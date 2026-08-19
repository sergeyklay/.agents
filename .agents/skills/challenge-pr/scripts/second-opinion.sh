#!/bin/sh
# second-opinion.sh - run a diff past a second model and print its
# findings as a JSON envelope on stdout.
#
# The only file in the challenge-pr skill that names a provider; the
# skill prose stays vendor-neutral. Supporting another provider means
# another branch in the case below and its own prompt file - nothing
# else in the skill changes.
#
# The diff is cut into units and each unit is its own provider call;
# the findings of every unit are merged into one envelope. Measured
# against an eight-defect reference on one pull request: the whole diff
# in a single call returned nothing at all, in eighteen runs across
# every context configuration tried, while units under 150 changed
# lines returned 143 findings, 20 of which survived a check against the
# code and 4 of which matched a reference defect.
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

# Longest unit handed to the provider, in changed (+/-) lines. 150 is
# the measured threshold: the same diff whole found nothing, cut this
# way it found four of the eight reference defects. A file under the
# threshold is one unit; a larger file is cut hunk by hunk, and a hunk
# over the threshold into sub-hunks.
UNIT_MAX_CHANGED_LINES=150

# Model class is what completeness turned on once the diff was cut: the
# Pro-class model found four reference defects where the flash-class
# model found one, for 1.56x the tokens. Overridable with --model.
MODEL=gemini-3.1-pro-preview

PROVIDER=gemini
DIFF_FILE=
PROMPT_FILE=

usage() {
    cat <<EOF
Usage: $(basename "$0") --diff-file FILE --prompt-file FILE
                        [--model NAME] [--provider NAME]

Obtain an independent review of a diff from a second model.

Options:
  --diff-file FILE    Unified diff to review. Cut into units of under
                      $UNIT_MAX_CHANGED_LINES changed lines, one provider call each.
  --prompt-file FILE  Reviewer instructions and output schema.
  --model NAME        Model to request (default: $MODEL).
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

# Remove the throwaway root and everything the run put in it: the units
# the diff was cut into, the provider's home with the copied credential
# in it, and the raw output. The provider keys its session stores to the
# directory it ran in and writes them under its own home, so with that
# home inside this root there is nothing of the run left anywhere else -
# no tmp/<slug>, no history/<slug>, no registry entry, and no session
# of somebody else's to tell them apart from.
gemini_cleanup() {
    tmproot=$1
    [ -n "$tmproot" ] || return 0
    rm -rf -- "$tmproot"
}

# Cut the diff into units of under UNIT_MAX_CHANGED_LINES changed lines
# and print one unit path per line, in diff order.
#
# A unit keeps the diff --git header block of the file it came from and
# whole @@ hunks under it, so it is a valid unified diff on its own and
# every path and line number the model quotes is the one the caller will
# read. A hunk that is itself over the threshold is cut into sub-hunks
# with recomputed @@ counts. A file whose header carries no hunk at all
# - a rename, a mode change - still becomes a unit, so no changed path
# disappears between the diff and the calls.
slice_diff() {
    awk -v limit="$UNIT_MAX_CHANGED_LINES" -v outdir="$1" '
function changed(l) {
    if (substr(l, 1, 1) == "+") return substr(l, 1, 3) != "+++"
    if (substr(l, 1, 1) == "-") return substr(l, 1, 3) != "---"
    return 0
}
function newunit(    path, k) {
    nunit++
    path = sprintf("%s/u%04d.diff", outdir, nunit)
    for (k = 1; k <= nfh; k++) print fh[k] > path
    print path
    return path
}
function parse(h,    t, p, spec, side, old, new) {
    t = substr(h, 4)
    p = index(t, " @@")
    spec = substr(t, 1, p - 1)
    tail = substr(t, p + 3)
    split(spec, side, " ")
    old = substr(side[1], 2)
    new = substr(side[2], 2)
    sub(",.*", "", old)
    sub(",.*", "", new)
    ostart = old + 0
    nstart = new + 0
}
function flush(    i, j, k, total, path, ao, an, co, cn, pa, pb, curn, curc, c1) {
    if (nfh == 0) return
    total = 0
    for (i = 1; i <= nh; i++) total += hc[i]
    if (total < limit) {
        path = newunit()
        for (i = 1; i <= nh; i++) {
            print hh[i] > path
            for (j = 1; j <= nb[i]; j++) print hb[i, j] > path
        }
        close(path)
        return
    }
    for (i = 1; i <= nh; i++) {
        if (hc[i] < limit) {
            path = newunit()
            print hh[i] > path
            for (j = 1; j <= nb[i]; j++) print hb[i, j] > path
            close(path)
            continue
        }
        parse(hh[i])
        co = ostart; cn = nstart; ao = ostart; an = nstart
        curn = 0; curc = 0; pa = 0; pb = 0
        for (j = 1; j <= nb[i]; j++) {
            cur[++curn] = hb[i, j]
            c1 = substr(hb[i, j], 1, 1)
            if (c1 == " " || hb[i, j] == "") { co++; cn++; pa++; pb++ }
            else if (c1 == "-") { co++; pa++ }
            else if (c1 == "+") { cn++; pb++ }
            if (changed(hb[i, j])) curc++
            if (curc >= limit - 10) {
                path = newunit()
                printf "@@ -%d,%d +%d,%d @@%s\n", ao, pa, an, pb, tail > path
                for (k = 1; k <= curn; k++) print cur[k] > path
                close(path)
                ao = co; an = cn; curn = 0; curc = 0; pa = 0; pb = 0
            }
        }
        if (curn > 0) {
            path = newunit()
            printf "@@ -%d,%d +%d,%d @@%s\n", ao, pa, an, pb, tail > path
            for (k = 1; k <= curn; k++) print cur[k] > path
            close(path)
        }
    }
}
/^diff --git / { flush(); nfh = 1; fh[1] = $0; nh = 0; inhunk = 0; started = 1; next }
started != 1   { next }
/^@@/          { nh++; hh[nh] = $0; nb[nh] = 0; hc[nh] = 0; inhunk = 1; next }
inhunk == 0    { fh[++nfh] = $0; next }
               { nb[nh]++; hb[nh, nb[nh]] = $0; if (changed($0)) hc[nh]++ }
END            { flush() }
' < "$DIFF_FILE"
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

# One unit, one call, and one retry before the whole envelope fails.
# The retry is not decoration: a single call failed about four times in
# a hundred over the measured runs, and a pull request cut into 38 units
# would then lose four runs in five to one bad call. A unit that fails
# twice takes the envelope down with it, because findings from the units
# that did answer would otherwise reach the reader as a complete review
# with an undisclosed hole in it.
run_unit() {
    unitfile=$1
    label=$2
    outfile=$3

    attempt=1
    while :; do
        status=0
        ( cd "$workdir" && gemini --skip-trust --policy "$policy" \
            -m "$MODEL" -o json -p "$prompt" ) \
            < "$unitfile" > "$raw" 2>"$errlog" || status=$?

        # A rule the provider refuses to compile - an unsafe regex, an
        # unknown tool name - is dropped from the policy, reported on
        # stderr and otherwise ignored: the run continues under whatever
        # rules survived and still exits 0. Losing a rule silently is
        # the one failure this script must not swallow, and retrying is
        # pointless because every unit loads the same policy file.
        if grep -q 'Policy file error' "$errlog"; then
            fail_soft "policy rejected: $(tr '\n' ' ' < "$errlog" | cut -c1-300)"
        fi

        if [ "$status" -ne 0 ]; then
            reason="gemini exited $status: $(tr '\n' ' ' < "$errlog" | cut -c1-300)"
        else
            reason=
            # A denied tool call ends the run with an empty response, an
            # error field and exit 0. Findings that will not parse are
            # therefore reported as a failure, never as "the second
            # model found nothing".
            jq -n --slurpfile raw "$raw" '
                ($raw[0] // {}) as $r
                | ([($r.stats.models // {}) | to_entries[]
                    | select((.value.api.totalRequests // 0) > 0) | .key]
                   | join(", ")) as $served
                | (if $served == "" then null else $served end) as $model
                | (($r.response // "")
                    | sub("^\\s*```[a-zA-Z]*\\s*"; "")
                    | sub("\\s*```\\s*$"; "")
                    | (fromjson? // null)) as $parsed
                | if ($parsed | type) == "object" and ($parsed.findings | type) == "array"
                  then {model: $model, findings: $parsed.findings, error: null}
                  else {model: $model, findings: [],
                        error: ("provider returned no parseable findings"
                                + (if ($r.error.message // "") == "" then ""
                                   else ": " + $r.error.message end))}
                  end
            ' > "$outfile" || reason="provider output was not valid JSON"
            [ -n "$reason" ] || reason=$(jq -r '.error // ""' "$outfile")
        fi

        [ -n "$reason" ] || return 0
        [ "$attempt" -lt 2 ] || fail_soft "$label: $reason"
        attempt=$((attempt + 1))
    done
}

run_gemini() {
    command -v gemini >/dev/null 2>&1 || fail_soft "gemini not found on PATH"

    policy="$SCRIPT_DIR/../assets/deny-tools.toml"
    [ -f "$policy" ] || die "policy file missing: $policy"

    prompt=$(cat -- "$PROMPT_FILE")

    tmproot=$(mktemp -d) || die "mktemp failed"
    trap 'gemini_cleanup "$tmproot"' EXIT INT TERM

    # The provider appends every prompt - every unit of the diff with it
    # - to a plaintext session log keyed by the directory it ran in.
    # Invoking from a throwaway directory keeps a private diff out of any
    # real project's history; the trap then takes the log away with it.
    # The directory stays empty: the model gets the unit on stdin and
    # has no tool with which to read anything anyway.
    #
    # The provider home is a sibling of that directory rather than a
    # directory inside it. One root still means one thing to remove if
    # the process is killed outright, but the copied credential stays
    # outside the tree the model runs in.
    workdir="$tmproot/work"
    clihome="$tmproot/clihome"
    units="$tmproot/units"
    mkdir -p "$workdir" "$clihome" "$units"
    gemini_home "$clihome"

    slice_diff "$units" > "$tmproot/units.list" \
        || fail_soft "could not cut $DIFF_FILE into units"
    total=$(wc -l < "$tmproot/units.list")
    [ "$total" -gt 0 ] \
        || fail_soft "no reviewable units in $DIFF_FILE: no diff --git header found"

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
    #   with empty stdout, and a fresh directory is untrusted by
    #   definition.
    # --policy: denies every tool, see assets/deny-tools.toml.
    # -m names an alias the service may resolve however it likes, and
    #   the model misreports itself when asked, so the served model is
    #   read back from the response below instead of echoed from here.
    n=0
    while IFS= read -r unitfile; do
        n=$((n + 1))
        run_unit "$unitfile" "unit $n of $total" \
            "$(printf '%s/unit-%04d.json' "$tmproot" "$n")"
    done < "$tmproot/units.list"

    envelope=$(jq -s --arg provider "$PROVIDER" '
        ([.[].model | select(. != null)] | unique | join(", ")) as $served
        | {provider: $provider,
           model_served: (if $served == "" then null else $served end),
           findings: (map(.findings) | add),
           error: null}
    ' "$tmproot"/unit-*.json) || fail_soft "could not merge the unit findings"

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
            --model)
                [ $# -ge 2 ] || die "option requires a value: $1"
                MODEL=$2
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
    [ -n "$MODEL" ]       || die "missing value for --model"
    command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

    case $PROVIDER in
        gemini) run_gemini ;;
        *)      die "unsupported provider: $PROVIDER (implemented: gemini)" ;;
    esac
}

main "$@"
