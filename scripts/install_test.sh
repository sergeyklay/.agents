#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
INSTALLER="$SCRIPT_DIR/install.sh"
CONTEXT="$SCRIPT_DIR/../.agents/AGENTS.md"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' 0 HUP INT TERM

new_home() {
  home="$TEST_ROOT/$1"
  mkdir -p "$home/.claude" "$home/.codex" "$home/.copilot" \
    "$home/.gemini" "$home/.config/opencode"
  printf '%s\n' "$home"
}

run_install() {
  home=$1
  shift
  HOME="$home" sh "$INSTALLER" "$@" >/dev/null
}

assert_file() {
  [ -f "$1" ] || {
    printf 'expected file: %s\n' "$1" >&2
    exit 1
  }
}

assert_absent() {
  [ ! -e "$1" ] || {
    printf 'expected absent: %s\n' "$1" >&2
    exit 1
  }
}

assert_same() {
  cmp -s -- "$1" "$2" || {
    printf 'expected identical files: %s %s\n' "$1" "$2" >&2
    exit 1
  }
}

assert_contains() {
  case $1 in
  *"$2"*) return 0 ;;
  esac
  printf 'expected output to contain: %s\n' "$2" >&2
  exit 1
}

assert_not_contains() {
  case $1 in
  *"$2"*)
    printf 'expected output not to contain: %s\n' "$2" >&2
    exit 1
    ;;
  esac
}

assert_file_contains() {
  if ! grep -qF -- "$2" "$1"; then
    printf 'expected %s to contain: %s\n' "$1" "$2" >&2
    exit 1
  fi
}

frontmatter_of() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next }
       inside && $0 == "---" { exit }
       inside { print }' "$1"
}

assert_frontmatter() {
  if ! frontmatter_of "$1" | grep -qxF "$2"; then
    printf 'expected frontmatter line in %s: %s\n' "$1" "$2" >&2
    exit 1
  fi
}

assert_no_frontmatter_key() {
  if frontmatter_of "$1" | grep -q "^$2:"; then
    printf 'unexpected frontmatter key in %s: %s\n' "$1" "$2" >&2
    exit 1
  fi
}

escape=$(printf '\033')
help_output=$(NO_COLOR=1 TERM=xterm sh "$INSTALLER" --help)
assert_contains "$help_output" 'Usage'
assert_contains "$help_output" 'Asset options'
assert_contains "$help_output" 'Host options'
assert_contains "$help_output" 'Examples'
assert_contains "$help_output" '--context'
assert_contains "$help_output" '# Install every supported asset for Claude Code.'
assert_contains "$help_output" 'bash scripts/install.sh --agents --opencode'
assert_contains "$help_output" 'bash scripts/install.sh --context --claude --gemini'
assert_contains "$help_output" 'NO_COLOR'
assert_not_contains "$help_output" "$escape"

home=$(new_home context-all-hosts)
run_install "$home" --context
assert_same "$CONTEXT" "$home/.claude/CLAUDE.md"
assert_same "$CONTEXT" "$home/.codex/AGENTS.md"
assert_same "$CONTEXT" "$home/.copilot/copilot-instructions.md"
assert_absent "$home/.copilot/instructions/context.instructions.md"
assert_same "$CONTEXT" "$home/.gemini/GEMINI.md"
assert_same "$CONTEXT" "$home/.config/opencode/AGENTS.md"
assert_absent "$home/.claude/agents"
assert_absent "$home/.codex/skills"
assert_absent "$home/.copilot/agents"
assert_absent "$home/.gemini/agents"
assert_absent "$home/.config/opencode/agents"

home=$(new_home opencode-agents)
output=$(NO_COLOR=1 TERM=xterm HOME="$home" sh "$INSTALLER" --agents --opencode)
assert_contains "$output" ':: Installing agent assets'
assert_contains "$output" 'Assets  agents'
assert_contains "$output" 'Hosts   opencode'
assert_contains "$output" 'Agent definitions'
assert_contains "$output" '+ .opencode/agents/arch-review -> ~/.config/opencode/agents/arch-review.md'
assert_contains "$output" ':: Installation complete: 10 updated, 0 skipped'
assert_not_contains "$output" 'Commands and prompts'
assert_not_contains "$output" "$TEST_ROOT"
assert_not_contains "$output" "$escape"
assert_file "$home/.config/opencode/agents/arch-review.md"
assert_absent "$home/.claude/agents"
assert_absent "$home/.copilot/agents"
assert_absent "$home/.gemini/agents"

home=$(new_home claude-all)
run_install "$home" --claude
assert_file "$home/.claude/agents/arch-review.md"
assert_file "$home/.claude/commands/challenge-pr.md"
assert_file "$home/.claude/hooks/append_agentsmd_context.sh"
assert_file "$home/.claude/rules/commit-messages.md"
assert_file "$home/.claude/settings.json"
assert_file "$home/.claude/skills/context-files/SKILL.md"
assert_same "$CONTEXT" "$home/.claude/CLAUDE.md"
# The orchestrator commands must fork into their agent, and must not pin that
# fork to the invoking turn: a fork that cannot take a later turn never
# receives its delegated subagent's completion notification.
for command in specify implement; do
  assert_file "$home/.claude/commands/$command.md"
  assert_frontmatter "$home/.claude/commands/$command.md" 'context: fork'
  assert_no_frontmatter_key "$home/.claude/commands/$command.md" 'background'
done
assert_frontmatter "$home/.claude/commands/specify.md" 'agent: composer'
assert_frontmatter "$home/.claude/commands/implement.md" 'agent: conductor'
jq -e '
  .permissions.defaultMode == "bypassPermissions" and
  (.permissions.deny | index("Read(**/.env)") != null) and
  (.permissions.deny | index("Read(**/.env.*)") == null)
' "$home/.claude/settings.json" >/dev/null
assert_absent "$home/.codex/skills"
assert_absent "$home/.copilot/agents"
assert_absent "$home/.gemini/agents"
assert_absent "$home/.config/opencode/agents"

home=$(new_home orchestrator-search-tools)
run_install "$home" --agents
# The orchestrators inspect artifacts they never write. Without a targeted search
# tool, checking one line of a review means pulling the whole file into context,
# and the cheapest way to check it again is to pull it again. Every host that
# ships a tool list must carry a content search and a filename search.
for agent in composer conductor; do
  assert_frontmatter "$home/.claude/agents/$agent.md" '  - Grep'
  assert_frontmatter "$home/.claude/agents/$agent.md" '  - Glob'
  assert_frontmatter "$home/.copilot/agents/$agent.agent.md" '  - search/textSearch'
  assert_frontmatter "$home/.copilot/agents/$agent.agent.md" '  - search/fileSearch'
  assert_frontmatter "$home/.gemini/agents/$agent.md" '  - grep_search'
  assert_frontmatter "$home/.gemini/agents/$agent.md" '  - glob'
  # OpenCode ships no tool list for these agents, so there is nothing to widen.
  assert_no_frontmatter_key "$home/.config/opencode/agents/$agent.md" 'tools'
done

home=$(new_home skills-authoring-parity)
run_install "$home" --skills
# The writing-specs authoring procedure is the control on edit churn, and it is
# worth nothing on a host that never receives it. Skills install to all five
# hosts, so every installed copy must carry the rule, not only Claude Code's.
for skill_root in "$home/.claude/skills" "$home/.codex/skills" \
  "$home/.copilot/skills" "$home/.gemini/skills" \
  "$home/.config/opencode/skills"; do
  spec_skill="$skill_root/writing-specs/SKILL.md"
  assert_file "$spec_skill"
  assert_file_contains "$spec_skill" '#### Authoring procedure'
  assert_file_contains "$spec_skill" \
    '**Draft the whole document before the first write.**'
  assert_file_contains "$spec_skill" \
    '**Group revisions into as few calls as the host allows.**'
  assert_file_contains "$spec_skill" \
    '**Never re-read a file you wrote yourself.**'
done
# The validator gathers every error before it prints. Its failure line has to
# say so, or an agent that reads "N error(s)" and nothing else re-runs the
# script after each single fix, which is the churn the rule above forbids.
broken_spec="$TEST_ROOT/Spec-broken.md"
printf '# Broken\n' >"$broken_spec"
validator="$home/.claude/skills/writing-specs/scripts/validate_spec.py"
assert_file "$validator"
if validator_output=$(python3 "$validator" "$broken_spec"); then
  printf 'expected the validator to fail on a spec with no sections\n' >&2
  exit 1
fi
assert_contains "$validator_output" 'VALIDATION_RESULT=FAIL'
assert_contains "$validator_output" 'fix all errors in one pass, then re-run once'

home=$(new_home multiple-hosts)
run_install "$home" --gemini --commands --opencode
assert_file "$home/.gemini/commands/challenge-pr.toml"
assert_file "$home/.config/opencode/commands/challenge-pr.md"
assert_absent "$home/.claude/commands"
assert_absent "$home/.copilot/prompts"
assert_absent "$home/.gemini/agents"
assert_absent "$home/.config/opencode/agents"

home=$(new_home default-hosts)
run_install "$home" --commands
assert_file "$home/.claude/commands/challenge-pr.md"
assert_file "$home/.copilot/prompts/challenge-pr.prompt.md"
assert_file "$home/.gemini/commands/challenge-pr.toml"
assert_file "$home/.config/opencode/commands/challenge-pr.md"
assert_absent "$home/.codex/commands"
assert_absent "$home/.claude/CLAUDE.md"

home=$(new_home rules-only)
run_install "$home" --rules --claude
assert_file "$home/.claude/rules/commit-messages.md"
assert_absent "$home/.claude/CLAUDE.md"

home=$(new_home codex-all)
run_install "$home" --codex
assert_same "$CONTEXT" "$home/.codex/AGENTS.md"
assert_file "$home/.codex/skills/context-files/SKILL.md"
assert_absent "$home/.claude/skills"
assert_absent "$home/.copilot/skills"
assert_absent "$home/.gemini/skills"
assert_absent "$home/.config/opencode/skills"

home=$(new_home stale-rules)
mkdir -p "$home/.claude/rules" "$home/.copilot/instructions" \
  "$home/.config/opencode/rules"
cp -- "$CONTEXT" "$home/.claude/rules/working-agreement.md"
cp -- "$CONTEXT" "$home/.copilot/instructions/working-agreement.instructions.md"
cp -- "$CONTEXT" "$home/.config/opencode/rules/working-agreement.md"
printf '\n' >>"$home/.claude/rules/working-agreement.md"
printf 'old context\n' >"$home/.claude/CLAUDE.md"
run_install "$home" --context --claude --copilot --opencode
assert_same "$CONTEXT" "$home/.claude/CLAUDE.md"
assert_absent "$home/.claude/rules/working-agreement.md"
assert_absent "$home/.copilot/instructions/working-agreement.instructions.md"
assert_absent "$home/.config/opencode/rules/working-agreement.md"

home=$(new_home modified-stale-rule)
mkdir -p "$home/.config/opencode/rules"
cp -- "$CONTEXT" "$home/.config/opencode/rules/working-agreement.md"
printf '\n# Local change\n' >>"$home/.config/opencode/rules/working-agreement.md"
output=$(NO_COLOR=1 HOME="$home" sh "$INSTALLER" --context --opencode)
assert_contains "$output" 'modified stale file preserved'
assert_file "$home/.config/opencode/rules/working-agreement.md"
assert_same "$CONTEXT" "$home/.config/opencode/AGENTS.md"

home=$(new_home unavailable-host)
rmdir "$home/.codex"
output=$(NO_COLOR=1 HOME="$home" sh "$INSTALLER" --codex)
assert_contains "$output" '- Codex not found at ~/.codex; skipping'
assert_contains "$output" '- No destinations were updated (1 skipped)'
assert_absent "$home/.codex"

printf 'install option tests passed\n'
