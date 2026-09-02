#!/bin/sh
# sync — mirror agent assets from this repository into host-specific
# directories under $HOME.
#
# Per-host overlay: when templates/<vendor>/<kind>/<name>.yaml exists,
# its top-level keys are merged onto the source's frontmatter before
# the mirror, replacing matching source fields and adding the rest.
# <vendor> matches the destination's hidden-directory name (.claude,
# .copilot, .gemini); <kind> matches the destination subdirectory
# (agents, commands, prompts, instructions, rules, skills). For
# skills, the overlay rewrites only SKILL.md; supporting files under
# the skill directory mirror verbatim. Sources without frontmatter
# take the template wholesale; a missing template yields a verbatim
# copy.

set -eu

SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH="" cd -- "$SCRIPT_DIR/.." && pwd)

# Sync kinds and hosts dispatched by main. --all expands actions only;
# host options independently restrict destinations.
ALL_ACTIONS='agents commands hooks rules settings skills'
ALL_HOSTS='claude codex copilot gemini opencode'

# Formatting follows terminal capabilities and the NO_COLOR convention.
setup_formatting() {
    if [ -t 1 ] && [ "${TERM-}" != "dumb" ] && [ -z "${NO_COLOR-}" ]; then
	ESC=$(printf '\033')
	BOLD="${ESC}[1m"
	DIM="${ESC}[2m"
	RED="${ESC}[31m"
	GREEN="${ESC}[32m"
	YELLOW="${ESC}[33m"
	CYAN="${ESC}[36m"
	RESET="${ESC}[0m"
    else
	BOLD=
	DIM=
	RED=
	GREEN=
	YELLOW=
	CYAN=
	RESET=
    fi
}

info() {
    printf '%s::%s %s\n' "${BOLD}${CYAN}" "$RESET" "$*"
}

ok() {
    printf '%s::%s %s\n' "${BOLD}${GREEN}" "$RESET" "$*"
}

warn() {
    printf '%s-%s %s\n' "${BOLD}${YELLOW}" "$RESET" "$*"
}

err() {
    printf '%serror:%s %s\n' "${BOLD}${RED}" "$RESET" "$*" >&2
}

usage() {
    cat <<EOF

${BOLD}${CYAN}  .agents${RESET}
  ${DIM}Portable agent assets, installed where your tools expect them.${RESET}

${BOLD}Usage${RESET}
  $(basename "$0") ${CYAN}[asset options] [host options]${RESET}

${BOLD}Asset options${RESET}
  ${BOLD}${YELLOW}--all${RESET}       Install all asset types
  ${BOLD}${YELLOW}--agents${RESET}    Install agent definitions
  ${BOLD}${YELLOW}--commands${RESET}  Install commands and prompts
  ${BOLD}${YELLOW}--hooks${RESET}     Install agent hooks
  ${BOLD}${YELLOW}--rules${RESET}     Install agent rules and instructions
  ${BOLD}${YELLOW}--settings${RESET}  Install host settings
  ${BOLD}${YELLOW}--skills${RESET}    Install skills

${BOLD}Host options${RESET}
  ${BOLD}${YELLOW}--claude${RESET}    Target Claude Code
  ${BOLD}${YELLOW}--codex${RESET}     Target Codex
  ${BOLD}${YELLOW}--copilot${RESET}   Target GitHub Copilot
  ${BOLD}${YELLOW}--gemini${RESET}    Target Gemini CLI
  ${BOLD}${YELLOW}--opencode${RESET}  Target opencode

${BOLD}Other options${RESET}
  ${BOLD}${YELLOW}-h, --help${RESET}  Show this help and exit

${BOLD}Selection${RESET}
  Asset and host options intersect. Multiple host options are combined.
  With no asset option, all supported asset types are installed. With no
  host option, every registered host is targeted.

${BOLD}Examples${RESET}
  ${DIM}# Install every supported asset for Claude Code.${RESET}
  ${CYAN}bash scripts/install.sh --claude${RESET}

  ${DIM}# Install only agent definitions for opencode.${RESET}
  ${CYAN}bash scripts/install.sh --agents --opencode${RESET}

  ${DIM}# Install skills for Claude Code and Codex.${RESET}
  ${CYAN}bash scripts/install.sh --skills --claude --codex${RESET}

  ${DIM}# Install every asset type for every registered host.${RESET}
  ${CYAN}bash scripts/install.sh --all${RESET}

${BOLD}Environment${RESET}
  ${CYAN}NO_COLOR${RESET}   Disable color output (https://no-color.org/)
EOF
}

die() {
    err "$1"
    exit 1
}

host_selected() {
    case " $hosts " in
	*" $1 "*) return 0 ;;
    esac
    return 1
}

host_active() {
    host_selected "$1" && [ -d "$(host_root "$1")" ]
}

any_host_active() {
    for candidate do
	host_active "$candidate" && return 0
    done
    return 1
}

host_root() {
    case $1 in
	claude)   printf '%s/.claude\n' "$HOME" ;;
	codex)    printf '%s/.codex\n' "$HOME" ;;
	copilot)  printf '%s/.copilot\n' "$HOME" ;;
	gemini)   printf '%s/.gemini\n' "$HOME" ;;
	opencode) printf '%s/.config/opencode\n' "$HOME" ;;
    esac
}

host_name() {
    case $1 in
	claude)   printf 'Claude Code\n' ;;
	codex)    printf 'Codex\n' ;;
	copilot)  printf 'GitHub Copilot\n' ;;
	gemini)   printf 'Gemini CLI\n' ;;
	opencode) printf 'opencode\n' ;;
    esac
}

for_host() {
    selected_host=$1
    shift
    host_active "$selected_host" || return 0
    "$@"
}

join_words() {
    words=$1
    # Selection lists contain only installer-owned identifiers.
    # shellcheck disable=SC2086
    set -- $words
    separator=
    for word do
	printf '%s%s' "$separator" "$word"
	separator=', '
    done
}

canonical_selection() {
    selected=$1
    shift
    for candidate do
	case " $selected " in
	    *" $candidate "*) printf '%s ' "$candidate" ;;
	esac
    done
}

display_path() {
    path=$1
    case $path in
	"$HOME")        printf '~\n' ;;
	"$HOME"/*)      printf '%s/%s\n' '~' "${path#"$HOME"/}" ;;
	"$REPO_ROOT")   printf '.\n' ;;
	"$REPO_ROOT"/*) printf './%s\n' "${path#"$REPO_ROOT"/}" ;;
	*)               printf '%s\n' "$path" ;;
    esac
}

progress_section() {
    printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"
}

progress_updated() {
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
    printf '  %s+%s %s %s->%s %s\n' "$GREEN" "$RESET" \
	"$(display_path "$1")" "$DIM" "$RESET" "$(display_path "$2")"
}

progress_skipped() {
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    printf '  %s-%s %s %s(%s)%s\n' "$YELLOW" "$RESET" \
	"$(display_path "$1")" "$DIM" "$2" "$RESET"
}

print_plan() {
    info "Installing agent assets"
    printf '   %sAssets%s  %s\n' "$BOLD" "$RESET" "$(join_words "$actions")"
    printf '   %sHosts%s   %s\n' "$BOLD" "$RESET" "$(join_words "$hosts")"

    for candidate in $hosts; do
	candidate_root=$(host_root "$candidate")
	if [ ! -d "$candidate_root" ]; then
	    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
	    warn "$(host_name "$candidate") not found at $(display_path "$candidate_root"); skipping"
	fi
    done
}

ensure_subdir() {
    root=$1
    subdir=$2
    if [ -d "$root" ]; then
	mkdir -p "$root/$subdir"
    fi
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
	progress_skipped "$label" "destination directory missing: $(display_path "$parent")"
        return 0
    fi
    if [ -e "$dst" ] && [ "$(canonical_path "$src")" = "$(canonical_path "$dst")" ]; then
	progress_skipped "$label" "destination is a symlink to the source"
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
    progress_updated "$label" "$dst"
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
# A missing $2 yields a verbatim copy of $1. A $1 without leading
# `---` carries no frontmatter to merge, so the template content is
# wrapped in `---` markers and prepended to the body verbatim --
# the path taken by .agents/rules/, which keep all host-specific
# YAML in templates/<vendor>/<kind>/.
frontmatter_overlay() (
    src=$1
    tmpl=$2
    dst=$3

    if [ ! -f "$tmpl" ]; then
        cp -- "$src" "$dst"
        return 0
    fi

    if [ "$(head -n 1 -- "$src")" != "---" ]; then
        {
            printf -- '---\n'
            cat -- "$tmpl"
            printf -- '---\n'
            cat -- "$src"
        } > "$dst"
        return 0
    fi

    if detect_yq; then
        overlay_with_yq "$src" "$tmpl" "$dst"
    else
        overlay_with_awk "$src" "$tmpl" "$dst"
    fi
)

# Stage an overlaid file and mirror it to $dst. $kind is a path under
# templates/ (e.g. ".copilot/agents", ".gemini/commands"). For a given
# command/agent <name>, three optional template files apply:
#
#   <name>.yaml         - frontmatter overlay (deep-merged into source FM)
#   <name>.preamble.md  - inserted between frontmatter and source body
#   <name>.body.md      - appended after the source body
#
# Use the preamble for host-specific top-of-prompt directives whose
# semantics depend on position — for example, Gemini's `@<agent>`
# mention, which only triggers deterministic subagent delegation when
# it is the first token of the prompt. Use the suffix for host-specific
# input syntax (`${input:...}` for Copilot, `$ARGUMENTS` for Claude,
# `{{args}}` for Gemini). All three overlays are independently
# optional. Output format is selected by the destination extension:
# .toml dispatches to sync_view_toml (Gemini schema with description +
# prompt), anything else uses sync_view_md (markdown with merged YAML
# frontmatter and body). $src is the source markdown; $dst is the host
# destination. Logged as <kind>/<name>.
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
    preamble="$REPO_ROOT/templates/$kind/$name.preamble.md"
    suffix="$REPO_ROOT/templates/$kind/$name.body.md"

    tmp=$(mktemp) || die "mktemp failed"

    if [ -f "$preamble" ]; then
        # Preamble must sit between the frontmatter and the body, so
        # split the overlaid file and reassemble.
        merged=$(mktemp) || die "mktemp failed"
        fm=$(mktemp) || die "mktemp failed"
        body=$(mktemp) || die "mktemp failed"
        frontmatter_overlay "$src" "$tmpl" "$merged"
        split_frontmatter "$merged" "$fm" "$body"
        {
            if [ -s "$fm" ]; then
                printf -- '---\n'
                cat -- "$fm"
                printf -- '---\n'
            fi
            cat -- "$preamble"
            printf '\n'
            cat -- "$body"
        } > "$tmp"
        rm -f -- "$merged" "$fm" "$body"
    else
        frontmatter_overlay "$src" "$tmpl" "$tmp"
    fi

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
# emitted as a TOML basic string with " and \ escaped. Prompt is the
# optional .preamble.md, then the body, then the optional .body.md
# suffix — emitted as a TOML literal multiline string ('''...''') so
# that backslashes and ${...} / {{...}} placeholders pass through
# verbatim. Source bodies must not contain the literal '''; markdown
# uses ``` for code fences, so this holds.
sync_view_toml() {
    kind=$1
    src=$2
    dst=$3
    name=$(basename -- "$src" .md)
    tmpl="$REPO_ROOT/templates/$kind/$name.yaml"
    preamble="$REPO_ROOT/templates/$kind/$name.preamble.md"
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
        if [ -f "$preamble" ]; then
            cat -- "$preamble"
            printf '\n'
        fi
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
    any_host_active claude copilot gemini opencode || return 0
    progress_section "Agent definitions"

    src_dir="$REPO_ROOT/.agents/agents"
    [ -d "$src_dir" ] || die "source missing: $src_dir"

    # Pre-create agents/ in each installed host so the per-file mirrors
    # below are not skipped on a missing parent. Gating on root
    # existence keeps uninstalled hosts un-bootstrapped.
    for_host claude ensure_subdir "$HOME/.claude" agents
    for_host copilot ensure_subdir "$HOME/.copilot" agents
    for_host gemini ensure_subdir "$HOME/.gemini" agents
    for_host opencode ensure_subdir "$HOME/.config/opencode" agents

    for f in "$src_dir/"*.md; do
        [ -f "$f" ] || continue
        name=$(basename -- "$f" .md)

	for_host claude sync_view ".claude/agents" "$f" "$HOME/.claude/agents/$name.md"
	for_host copilot sync_view ".copilot/agents" "$f" "$HOME/.copilot/agents/$name.agent.md"
	for_host gemini sync_view ".gemini/agents" "$f" "$HOME/.gemini/agents/$name.md"

        # opencode derives the agent name from the filename and defaults
        # an agent without `mode` to "all", which would put all ten into
        # the Tab-cycled primary rotation, so templates/.opencode/agents/
        # pins `mode: subagent` for each. It also pins `model` and, where a
        # level was measured, `reasoningEffort`. An unrecognised frontmatter
        # key is forwarded to the provider as a model option, which is how
        # per-agent reasoning effort reaches openrouter; a provider that
        # does not take the key tolerates it.
        #
        # These levels are NOT a mirror of templates/.claude/agents/. Each
        # stack carries the setting its own measurements support, so three
        # agents diverge on purpose:
        #   arch-review  opencode max, Claude high. The Claude level follows
        #                that stack's thinking-share measurement; the opencode
        #                level is the one that produced a spec a blind review
        #                scored 22/25 with no defect that would reach code.
        #   composer,    no reasoningEffort at all. The only model measured
        #   conductor    delegating rather than doing the work itself ran at
        #                the provider default, and "default" is not a value
        #                the effort enum accepts.
        # Change a level here only against a measurement of this stack.
	for_host opencode sync_view ".opencode/agents" "$f" "$HOME/.config/opencode/agents/$name.md"
    done
}

sync_commands() {
    any_host_active claude copilot gemini opencode || return 0
    progress_section "Commands and prompts"

    src_dir="$REPO_ROOT/.agents/commands"
    [ -d "$src_dir" ] || die "source missing: $src_dir"

    # Pre-create per-host destination directories so the per-file mirrors
    # below are not skipped on a missing parent. Each host gates itself
    # on its own root, so an uninstalled tool stays untouched.
    for_host claude ensure_subdir "$HOME/.claude" commands
    for_host copilot ensure_subdir "$HOME/.copilot" prompts
    for_host gemini ensure_subdir "$HOME/.gemini" commands
    for_host opencode ensure_subdir "$HOME/.config/opencode" commands

    for f in "$src_dir/"*.md; do
        [ -f "$f" ] || continue
        name=$(basename -- "$f" .md)

        # Claude: ~/.claude/commands/ is functionally equivalent to
        # ~/.claude/skills/<name>/SKILL.md per the docs and accepts the
        # same frontmatter, but stays out of --skills' --delete sweep
        # against .agents/skills/.
	for_host claude sync_view ".claude/commands" "$f" "$HOME/.claude/commands/$name.md"

        # Copilot calls these "prompts" and uses the .prompt.md suffix.
	for_host copilot sync_view ".copilot/prompts" "$f" "$HOME/.copilot/prompts/$name.prompt.md"

        # Gemini commands are TOML files with `description` and `prompt`
        # keys; sync_view dispatches on the .toml extension.
	for_host gemini sync_view ".gemini/commands" "$f" "$HOME/.gemini/commands/$name.toml"

        # opencode derives the command name from the filename and reads
        # `description`, `agent`, `model` and `subtask` from frontmatter;
        # the body becomes the template and expands $ARGUMENTS and $1..$N.
        # templates/.opencode/commands/ supplies `subtask: true` where
        # Claude uses `context: fork`, since opencode has no equivalent
        # frontmatter key and runs the command as a child task instead.
	for_host opencode sync_view ".opencode/commands" "$f" "$HOME/.config/opencode/commands/$name.md"
    done
}

# Apply per-vendor SKILL.md frontmatter overlays. For each template
# under templates/<vendor>/skills/<name>.yaml, deep-merge its top-
# level keys into .agents/skills/<name>/SKILL.md and write the result
# to <dest_root>/<name>/SKILL.md. The preceding rsync in sync_skills
# has already mirrored bodies and supporting files; this function
# rewrites SKILL.md only. Skills without a matching template are
# left untouched.
apply_skill_overlays() {
    vendor=$1
    dest_root=$2
    src_root="$REPO_ROOT/.agents/skills"
    tmpl_root="$REPO_ROOT/templates/$vendor/skills"

    [ -d "$tmpl_root" ] || return 0
    [ -d "$dest_root" ] || return 0

    for tmpl in "$tmpl_root"/*.yaml; do
        [ -f "$tmpl" ] || continue
        name=$(basename -- "$tmpl" .yaml)
        src_skill="$src_root/$name/SKILL.md"
        dst_skill="$dest_root/$name/SKILL.md"
        label="$vendor/skills/$name"

        if [ ! -f "$src_skill" ]; then
	    progress_skipped "$label" "source skill missing: $(display_path "$src_skill")"
            continue
        fi
        if [ ! -d "$(dirname -- "$dst_skill")" ]; then
	    progress_skipped "$label" "destination directory missing: $(display_path "$(dirname -- "$dst_skill")")"
            continue
        fi
        if [ -e "$dst_skill" ] && [ "$(canonical_path "$src_skill")" = "$(canonical_path "$dst_skill")" ]; then
	    progress_skipped "$label" "destination is a symlink to the source"
            continue
        fi

        tmp=$(mktemp) || die "mktemp failed"
        frontmatter_overlay "$src_skill" "$tmpl" "$tmp"
        mv -f -- "$tmp" "$dst_skill"
	progress_updated "$label" "$dst_skill"
    done
}

# Mirror the skill tree into every registered destination, pairing each
# mirror with its own frontmatter overlay pass.
sync_skills() {
    any_host_active claude codex copilot gemini opencode || return 0
    progress_section "Skills"

    # Skills another tool owns, living in the destinations this
    # function sweeps. sync_to mirrors a directory with rsync
    # --delete, which removes whatever the source does not carry, so
    # without this every discovery-engine-* skill disappears on the
    # next --skills run. rsync spares an excluded path from deletion
    # as well as from transfer, so one pattern covers both. The
    # discovery-engine-* family is installed and updated by the
    # discovery-engine-manager skill, which writes them directly into
    # ~/.claude/skills; the exclusion is applied to every destination
    # because the sweep is identical in all of them. Quote the
    # expansion at each call site: unquoted, the shell would glob the
    # pattern against the current directory before rsync ever sees it.
    keep_foreign='--exclude=discovery-engine-*'

    for_host claude sync_to "$REPO_ROOT/.agents/skills" "$HOME/.claude/skills" "$keep_foreign"
    for_host claude apply_skill_overlays ".claude" "$HOME/.claude/skills"

    # Codex preserves .system/ and other Codex-managed dot entries.
    for_host codex sync_to "$REPO_ROOT/.agents/skills" "$HOME/.codex/skills" --exclude='.*' "$keep_foreign"

    for_host copilot sync_to "$REPO_ROOT/.agents/skills" "$HOME/.copilot/skills" "$keep_foreign"
    for_host copilot apply_skill_overlays ".copilot" "$HOME/.copilot/skills"

    for_host gemini sync_to "$REPO_ROOT/.agents/skills" "$HOME/.gemini/skills" "$keep_foreign"
    for_host gemini apply_skill_overlays ".gemini" "$HOME/.gemini/skills"

    for_host opencode sync_to "$REPO_ROOT/.agents/skills" "$HOME/.config/opencode/skills" "$keep_foreign"
}

# Mirror $1 onto $2 by merging, so keys the destination holds and the
# source does not survive the sync. A settings file carries both this
# repository's opinion and choices that belong to the machine - which
# credential the provider authenticates with, most of all - and a
# whole-file copy silently deletes the second kind. The provider then
# refuses to start, having been told nothing about how to authenticate.
# Source keys win on conflict, so the repository still converges what it
# does declare. Without jq the merge cannot be done safely, and skipping
# is the only honest option: a fallback copy is exactly the destructive
# path this exists to close.
merge_settings() {
    src=$1
    dst=$2
    if [ ! -f "$dst" ]; then
        sync_to "$src" "$dst"
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
	progress_skipped "$src" "jq not found; preserving host-local settings"
        return 0
    fi
    tmp=$(mktemp) || die "mktemp failed"
    jq -s '.[0] * .[1]' "$dst" "$src" > "$tmp" || die "settings merge failed: $src onto $dst"
    SYNC_TO_LABEL=$src
    sync_to "$tmp" "$dst"
    unset SYNC_TO_LABEL
    rm -f -- "$tmp"
}

sync_settings() {
    any_host_active claude gemini opencode || return 0
    progress_section "Host settings"

    for_host claude merge_settings "$REPO_ROOT/.claude/settings.json" "$HOME/.claude/settings.json"
    for_host claude sync_to "$REPO_ROOT/.claude/statusline.sh" "$HOME/.claude/statusline.sh"
    for_host gemini merge_settings "$REPO_ROOT/.gemini/settings.user.json" "$HOME/.gemini/settings.json"
    for_host gemini sync_to "$REPO_ROOT/.gemini/policies" "$HOME/.gemini/policies"

    # opencode reads every opencode.json and opencode.jsonc it finds in
    # ~/.config/opencode and deep-merges them, with .jsonc winning on a
    # conflicting key. Owning the .json half outright therefore needs no
    # merge pass: host-local choices live in the user's opencode.jsonc
    # and still override whatever this repository declares.
    for_host opencode sync_to "$REPO_ROOT/.opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
}

sync_rules() {
    any_host_active claude copilot opencode || return 0
    progress_section "Rules and instructions"

    src_dir="$REPO_ROOT/.agents/rules"
    [ -d "$src_dir" ] || die "source missing: $src_dir"

    # Pre-create per-host destination directories so the per-file mirrors
    # below are not skipped on a missing parent. Each host gates itself
    # on its own root, so an uninstalled tool stays untouched.
    for_host claude ensure_subdir "$HOME/.claude" rules
    for_host copilot ensure_subdir "$HOME/.copilot" instructions
    for_host opencode ensure_subdir "$HOME/.config/opencode" rules

    for f in "$src_dir/"*.md; do
        [ -f "$f" ] || continue
        name=$(basename -- "$f" .md)

        # Claude Code: ~/.claude/rules/<name>.md. The optional
        # templates/.claude/rules/<name>.yaml supplies `paths:` for
        # path-scoped rules; rules without one install as verbatim
        # markdown and load unconditionally on session start.
	for_host claude sync_view ".claude/rules" "$f" "$HOME/.claude/rules/$name.md"

        # VS Code Copilot: ~/.copilot/instructions/<name>.instructions.md.
        # templates/.copilot/instructions/<name>.yaml carries the
        # name/description/applyTo frontmatter Copilot expects.
	for_host copilot sync_view ".copilot/instructions" "$f" "$HOME/.copilot/instructions/$name.instructions.md"

        # opencode: ~/.config/opencode/rules/<name>.md, pulled in by the
        # `instructions` glob in .opencode/opencode.json. Only rules that
        # load unconditionally go there. opencode has no path scoping, so
        # every instruction file it reads enters the system prompt of every
        # session in every project; shipping a Go style rule that way would
        # state it as fact inside a TypeScript repository. A rule is
        # conditional exactly when templates/.claude/rules/<name>.yaml
        # exists to carry its `paths:`, so that file's absence is the test.
        if [ ! -f "$REPO_ROOT/templates/.claude/rules/$name.yaml" ]; then
	    for_host opencode sync_view ".opencode/rules" "$f" "$HOME/.config/opencode/rules/$name.md"
        fi
    done
}

sync_hooks() {
    any_host_active claude || return 0
    progress_section "Hooks"

    for_host claude sync_to "$REPO_ROOT/.claude/hooks" "$HOME/.claude/hooks"
}

main() {
    setup_formatting
    UPDATED_COUNT=0
    SKIPPED_COUNT=0
    actions=
    hosts=
    while [ $# -gt 0 ]; do
        case $1 in
            --all)       actions="$actions $ALL_ACTIONS" ;;
            --agents)    actions="$actions agents" ;;
            --commands)  actions="$actions commands" ;;
            --hooks)     actions="$actions hooks" ;;
            --rules)     actions="$actions rules" ;;
            --skills)    actions="$actions skills" ;;
            --settings)  actions="$actions settings" ;;
	    --claude)    hosts="$hosts claude" ;;
	    --codex)     hosts="$hosts codex" ;;
	    --copilot)   hosts="$hosts copilot" ;;
	    --gemini)    hosts="$hosts gemini" ;;
	    --opencode)  hosts="$hosts opencode" ;;
            -h|--help)   usage; exit 0 ;;
	    -*)          die "unknown option: $1 (try --help)" ;;
	    *)           die "unexpected argument: $1 (try --help)" ;;
        esac
        shift
    done
    [ -n "$actions$hosts" ] || { usage >&2; exit 2; }
    [ -n "$actions" ] || actions=$ALL_ACTIONS
    [ -n "$hosts" ] || hosts=$ALL_HOSTS
    actions=$(canonical_selection "$actions" agents commands hooks rules settings skills)
    hosts=$(canonical_selection "$hosts" claude codex copilot gemini opencode)

    print_plan
    # Dispatch in canonical order; the membership check drops
    # duplicates when --all is combined with individual flags.
    for action in $ALL_ACTIONS; do
        case " $actions " in *" $action "*) "sync_$action" ;; esac
    done

    printf '\n'
    if [ "$UPDATED_COUNT" -gt 0 ]; then
	ok "Installation complete: $UPDATED_COUNT updated, $SKIPPED_COUNT skipped"
    else
	warn "No destinations were updated ($SKIPPED_COUNT skipped)"
    fi
}

main "$@"
