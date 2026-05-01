#!/bin/sh
# sync — mirrors selected agent assets from this repo to external locations.
#
# To add a destination for an existing kind: append a `sync_to` line in the
# matching sync_<kind> function. To add a new kind: add a --flag case in
# main(), append the kind to ALL_ACTIONS, and define a corresponding
# sync_<kind> function below.

set -eu

SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH="" cd -- "$SCRIPT_DIR/.." && pwd)

# Master list of sync kinds — referenced by --all and the contract above.
ALL_ACTIONS='agents hooks instructions settings skills'

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Mirror agent assets from this repository to external locations.

Options:
  --all           Run every sync.
  --agents        Sync agents to home.
  --hooks         Sync agent hooks to home.
  --instructions  Sync agent instructions to home.
  --settings      Sync agents settings to home.
  --skills        Sync skills to registered skill destinations.
  -h, --help      Show this help and exit.
EOF
}

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Print the canonical absolute path of $1, resolving symlinks. Path
# components are resolved via cd-pwd-P; a symlink at the leaf is
# resolved one level via readlink and recursion. POSIX-only — avoids
# realpath / readlink -f, which differ between GNU and BSD.
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

# Mirror $1 into $2 (directory: recursive --delete; file: copy). Any
# extra arguments after $2 are forwarded to rsync — useful for
# per-destination flags such as --exclude, which doubles as a
# protect rule against --delete. The destination is skipped when (a)
# its parent directory is absent — the target tool isn't installed
# on this machine, so we won't bootstrap it; or (b) it already
# resolves through symlinks to the source — there's nothing to copy.
# Flag set is restricted to what rsync 2.6.9 (macOS default) and
# modern Linux share.
sync_to() {
    src=$1
    dst=$2
    shift 2
    parent=$(dirname -- "$dst")
    if [ ! -d "$parent" ]; then
        printf '  skip: %s (no %s)\n' "$dst" "$parent"
        return 0
    fi
    if [ -e "$dst" ] && [ "$(canonical_path "$src")" = "$(canonical_path "$dst")" ]; then
        printf '  skip: %s (symlink to source)\n' "$dst"
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
    printf '  %s -> %s\n' "$src" "$dst"
}

sync_agents() {
    printf 'syncing agents...\n'

    src_dir="$REPO_ROOT/.agents/agents"
    [ -d "$src_dir" ] || die "source missing: $src_dir"

    # Provision agents/ subdir for each installed agent so the per-file
    # sync_to calls below don't trip the "parent missing" skip rule.
    # Gating on root existence keeps us from bootstrapping a tool the
    # user doesn't have.
    for root in "$HOME/.claude" "$HOME/.copilot" "$HOME/.gemini"; do
        [ -d "$root" ] && mkdir -p "$root/agents"
    done

    for f in "$src_dir/"*.md; do
        [ -f "$f" ] || continue
        name=$(basename -- "$f" .md)

        # Claude
        sync_to "$f" "$HOME/.claude/agents/$name.md"

        # Copilot (uses .agent.md suffix per Copilot convention)
        sync_to "$f" "$HOME/.copilot/agents/$name.agent.md"

        # Gemini
        sync_to "$f" "$HOME/.gemini/agents/$name.md"
    done
}

sync_skills() {
    printf 'syncing skills...\n'

    # Claude
    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.claude/skills"

    # Codex: preserve .system/ and any other Codex-managed dot entries
    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.codex/skills" --exclude='.*'

    # Copilot
    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.copilot/skills"

    # Gemini
    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.gemini/skills"

    # OpenCode
    sync_to "$REPO_ROOT/.agents/skills" "$HOME/.config/opencode/skills"
}

sync_settings() {
    printf 'syncing settings...\n'

    # Claude
    sync_to "$REPO_ROOT/.claude/settings.json" "$HOME/.claude/settings.json"

    # Gemini
    sync_to "$REPO_ROOT/.gemini/settings.json" "$HOME/.gemini/settings.json"
    sync_to "$REPO_ROOT/.gemini/policies" "$HOME/.gemini/policies"
}

sync_instructions() {
    printf 'syncing instructions...\n'

    # Copilot
    sync_to "$REPO_ROOT/.copilot/instructions" "$HOME/.copilot/instructions"
}

sync_hooks() {
    printf 'syncing hooks...\n'

    # Claude
    sync_to "$REPO_ROOT/.claude/hooks" "$HOME/.claude/hooks"
}

main() {
    actions=
    while [ $# -gt 0 ]; do
        case $1 in
            --all)           actions="$actions $ALL_ACTIONS" ;;
            --agents)        actions="$actions agents" ;;
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
    # Dispatch in canonical order; the membership check drops duplicates
    # so --all combined with individual flags still runs each kind once.
    for action in $ALL_ACTIONS; do
        case " $actions " in *" $action "*) "sync_$action" ;; esac
    done
}

main "$@"
