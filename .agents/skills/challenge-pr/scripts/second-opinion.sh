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
BASE_SHA=

usage() {
    cat <<EOF
Usage: $(basename "$0") --diff-file FILE --prompt-file FILE --base-sha SHA
                        [--provider NAME]

Obtain an independent review of a diff from a second model.

Options:
  --diff-file FILE    Unified diff to review.
  --prompt-file FILE  Reviewer instructions and output schema.
  --base-sha SHA      Commit the diff applies to. Exported from the
                      repository in the current directory and handed to
                      the model as its working directory.
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

# Remove the throwaway root and everything the run put in it: the
# checkout, the provider's home with the copied credential in it, and
# the raw output. The provider keys its session stores to the directory
# it ran in and writes them under its own home, so with that home
# inside this root there is nothing of the run left anywhere else -
# no tmp/<slug>, no history/<slug>, no registry entry, and no session
# of somebody else's to tell them apart from.
gemini_cleanup() {
    tmproot=$1
    [ -n "$tmproot" ] || return 0
    rm -rf -- "$tmproot"
}

# Export the base commit into the directory the model will work in.
#
# The base commit, not the pull request's head: the checkout then holds
# the code the change lands on and nothing the pull request itself
# introduces, so a symlink or a context file added by the branch under
# review never reaches the run.
#
# .git is not part of an archive to begin with. .tool-versions is
# dropped because the provider's version resolves from the working
# directory, and a copy of that file would silently move the run to
# another installation. .gemini is dropped because a project-level
# provider directory would put settings and context back into the
# prompt this run exists to keep out of it.
export_checkout() {
    checkout=$1
    archive=$2
    git archive --format=tar -o "$archive" "$BASE_SHA" \
        -- . ':(exclude).tool-versions' ':(exclude).gemini' 2>"$archive.err" \
        || fail_soft "git archive failed for $BASE_SHA in $(pwd): $(tr '\n' ' ' < "$archive.err" | cut -c1-200)"
    tar -xf "$archive" -C "$checkout" || fail_soft "could not unpack $BASE_SHA"
    rm -f -- "$archive"
}

# Build a provider home that holds nothing but what authentication
# needs. GEMINI_CLI_HOME replaces the parent of the provider's state
# directory, so a throwaway value takes the operator's skills, agent
# definitions, MCP server instructions and personal policy out of the
# prompt with it - 10582 prompt tokens down to 4727 - and leaves this
# run's state where the trap can reach it.
#
# Two files are the measured minimum: the selected authentication type,
# and the credential store that type reads. The type is not copied from
# the operator's settings, because that file is rewritten by whatever
# installs configuration and a run that inherits it degrades the moment
# somebody else's deploy lands. It is derived from the store present on
# disk instead, so the run states its own precondition and fails with
# the missing store rather than with a stale choice.
gemini_home() {
    clihome=$1
    [ -n "${HOME:-}" ] || fail_soft "HOME is not set, cannot read provider settings"
    src="$HOME/.gemini"
    auth=gemini-api-key
    [ -f "$src/gemini-credentials.json" ] \
        || fail_soft "credential store not found: $src/gemini-credentials.json; this script carries only $auth into a throwaway provider home"

    mkdir -p "$clihome/.gemini"
    jq -n --arg auth "$auth" '{security: {auth: {selectedType: $auth}}}' \
        > "$clihome/.gemini/settings.json"
    cp -- "$src/gemini-credentials.json" "$clihome/.gemini/gemini-credentials.json"
    chmod 600 "$clihome/.gemini/gemini-credentials.json"
}

run_gemini() {
    command -v gemini >/dev/null 2>&1 || fail_soft "gemini not found on PATH"

    policy="$SCRIPT_DIR/../assets/deny-tools.toml"
    [ -f "$policy" ] || die "policy file missing: $policy"

    prompt=$(cat -- "$PROMPT_FILE")

    tmproot=$(mktemp -d) || die "mktemp failed"
    # The home-anchored deny rules match any path under $HOME carrying a
    # glob metacharacter, so a checkout below $HOME would silently refuse
    # every glob and every bracketed filename a framework produces, such
    # as a Next.js dynamic route. TMPDIR decides where mktemp lands, so
    # refuse the run rather than inherit a policy that half-works.
    case "$tmproot" in
        "$HOME"/*) rm -rf -- "$tmproot"
                   die "TMPDIR resolves under \$HOME ($tmproot); set TMPDIR outside the home directory" ;;
    esac
    trap 'gemini_cleanup "$tmproot"' EXIT INT TERM

    # The provider appends every prompt - the whole diff with it - to a
    # plaintext session log keyed by the directory it ran in. Invoking
    # from a throwaway checkout keeps a private diff out of any real
    # project's history; the trap then takes the log away with it.
    #
    # The provider home is a sibling of that checkout rather than a
    # directory inside it. One root still means one thing to remove if
    # the process is killed outright, but the copied credential stays
    # outside the tree the model is allowed to read.
    checkout="$tmproot/checkout"
    clihome="$tmproot/clihome"
    mkdir -p "$checkout" "$clihome"
    export_checkout "$checkout" "$tmproot/checkout.tar"
    gemini_home "$clihome"

    raw="$tmproot/raw.json"
    errlog="$tmproot/stderr.txt"

    GEMINI_CLI_HOME="$clihome"
    export GEMINI_CLI_HOME
    # Nothing below is safe without it: unset, the provider reads the
    # operator's global configuration and writes this run's session
    # state into the operator's home, where the trap above does not
    # reach.
    [ -n "${GEMINI_CLI_HOME:-}" ] || die "GEMINI_CLI_HOME is not set"

    # --skip-trust: headless runs in an untrusted directory exit 55
    #   with empty stdout, and a fresh checkout is untrusted by
    #   definition.
    # --policy: denies every tool but the read-only four, see
    #   assets/deny-tools.toml.
    # -m names an alias the service resolves however it likes, and the
    #   model misreports itself when asked, so the served model is read
    #   back from the response below instead of echoed from here.
    status=0
    ( cd "$checkout" && gemini --skip-trust --policy "$policy" \
        -m gemini-flash-latest -o json -p "$prompt" ) \
        < "$DIFF_FILE" > "$raw" 2>"$errlog" || status=$?

    if [ "$status" -ne 0 ]; then
        fail_soft "gemini exited $status: $(tr '\n' ' ' < "$errlog" | cut -c1-300)"
    fi

    # A rule the provider refuses to compile - an unsafe regex, an
    # unknown tool name - is dropped from the policy, reported on stderr
    # and otherwise ignored: the run continues under whatever rules
    # survived and still exits 0. Losing a rule silently is the one
    # failure this script must not swallow.
    if grep -q 'Policy file error' "$errlog"; then
        fail_soft "policy rejected: $(tr '\n' ' ' < "$errlog" | cut -c1-300)"
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
            --base-sha)
                [ $# -ge 2 ] || die "option requires a value: $1"
                BASE_SHA=$2
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
    [ -n "$BASE_SHA" ]    || die "missing required option: --base-sha"
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
