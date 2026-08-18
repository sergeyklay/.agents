#!/bin/sh
# second-opinion.sh - run a diff past a second model and print its
# findings as a JSON envelope on stdout.
#
# The only file in the challenge-pr skill that names a provider; the
# skill prose stays vendor-neutral. Supporting another provider means
# another branch in the case below and its own prompt file - nothing
# else in the skill changes.
#
# Envelope, always a single JSON object:
#   {"provider":"...","model_served":"..."|null,"findings":[...],"error":null|"..."}
#
# Exit 0 whenever an envelope was printed, provider failures included:
# the caller degrades to a one-provider review and should not have to
# read shell exit codes to notice. Exit 1 covers usage errors and a
# missing jq, where no envelope can be produced at all.

set -eu

SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)

PROVIDER=gemini
DIFF_FILE=
PROMPT_FILE=

usage() {
    cat <<EOF
Usage: $(basename "$0") --diff-file FILE --prompt-file FILE [--provider NAME]

Obtain an independent review of a diff from a second model.

Options:
  --diff-file FILE    Unified diff to review.
  --prompt-file FILE  Reviewer instructions and output schema.
  --provider NAME     Second-opinion provider (default: gemini).
  -h, --help          Show this help and exit.
EOF
}

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Report a provider failure through the envelope rather than the exit
# status, so a caller that only reads stdout still learns why the
# second opinion is missing.
fail_soft() {
    jq -n --arg provider "$PROVIDER" --arg error "$1" \
        '{provider: $provider, model_served: null, findings: [], error: $error}'
    exit 0
}

# Remove the throwaway working directory and every provider store
# keyed to it. There are two, not one: the provider stamps a
# .project_root marker into both tmp/<slug> and history/<slug> the
# moment it resolves a slug for the directory, so a run that only
# sweeps tmp leaves a history entry behind on every invocation.
# Candidates are matched by reading each .project_root instead of
# deriving the name from the path: the provider rewrites and lowercases
# the basename, appends -1, -2 on collision, and every other entry in
# both stores is somebody else's session.
#
# The provider also records the directory in its project registry.
# That entry is left behind deliberately: it holds a path and no
# content, and rewriting a file shared with every concurrent provider
# process would trade litter for a lost-update race.
gemini_cleanup() {
    workdir=$1
    [ -n "$workdir" ] || return 0
    if [ -n "${HOME:-}" ]; then
        for store in "$HOME/.gemini/tmp" "$HOME/.gemini/history"; do
            [ -d "$store" ] || continue
            for session in "$store"/*/; do
                [ -f "$session.project_root" ] || continue
                [ "$(cat "$session.project_root")" = "$workdir" ] || continue
                rm -rf -- "$session"
            done
        done
    fi
    rm -rf -- "$workdir"
}

run_gemini() {
    command -v gemini >/dev/null 2>&1 || fail_soft "gemini not found on PATH"

    policy="$SCRIPT_DIR/../assets/deny-tools.toml"
    [ -f "$policy" ] || die "policy file missing: $policy"

    prompt=$(cat -- "$PROMPT_FILE")

    workdir=$(mktemp -d) || die "mktemp failed"
    # The provider appends every prompt - the whole diff with it - to a
    # plaintext session log keyed by the directory it ran in. Invoking
    # from a throwaway directory keeps a private diff out of any real
    # project's history and denies the model this repository as ambient
    # context; the trap then takes both the directory and that log away.
    trap 'gemini_cleanup "$workdir"' EXIT INT TERM

    raw="$workdir/raw.json"
    errlog="$workdir/stderr.txt"

    # --skip-trust: headless runs in an untrusted directory exit 55
    #   with empty stdout, and a fresh mktemp directory is untrusted by
    #   definition.
    # --policy: denies every tool, see assets/deny-tools.toml.
    # -m names an alias the service resolves however it likes, and the
    #   model misreports itself when asked, so the served model is read
    #   back from the response below instead of echoed from here.
    status=0
    ( cd "$workdir" && gemini --skip-trust --policy "$policy" \
        -m gemini-flash-latest -o json -p "$prompt" ) \
        < "$DIFF_FILE" > "$raw" 2>"$errlog" || status=$?

    if [ "$status" -ne 0 ]; then
        fail_soft "gemini exited $status: $(tr '\n' ' ' < "$errlog" | cut -c1-300)"
    fi

    # A denied tool call ends the run with an empty response, an error
    # field and exit 0. Findings that will not parse are therefore
    # reported as a failure, never as "the second model found nothing".
    envelope=$(jq -n --arg provider "$PROVIDER" --slurpfile raw "$raw" '
        ($raw[0] // {}) as $r
        | ([($r.stats.models // {}) | to_entries[]
            | select((.value.api.totalRequests // 0) > 0) | .key] | join(", ")) as $served
        | (if $served == "" then null else $served end) as $model
        | (($r.response // "")
            | sub("^\\s*```[a-zA-Z]*\\s*"; "")
            | sub("\\s*```\\s*$"; "")
            | (fromjson? // null)) as $parsed
        | if ($parsed | type) == "object" and ($parsed.findings | type) == "array"
          then {provider: $provider, model_served: $model,
                findings: $parsed.findings, error: null}
          else {provider: $provider, model_served: $model, findings: [],
                error: ("provider returned no parseable findings"
                        + (if ($r.error.message // "") == "" then ""
                           else ": " + $r.error.message end))}
          end
    ') || fail_soft "provider output was not valid JSON"

    printf '%s\n' "$envelope"
}

main() {
    while [ $# -gt 0 ]; do
        case $1 in
            --diff-file)
                [ $# -ge 2 ] || die "option requires a value: $1"
                DIFF_FILE=$2
                shift 2
                ;;
            --prompt-file)
                [ $# -ge 2 ] || die "option requires a value: $1"
                PROMPT_FILE=$2
                shift 2
                ;;
            --provider)
                [ $# -ge 2 ] || die "option requires a value: $1"
                PROVIDER=$2
                shift 2
                ;;
            -h|--help) usage; exit 0 ;;
            -*)        die "unknown option: $1" ;;
            *)         die "unexpected argument: $1" ;;
        esac
    done

    [ -n "$DIFF_FILE" ]   || die "missing required option: --diff-file"
    [ -n "$PROMPT_FILE" ] || die "missing required option: --prompt-file"
    [ -f "$DIFF_FILE" ]   || die "diff file not found: $DIFF_FILE"
    [ -s "$DIFF_FILE" ]   || die "diff file is empty: $DIFF_FILE"
    [ -f "$PROMPT_FILE" ] || die "prompt file not found: $PROMPT_FILE"
    command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

    case $PROVIDER in
        gemini) run_gemini ;;
        *)      die "unsupported provider: $PROVIDER (implemented: gemini)" ;;
    esac
}

main "$@"
