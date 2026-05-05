#!/bin/sh
# sync — mirror agent assets from this repository into host-specific
# directories under $HOME.
#
# Per-host overlay: when templates/<vendor>/<name>.yaml exists, its
# top-level keys are merged onto the agent's frontmatter before the
# mirror, replacing matching source fields and adding the rest. The
# vendor token matches the destination's hidden-directory name
# (.claude, .copilot, .gemini); a missing template yields a verbatim
# copy.

set -eu

SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH="" cd -- "$SCRIPT_DIR/.." && pwd)

# Sync kinds dispatched by main; --all expands to this list.
ALL_ACTIONS='agents commands hooks instructions settings skills'

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Install agent assets from this repository to user home.

Options:
  --all           Install all.
  --agents        Install agents to user home.
  --commands      Install commands to user home.
  --hooks         Install agent hooks to user home.
  --instructions  Install agent instructions to user home.
  --settings      Install agents settings to user home.
  --skills        Install skills to registered skill destinations.
  -h, --help      Show this help and exit.
EOF
}

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Print the canonical absolute path of $1, resolving symlinks one
# component at a time. POSIX-only: realpath and readlink -f differ
# between GNU and BSD.
canonical_path() {
    if [ -d "$1" ]; then
        ( CDPATH="" cd -- "$1" && pwd -P )
    elif [ -L "$1" ]; then
        target=$(readlink -- "$1")
        case "$target" in
            /*) canonical_path "$target" ;;
            *)  canonical_path "$(dirname -- "$1")/$target" ;;
        esac
    elif [ -f "$1" ]; then
        printf '%s/%s\n' "$( CDPATH="" cd -- "$(dirname -- "$1")" && pwd -P )" "$(basename -- "$1")"
    fi
}

# Mirror $1 into $2; arguments after $2 are forwarded to rsync. A
# directory source uses rsync --delete; a file source is copied.
# Skipped when $2's parent directory is absent, or when $1 and $2
# resolve to the same canonical path. SYNC_TO_LABEL, when set,
# replaces $1 in log output. Flag set is restricted to the rsync
# features shared by macOS's stock 2.6.9 and modern Linux builds.
sync_to() {
    src=$1
    dst=$2
    shift 2
    label=${SYNC_TO_LABEL:-$src}
    parent=$(dirname -- "$dst")
    if [ ! -d "$parent" ]; then
        printf '  skip: %s -> %s (no %s)\n' "$label" "$dst" "$parent"
        return 0
    fi
    if [ -e "$dst" ] && [ "$(canonical_path "$src")" = "$(canonical_path "$dst")" ]; then
        printf '  skip: %s -> %s (symlink to source)\n' "$label" "$dst"
        return 0
    fi
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        rsync -a --delete "$@" "$src/" "$dst/"
    elif [ -f "$src" ]; then
        rsync -a "$@" "$src" "$dst"
    else
        die "source missing: $src"
    fi
    printf '  %s -> %s\n' "$label" "$dst"
}

# Return 0 when mikefarah/yq v4 is on PATH. Other yq forks share the
# binary name but use incompatible expression syntax, so version
# gating is mandatory.
detect_yq() {
    command -v yq >/dev/null 2>&1 || return 1
    case "$(yq --version 2>/dev/null)" in
        *mikefarah*v4.*) return 0 ;;
    esac
    return 1
}

# Split $1 (markdown with optional leading YAML frontmatter) into the
# frontmatter at $2 and the body at $3. The surrounding `---` markers
# are stripped. A file with no frontmatter leaves $2 empty and writes
# its full content to $3.
split_frontmatter() {
    awk -v fm="$2" -v body="$3" '
        BEGIN { state = "pre" }
        state == "pre" && NR == 1 && /^---$/ { state = "fm"; next }
        state == "pre"                      { state = "body"; print > body; next }
        state == "fm"  && /^---$/           { state = "body"; next }
        state == "fm"                       { print > fm; next }
        state == "body"                     { print > body }
    ' "$1"
}

# Overlay $1's frontmatter with $2 using mikefarah/yq's deep-merge
# operator (RHS-priority, array replace). The result is written to $3
# with the body preserved verbatim. Quoted keys, anchors, and multi-
# line scalars round-trip.
# https://mikefarah.gitbook.io/yq/operators/multiply-merge
#
# This and the sibling overlay backends run in subshell scope so their
# variable assignments do not propagate to the caller.
overlay_with_yq() (
    src=$1
    tmpl=$2
    dst=$3

    fm=$(mktemp) || die "mktemp failed"
    body=$(mktemp) || die "mktemp failed"
    merged=$(mktemp) || die "mktemp failed"

    split_frontmatter "$src" "$fm" "$body"
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        "$fm" "$tmpl" > "$merged" \
        || die "yq merge failed: $tmpl onto $src"

    {
        printf -- '---\n'
        cat -- "$merged"
        printf -- '---\n'
        cat -- "$body"
    } > "$dst"

    rm -f -- "$fm" "$body" "$merged"
)

# Pure-POSIX awk overlay backend. Recognises top-level keys matching
# /^[A-Za-z_][A-Za-z_0-9-]*:/ at column zero; multi-line values
# continue until the next top-level key. YAML document markers
# (`---`, `...`) inside the template are dropped. Quoted keys,
# anchors, and multi-document YAML are unsupported.
overlay_with_awk() (
    src=$1
    tmpl=$2
    dst=$3

    awk -v tmpl="$tmpl" '
        BEGIN {
            while ((getline line < tmpl) > 0) {
                if (line == "---" || line == "...") continue
                tmpl_fm[++tn] = line
                if (match(line, /^[A-Za-z_][A-Za-z_0-9-]*:/)) {
                    key = substr(line, 1, RLENGTH - 1)
                    tmpl_keys[key] = 1
                }
            }
            close(tmpl)
            state = "pre"
        }
        state == "pre" && $0 == "---" { state = "fm"; print; next }
        state == "fm"  && $0 == "---" {
            for (i = 1; i <= tn; i++) print tmpl_fm[i]
            state = "body"
            print
            next
        }
        state == "fm" {
            if (match($0, /^[A-Za-z_][A-Za-z_0-9-]*:/)) {
                key = substr($0, 1, RLENGTH - 1)
                skip_block = (key in tmpl_keys) ? 1 : 0
            }
            if (!skip_block) print
            next
        }
        { print }
    ' "$src" > "$dst"
)

# Apply $2's overlay to $1's frontmatter; write the result to $3.
# Selects the yq backend when available, otherwise the awk backend.
# A missing $2 yields a verbatim copy of $1.
frontmatter_overlay() (
    src=$1
    tmpl=$2
    dst=$3

    if [ ! -f "$tmpl" ]; then
        cp -- "$src" "$dst"
        return 0
    fi

    if detect_yq; then
        overlay_with_yq "$src" "$tmpl" "$dst"
    else
        overlay_with_awk "$src" "$tmpl" "$dst"
    fi
)

# Stage an overlaid file and mirror it to $dst. $kind is a path under
# templates/ (e.g. ".copilot/agents", ".gemini/commands"); templates/
# <kind>/<name>.yaml is the per-file frontmatter overlay, and templates/
# <kind>/<name>.body.md, if present, is appended to the body — used for
# host-specific footers like ${input:...} or {{args}} whose syntax
# varies per host. Both overlays are independently optional. Output
# format is selected by the destination extension: .toml dispatches to
# sync_view_toml (Gemini schema with description + prompt), anything
# else uses sync_view_md (markdown with merged YAML frontmatter and
# body). $src is the source markdown; $dst is the host destination.
# Logged as <kind>/<name>.
sync_view() {
    case "$3" in
        *.toml) sync_view_toml "$1" "$2" "$3" ;;
        *)      sync_view_md   "$1" "$2" "$3" ;;
    esac
}

sync_view_md() {
    kind=$1
    src=$2
    dst=$3
    name=$(basename -- "$src" .md)
    tmpl="$REPO_ROOT/templates/$kind/$name.yaml"
    suffix="$REPO_ROOT/templates/$kind/$name.body.md"

    tmp=$(mktemp) || die "mktemp failed"
    frontmatter_overlay "$src" "$tmpl" "$tmp"
    if [ -f "$suffix" ]; then
        printf '\n' >> "$tmp"
        cat -- "$suffix" >> "$tmp"
    fi
    SYNC_TO_LABEL="$kind/$name"
    sync_to "$tmp" "$dst"
    unset SYNC_TO_LABEL
    rm -f -- "$tmp"
}

# Emit a Gemini-flavoured TOML command (schema: description + prompt)
# from the source markdown's frontmatter and body. Description comes
# from the merged YAML frontmatter as a single-line scalar and is
# emitted as a TOML basic string with " and \ escaped. Prompt is body
# plus optional .body.md suffix, emitted as a TOML literal multiline
# string ('''...''') so that backslashes and ${...} / {{...}}
# placeholders pass through verbatim. Source bodies must not contain
# the literal '''; markdown uses ``` for code fences, so this holds.
sync_view_toml() {
    kind=$1
    src=$2
    dst=$3
    name=$(basename -- "$src" .md)
    tmpl="$REPO_ROOT/templates/$kind/$name.yaml"
    suffix="$REPO_ROOT/templates/$kind/$name.body.md"

    merged=$(mktemp) || die "mktemp failed"
    fm=$(mktemp) || die "mktemp failed"
    body=$(mktemp) || die "mktemp failed"
    frontmatter_overlay "$src" "$tmpl" "$merged"
    split_frontmatter "$merged" "$fm" "$body"

    description=$(awk '
        /^description:/ {
            sub(/^description:[[:space:]]*/, "")
            if (sub(/^"/, "")) sub(/"$/, "")
            else if (sub(/^\047/, "")) sub(/\047$/, "")
            print
            exit
        }
    ' "$fm")
    description_escaped=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')

    tmp=$(mktemp) || die "mktemp failed"
    {
        printf 'description = "%s"\n' "$description_escaped"
        printf "prompt = '''\n"
        cat -- "$body"
        if [ -f "$suffix" ]; then
            printf '\n'
            cat -- "$suffix"
        fi
        printf "'''\n"
    } > "$tmp"

    SYNC_TO_LABEL="$kind/$name"
    sync_to "$tmp" "$dst"
    unset SYNC_TO_LABEL

    rm -f -- "$merged" "$fm" "$body" "$tmp"
}

sync_agents() {
    printf 'syncing agents...\n'

    src_dir="$REPO_ROOT/.agents/agents"
    [ -d "$src_dir" ] || die "source missing: $src_dir"

    # Pre-create agents/ in each installed host so the per-file mirrors
    # below are not skipped on a missing parent. Gating on root
    # existence keeps uninstalled hosts un-bootstrapped.
    for root in "$HOME/.claude" "$HOME/.copilot" "$HOME/.gemini"; do
        [ -d "$root" ] && mkdir -p "$root/agents"
    done

    for f in "$src_dir/"*.md; do
        [ -f "$f" ] || continue
        name=$(basename -- "$f" .md)

        sync_view ".claude/agents"  "$f" "$HOME/.claude/agents/$name.md"
        sync_view ".copilot/agents" "$f" "$HOME/.copilot/agents/$name.agent.md"
        sync_view ".gemini/agents"  "$f" "$HOME/.gemini/agents/$name.md"
    done
}

sync_commands() {
    printf 'syncing commands...\n'

    src_dir="$REPO_ROOT/.agents/commands"
    [ -d "$src_dir" ] || die "source missing: $src_dir"

    # Pre-create per-host destination directories so the per-file mirrors
    # below are not skipped on a missing parent. Each host gates itself
    # on its own root, so an uninstalled tool stays untouched.
    [ -d "$HOME/.claude" ]  && mkdir -p "$HOME/.claude/commands"
    [ -d "$HOME/.copilot" ] && mkdir -p "$HOME/.copilot/prompts"
    [ -d "$HOME/.gemini" ]  && mkdir -p "$HOME/.gemini/commands"

    for f in "$src_dir/"*.md; do
        [ -f "$f" ] || continue
        name=$(basename -- "$f" .md)

        # Claude: ~/.claude/commands/ is functionally equivalent to
        # ~/.claude/skills/<name>/SKILL.md per the docs and accepts the
        # same frontmatter, but stays out of --skills' --delete sweep
        # against .agents/skills/.
        sync_view ".claude/commands" "$f" "$HOME/.claude/commands/$name.md"

        # Copilot calls these "prompts" and uses the .prompt.md suffix.
        sync_view ".copilot/prompts" "$f" "$HOME/.copilot/prompts/$name.prompt.md"

        # Gemini commands are TOML files with `description` and `prompt`
        # keys; sync_view dispatches on the .toml extension.
        sync_view ".gemini/commands" "$f" "$HOME/.gemini/commands/$name.toml"
    done
}

sync_skills() {
    printf 'syncing skills...\n'

    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.claude/skills"
    # Codex preserves .system/ and other Codex-managed dot entries.
    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.codex/skills" --exclude='.*'
    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.copilot/skills"
    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.gemini/skills"
    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.config/opencode/skills"
}

sync_settings() {
    printf 'syncing settings...\n'

    sync_to "$REPO_ROOT/.claude/settings.json" "$HOME/.claude/settings.json"
    sync_to "$REPO_ROOT/.gemini/settings.user.json" "$HOME/.gemini/settings.json"
    sync_to "$REPO_ROOT/.gemini/policies" "$HOME/.gemini/policies"
}

sync_instructions() {
    printf 'syncing instructions...\n'

    sync_to "$REPO_ROOT/.copilot/instructions" "$HOME/.copilot/instructions"
}

sync_hooks() {
    printf 'syncing hooks...\n'

    sync_to "$REPO_ROOT/.claude/hooks" "$HOME/.claude/hooks"
}

main() {
    actions=
    while [ $# -gt 0 ]; do
        case $1 in
            --all)           actions="$actions $ALL_ACTIONS" ;;
            --agents)        actions="$actions agents" ;;
            --commands)      actions="$actions commands" ;;
            --hooks)         actions="$actions hooks" ;;
            --instructions)  actions="$actions instructions" ;;
            --skills)        actions="$actions skills" ;;
            --settings)      actions="$actions settings" ;;
            -h|--help)       usage; exit 0 ;;
            -*)              die "unknown option: $1" ;;
            *)               die "unexpected argument: $1" ;;
        esac
        shift
    done
    [ -n "$actions" ] || { usage >&2; exit 2; }
    # Dispatch in canonical order; the membership check drops
    # duplicates when --all is combined with individual flags.
    for action in $ALL_ACTIONS; do
        case " $actions " in *" $action "*) "sync_$action" ;; esac
    done
}

main "$@"
