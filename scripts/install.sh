#!/bin/sh
# Install canonical agent assets into host-specific user directories.

set -eu

SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH="" cd -- "$SCRIPT_DIR/.." && pwd)

ALL_ACTIONS='context agents commands hooks rules settings skills'
ALL_HOSTS='claude codex copilot gemini opencode'

# Gemini strips agent-kind tools from subagents, so an orchestrator installed
# as a Gemini agent cannot delegate. The protocol ships as a top-level command.
GEMINI_SKIPPED_AGENTS='composer conductor'

# Gemini's own `mergeStrategy: "union"` keys (settingsSchema.ts 0.58.0).
GEMINI_UNION_KEYS='[
  "policyPaths",
  "adminPolicyPaths",
  "context.fileFiltering.customIgnoreFilePaths",
  "tools.exclude",
  "advanced.excludedEnvVars",
  "extensions.disabled",
  "extensions.workspacesWithMigrationNudge",
  "skills.disabled",
  "hooksConfig.disabled"
]'

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
  ${BOLD}${YELLOW}--context${RESET}   Install global user context
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

  ${DIM}# Install global context for Claude Code and Gemini CLI.${RESET}
  ${CYAN}bash scripts/install.sh --context --claude --gemini${RESET}

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
  for candidate; do
    host_active "$candidate" && return 0
  done
  return 1
}

host_root() {
  case $1 in
  claude) printf '%s/.claude\n' "$HOME" ;;
  codex) printf '%s/.codex\n' "$HOME" ;;
  copilot) printf '%s/.copilot\n' "$HOME" ;;
  gemini) printf '%s/.gemini\n' "$HOME" ;;
  opencode) printf '%s/.config/opencode\n' "$HOME" ;;
  esac
}

host_name() {
  case $1 in
  claude) printf 'Claude Code\n' ;;
  codex) printf 'Codex\n' ;;
  copilot) printf 'GitHub Copilot\n' ;;
  gemini) printf 'Gemini CLI\n' ;;
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
  for word; do
    printf '%s%s' "$separator" "$word"
    separator=', '
  done
}

canonical_selection() {
  selected=$1
  shift
  for candidate; do
    case " $selected " in
    *" $candidate "*) printf '%s ' "$candidate" ;;
    esac
  done
}

display_path() {
  path=$1
  case $path in
  "$HOME") printf '~\n' ;;
  "$HOME"/*) printf '%s/%s\n' '~' "${path#"$HOME"/}" ;;
  "$REPO_ROOT") printf '.\n' ;;
  "$REPO_ROOT"/*) printf './%s\n' "${path#"$REPO_ROOT"/}" ;;
  *) printf '%s\n' "$path" ;;
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

progress_removed() {
  UPDATED_COUNT=$((UPDATED_COUNT + 1))
  printf '  %s-%s %s %s(%s)%s\n' "$GREEN" "$RESET" \
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

# Canonicalize existing paths without relying on GNU readlink -f.
canonical_path() {
  if [ -d "$1" ]; then
    (CDPATH="" cd -- "$1" && pwd -P)
  elif [ -L "$1" ]; then
    target=$(readlink -- "$1")
    case "$target" in
    /*) canonical_path "$target" ;;
    *) canonical_path "$(dirname -- "$1")/$target" ;;
    esac
  elif [ -f "$1" ]; then
    printf '%s/%s\n' "$(CDPATH="" cd -- "$(dirname -- "$1")" && pwd -P)" "$(basename -- "$1")"
  fi
}

# Flags must work with macOS rsync 2.6.9.
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

# Other yq implementations use incompatible syntax.
detect_yq() {
  command -v yq >/dev/null 2>&1 || return 1
  case "$(yq --version 2>/dev/null)" in
  *mikefarah*v4.*) return 0 ;;
  esac
  return 1
}

# Split optional leading YAML frontmatter from the Markdown body.
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

# Deep-merge frontmatter with template priority; array values are replaced.
# Subshell scope keeps temporaries out of the caller.
overlay_with_yq() (
  src=$1
  tmpl=$2
  dst=$3

  fm=$(mktemp) || die "mktemp failed"
  body=$(mktemp) || die "mktemp failed"
  merged=$(mktemp) || die "mktemp failed"

  split_frontmatter "$src" "$fm" "$body"
  yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
    "$fm" "$tmpl" >"$merged" ||
    die "yq merge failed: $tmpl onto $src"

  {
    printf -- '---\n'
    cat -- "$merged"
    printf -- '---\n'
    cat -- "$body"
  } >"$dst"

  rm -f -- "$fm" "$body" "$merged"
)

# Fallback: replaces top-level /^[A-Za-z_][A-Za-z_0-9-]*:/ blocks. No quoted
# keys, anchors, or multi-document YAML.
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
    ' "$src" >"$dst"
)

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
    } >"$dst"
    return 0
  fi

  if detect_yq; then
    overlay_with_yq "$src" "$tmpl" "$dst"
  else
    overlay_with_awk "$src" "$tmpl" "$dst"
  fi
)

# Apply optional frontmatter, preamble, and body overlays. TOML
# destinations use Gemini command serialization.
sync_view() {
  case "$3" in
  *.toml) sync_view_toml "$1" "$2" "$3" ;;
  *) sync_view_md "$1" "$2" "$3" ;;
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
    } >"$tmp"
    rm -f -- "$merged" "$fm" "$body"
  else
    frontmatter_overlay "$src" "$tmpl" "$tmp"
  fi

  if [ -f "$suffix" ]; then
    printf '\n' >>"$tmp"
    cat -- "$suffix" >>"$tmp"
  fi

  SYNC_TO_LABEL="$kind/$name"
  sync_to "$tmp" "$dst"
  unset SYNC_TO_LABEL
  rm -f -- "$tmp"
}

# Read one scalar frontmatter value, unquoting a quoted form.
frontmatter_value() {
  awk -v key="$2" '
        index($0, key ":") == 1 {
            sub("^" key ":[[:space:]]*", "")
            if (sub(/^"/, "")) sub(/"$/, "")
            else if (sub(/^\047/, "")) sub(/\047$/, "")
            print
            exit
        }
    ' "$1"
}

# A Gemini command prompt is a TOML literal string the CLI expands before it
# runs: ''' closes the string early, !{...} executes a command, @{...} reads a file.
assert_prompt_safe() {
  guard_file=$1
  guard_label=$2
  for guard_sigil in "'''" '!{' '@{'; do
    if grep -qF -- "$guard_sigil" "$guard_file"; then
      die "refusing to inline $guard_label: contains $guard_sigil"
    fi
  done
}

# Prompt fragments are inlined into a TOML literal and must not contain '''.
# An "agent: <name>" template key inlines that agent's body: Gemini's command
# schema has no agent binding, and only the primary session holds invoke_agent.
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

  description=$(frontmatter_value "$fm" description)
  description_escaped=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')

  agent=$(frontmatter_value "$fm" agent)
  agent_body=
  if [ -n "$agent" ]; then
    # The name is interpolated into a path: a non-token value traverses out of
    # .agents/agents, and the existence check below passes on the traversed file.
    case $agent in
    *[!A-Za-z0-9-]*)
      die "refusing to inline agent \"$agent\" from $tmpl onto $src: expected [A-Za-z0-9-]"
      ;;
    esac
    agent_src="$REPO_ROOT/.agents/agents/$agent.md"
    [ -f "$agent_src" ] || die "agent source missing: $agent_src"
    agent_body=$(mktemp) || die "mktemp failed"
    agent_fm=$(mktemp) || die "mktemp failed"
    split_frontmatter "$agent_src" "$agent_fm" "$agent_body"
    rm -f -- "$agent_fm"
    assert_prompt_safe "$agent_body" "$agent_src"
  fi

  # Every fragment reaching the prompt literal is a place a sigil can enter;
  # guarding only the agent body left the other three open (measured 0.58.0).
  if [ -f "$preamble" ]; then
    assert_prompt_safe "$preamble" "$preamble"
  fi
  assert_prompt_safe "$body" "$src"
  if [ -f "$suffix" ]; then
    assert_prompt_safe "$suffix" "$suffix"
  fi

  tmp=$(mktemp) || die "mktemp failed"
  {
    printf 'description = "%s"\n' "$description_escaped"
    printf "prompt = '''\n"
    if [ -f "$preamble" ]; then
      cat -- "$preamble"
      printf '\n'
    fi
    if [ -n "$agent_body" ]; then
      cat -- "$agent_body"
      printf '\n'
    fi
    cat -- "$body"
    if [ -f "$suffix" ]; then
      printf '\n'
      cat -- "$suffix"
    fi
    printf "'''\n"
  } >"$tmp"

  SYNC_TO_LABEL="$kind/$name"
  sync_to "$tmp" "$dst"
  unset SYNC_TO_LABEL

  rm -f -- "$merged" "$fm" "$body" "$tmp"
  if [ -n "$agent_body" ]; then
    rm -f -- "$agent_body"
    agent_body=
  fi
}

gemini_agent_skipped() {
  case " $GEMINI_SKIPPED_AGENTS " in
  *" $1 "*) return 0 ;;
  esac
  return 1
}

# Per-file views go through rsync without --delete, so a previously installed
# skipped agent survives frozen, still advertising a delegation tool the host
# removes without warning.
cleanup_skipped_gemini_agents() {
  for skipped in $GEMINI_SKIPPED_AGENTS; do
    stale="$HOME/.gemini/agents/$skipped.md"
    # rm -f fails on a directory and the script runs under set -e; remove only
    # what an earlier install could have written (a regular file or symlink).
    if [ -f "$stale" ] || [ -L "$stale" ]; then
      rm -f -- "$stale"
      progress_removed "$stale" 'removed disarmed orchestrator'
    elif [ -e "$stale" ]; then
      progress_skipped "$stale" 'not a regular file'
    fi
  done
}

sync_agents() {
  any_host_active claude copilot gemini opencode || return 0
  progress_section "Agent definitions"

  src_dir="$REPO_ROOT/.agents/agents"
  [ -d "$src_dir" ] || die "source missing: $src_dir"

  for_host claude ensure_subdir "$HOME/.claude" agents
  for_host copilot ensure_subdir "$HOME/.copilot" agents
  for_host gemini ensure_subdir "$HOME/.gemini" agents
  for_host opencode ensure_subdir "$HOME/.config/opencode" agents

  for f in "$src_dir/"*.md; do
    [ -f "$f" ] || continue
    name=$(basename -- "$f" .md)

    for_host claude sync_view ".claude/agents" "$f" "$HOME/.claude/agents/$name.md"
    for_host copilot sync_view ".copilot/agents" "$f" "$HOME/.copilot/agents/$name.agent.md"
    if ! gemini_agent_skipped "$name"; then
      for_host gemini sync_view ".gemini/agents" "$f" "$HOME/.gemini/agents/$name.md"
    fi
    for_host opencode sync_view ".opencode/agents" "$f" "$HOME/.config/opencode/agents/$name.md"
  done

  for_host gemini cleanup_skipped_gemini_agents
}

sync_commands() {
  any_host_active claude copilot gemini opencode || return 0
  progress_section "Commands and prompts"

  src_dir="$REPO_ROOT/.agents/commands"
  [ -d "$src_dir" ] || die "source missing: $src_dir"

  for_host claude ensure_subdir "$HOME/.claude" commands
  for_host copilot ensure_subdir "$HOME/.copilot" prompts
  for_host gemini ensure_subdir "$HOME/.gemini" commands
  for_host opencode ensure_subdir "$HOME/.config/opencode" commands

  for f in "$src_dir/"*.md; do
    [ -f "$f" ] || continue
    name=$(basename -- "$f" .md)
    for_host claude sync_view ".claude/commands" "$f" "$HOME/.claude/commands/$name.md"
    for_host copilot sync_view ".copilot/prompts" "$f" "$HOME/.copilot/prompts/$name.prompt.md"
    for_host gemini sync_view ".gemini/commands" "$f" "$HOME/.gemini/commands/$name.toml"
    for_host opencode sync_view ".opencode/commands" "$f" "$HOME/.config/opencode/commands/$name.md"
  done
}

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

sync_skills() {
  any_host_active claude codex copilot gemini opencode || return 0
  progress_section "Skills"

  for_host claude sync_to "$REPO_ROOT/.agents/skills" "$HOME/.claude/skills"
  for_host claude apply_skill_overlays ".claude" "$HOME/.claude/skills"

  # Codex preserves .system/ and other Codex-managed dot entries.
  for_host codex sync_to "$REPO_ROOT/.agents/skills" "$HOME/.codex/skills" --exclude='.*'

  for_host copilot sync_to "$REPO_ROOT/.agents/skills" "$HOME/.copilot/skills"
  for_host copilot apply_skill_overlays ".copilot" "$HOME/.copilot/skills"

  for_host gemini sync_to "$REPO_ROOT/.agents/skills" "$HOME/.gemini/skills"
  for_host gemini apply_skill_overlays ".gemini" "$HOME/.gemini/skills"

  for_host opencode sync_to "$REPO_ROOT/.agents/skills" "$HOME/.config/opencode/skills"
}

# Repository values win conflicts, except for arrays at the $3 key paths, which
# keep host-local entries. Without jq, skip existing host-local files.
merge_settings() {
  src=$1
  dst=$2
  union_keys=${3:-[]}
  if [ ! -f "$dst" ]; then
    sync_to "$src" "$dst"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    progress_skipped "$src" "jq not found; preserving host-local settings"
    return 0
  fi
  tmp=$(mktemp) || die "mktemp failed"
  # getpath throws when a parent is not an object; that key falls back to `*`.
  jq -s --argjson union_keys "$union_keys" '
    def keep_first_occurrence:
      reduce .[] as $item ([]; if index([$item]) then . else . + [$item] end);
    . as [$host, $repo]
    | reduce ($union_keys[] | split(".")) as $path
        ($host * $repo;
          ($host | try getpath($path) catch null) as $host_array
          | ($repo | try getpath($path) catch null) as $repo_array
          | if ($host_array | type) == "array" and ($repo_array | type) == "array"
            then setpath($path; ($host_array + $repo_array) | keep_first_occurrence)
            else .
            end)
  ' "$dst" "$src" >"$tmp" || die "settings merge failed: $src onto $dst"
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
  for_host gemini merge_settings "$REPO_ROOT/.gemini/settings.json" \
    "$HOME/.gemini/settings.json" "$GEMINI_UNION_KEYS"
  for_host gemini sync_to "$REPO_ROOT/.gemini/policies" "$HOME/.gemini/policies"
  for_host opencode sync_to "$REPO_ROOT/.opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
  for_host opencode sync_to "$REPO_ROOT/.opencode/tui.json" "$HOME/.config/opencode/tui.json"
}

# Match the former rule, allowing its extra trailing newline.
stale_rule_matches_context() {
  stale=$1
  context=$2

  cmp -s -- "$stale" "$context" && return 0

  tmp=$(mktemp) || die "mktemp failed"
  {
    cat -- "$context"
    printf '\n'
  } >"$tmp"
  if cmp -s -- "$stale" "$tmp"; then
    matches=0
  else
    matches=1
  fi
  rm -f -- "$tmp"
  return "$matches"
}

cleanup_stale_working_agreement() {
  stale=$1
  context=$2

  [ -e "$stale" ] || [ -L "$stale" ] || return 0
  if [ -f "$stale" ] && stale_rule_matches_context "$stale" "$context"; then
    rm -f -- "$stale"
    progress_removed "$stale" 'removed stale rule'
  else
    progress_skipped "$stale" "modified stale file preserved"
  fi
}

sync_context() {
  any_host_active claude codex copilot gemini opencode || return 0
  progress_section "Global context"

  context_src="$REPO_ROOT/.agents/AGENTS.md"
  [ -f "$context_src" ] || die "source missing: $context_src"

  for_host claude sync_to "$context_src" "$HOME/.claude/CLAUDE.md"
  for_host claude cleanup_stale_working_agreement \
    "$HOME/.claude/rules/working-agreement.md" "$context_src"

  for_host codex sync_to "$context_src" "$HOME/.codex/AGENTS.md"

  for_host copilot sync_to "$context_src" "$HOME/.copilot/copilot-instructions.md"
  for_host copilot cleanup_stale_working_agreement \
    "$HOME/.copilot/instructions/working-agreement.instructions.md" "$context_src"

  for_host gemini sync_to "$context_src" "$HOME/.gemini/GEMINI.md"

  for_host opencode sync_to "$context_src" "$HOME/.config/opencode/AGENTS.md"
  for_host opencode cleanup_stale_working_agreement \
    "$HOME/.config/opencode/rules/working-agreement.md" "$context_src"
}

sync_rules() {
  any_host_active claude copilot opencode || return 0
  progress_section "Rules and instructions"

  src_dir="$REPO_ROOT/.agents/rules"
  [ -d "$src_dir" ] || die "source missing: $src_dir"

  for_host claude ensure_subdir "$HOME/.claude" rules
  for_host copilot ensure_subdir "$HOME/.copilot" instructions
  for_host opencode ensure_subdir "$HOME/.config/opencode" rules

  for f in "$src_dir/"*.md; do
    [ -f "$f" ] || continue
    name=$(basename -- "$f" .md)

    for_host claude sync_view ".claude/rules" "$f" "$HOME/.claude/rules/$name.md"
    for_host copilot sync_view ".copilot/instructions" "$f" "$HOME/.copilot/instructions/$name.instructions.md"

    # A Claude paths overlay marks rules that cannot be global in OpenCode.
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
    --all) actions="$actions $ALL_ACTIONS" ;;
    --context) actions="$actions context" ;;
    --agents) actions="$actions agents" ;;
    --commands) actions="$actions commands" ;;
    --hooks) actions="$actions hooks" ;;
    --rules) actions="$actions rules" ;;
    --skills) actions="$actions skills" ;;
    --settings) actions="$actions settings" ;;
    --claude) hosts="$hosts claude" ;;
    --codex) hosts="$hosts codex" ;;
    --copilot) hosts="$hosts copilot" ;;
    --gemini) hosts="$hosts gemini" ;;
    --opencode) hosts="$hosts opencode" ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *) die "unexpected argument: $1 (try --help)" ;;
    esac
    shift
  done
  [ -n "$actions$hosts" ] || {
    usage >&2
    exit 2
  }
  [ -n "$actions" ] || actions=$ALL_ACTIONS
  [ -n "$hosts" ] || hosts=$ALL_HOSTS
  actions=$(canonical_selection "$actions" context agents commands hooks rules settings skills)
  hosts=$(canonical_selection "$hosts" claude codex copilot gemini opencode)

  print_plan
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
