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

# Write a spec of exactly $1 words, to drive the validator's word budget.
filler_spec() {
  awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) print "word" }' >"$2"
}

# First non-empty line of a Markdown body, past any YAML frontmatter.
first_body_line() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next }
       inside && $0 == "---"   { inside = 0; body = 1; next }
       body && NF              { print; exit }' "$1"
}

assert_toml_parses() {
  if ! python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"; then
    printf 'expected valid TOML: %s\n' "$1" >&2
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
  # Gemini receives no orchestrator agent at all, so the two search tools are
  # asserted below over the eight agents it still gets.
  # OpenCode has no tool list to widen: an agent that names no tools keeps the
  # default `"*": allow`, which already covers both searches. A `tools` key
  # here would only narrow that, and the list shape every other host uses fails
  # the whole config load on OpenCode 1.18.27 ("Expected object | undefined"),
  # taking every other agent down with it. OpenCode's own widening for these
  # two agents is the delegation block asserted below, not a tool list.
  assert_no_frontmatter_key "$home/.config/opencode/agents/$agent.md" 'tools'
done
for agent in architect arch-review planner sleuth \
  go-coder go-tester ts-coder ts-tester; do
  assert_frontmatter "$home/.gemini/agents/$agent.md" '  - grep_search'
  assert_frontmatter "$home/.gemini/agents/$agent.md" '  - glob'
done

home=$(new_home opencode-orchestrator-delegation)
run_install "$home" --agents --settings --opencode
# Delegation is the entire protocol of both orchestrators, and OpenCode 1.18.27
# revokes it from every subagent session the task tool spawns: deriving the
# child session's permissions appends `task: deny`, and separately
# `todowrite: deny`, unless the agent already carries a rule whose permission
# name is literally that string. A blanket `"*": allow` does not satisfy the
# test, because it resolves to a rule named `*`; only the spelled-out keys
# survive. Without them the tool is dropped from the request before the model
# ever sees it, so the agent does not fail loudly, it simply never delegates.
for agent in composer conductor; do
  assert_frontmatter "$home/.config/opencode/agents/$agent.md" 'permission:'
  assert_frontmatter "$home/.config/opencode/agents/$agent.md" '  task: allow'
  assert_frontmatter "$home/.config/opencode/agents/$agent.md" '  todowrite: allow'
done
# Naming the keys only cancels the automatic deny; the depth ceiling is a
# separate gate, and at its default of 1 a subagent still cannot spawn one.
# The setting is global, so the repository's own copy is what has to carry it.
assert_file_contains "$home/.config/opencode/opencode.json" '"subagent_depth": 2'

home=$(new_home gemini-orchestrator-command)
# Gemini CLI 0.58.0 discards every agent-kind tool when it builds a subagent's
# tool registry, so an orchestrator shipped as a Gemini agent loses
# `invoke_agent` at load time with no warning, burns its turn budget failing to
# delegate, and exits 0. The primary session keeps the tool, so the protocol
# has to arrive as a top-level command instead: `agent: <name>` in the Gemini
# command template inlines the canonical agent body into the generated prompt.
# The two disarmed agent files must stop being installed, because their
# description actively invites the primary model to call them.
mkdir -p "$home/.gemini"
printf '{"general": {"vimMode": true}}\n' >"$home/.gemini/settings.json"
run_install "$home" --agents --commands --settings --gemini
assert_absent "$home/.gemini/agents/composer.md"
assert_absent "$home/.gemini/agents/conductor.md"
assert_file "$home/.gemini/agents/architect.md"
for pair in specify:composer implement:conductor; do
  command=${pair%:*}
  agent=${pair#*:}
  toml="$home/.gemini/commands/$command.toml"
  assert_file "$toml"
  assert_toml_parses "$toml"
  # The protocol itself, not a summary of it. Derived from the canonical file
  # so the assertion cannot drift out of date, and distinct per agent so an
  # installer that inlined the wrong body still fails.
  assert_file_contains "$toml" \
    "$(first_body_line "$SCRIPT_DIR/../.agents/agents/$agent.md")"
  # The command's own body and argument block survive alongside it.
  assert_file_contains "$toml" '{{args}}'
  # Gemini's TOML command schema is `prompt` plus optional `description`, and
  # unknown keys are stripped without a warning. An `agent` key written here
  # would be a control that looks present and does nothing.
  if grep -q '^agent[[:space:]]*=' "$toml"; then
    printf 'unexpected agent key in %s\n' "$toml" >&2
    exit 1
  fi
  # Gemini has no `context: fork` equivalent, so the orchestrator shares the
  # primary session's history. The generated text has to say so.
  assert_file_contains "$toml" '/chat clear'
done
# Under the default approval mode a stage agent receives neither `write_file`
# nor `replace`: measured on 0.58.0, an agent declaring `read_file`,
# `write_file`, `replace` and `run_shell_command` gets 2 tools under `default`
# and 4 under `auto_edit`. The pipeline then cannot write a spec or a plan and
# reports success anyway. `general.defaultApprovalMode` carries the mitigation
# without a flag, and is the only one of the two that a settings file can hold:
# `"yolo"` there is discarded and falls back to `default`.
jq -e '.general.defaultApprovalMode == "auto_edit"' \
  "$home/.gemini/settings.json" >/dev/null
# The merge is a deep merge, so a host-local sibling key survives it.
jq -e '.general.vimMode == true' "$home/.gemini/settings.json" >/dev/null
# The policy engine honors a singular `[[rule]]` table with a `decision` field.
# The plural table and the `action` field, both of which the shipped Gemini
# documentation uses, are discarded with no diagnostic at all.
assert_file_contains "$home/.gemini/policies/safe-commands.toml" '[[rule]]'
assert_file_contains "$home/.gemini/policies/safe-commands.toml" 'decision ='
if grep -q '^\[\[rules\]\]' "$home/.gemini/policies/safe-commands.toml"; then
  printf 'unexpected plural [[rules]] table in installed policy\n' >&2
  exit 1
fi
if grep -q '^action[[:space:]]*=' "$home/.gemini/policies/safe-commands.toml"; then
  printf 'unexpected action key in installed policy\n' >&2
  exit 1
fi

# The inlined body lands inside a TOML literal string that Gemini expands
# before it runs the prompt. All three counts are 0 in the canonical bodies
# today, which is exactly why the guard needs a planted body to prove it fires:
# ''' closes the string early, !{...} executes a shell command at expansion
# time, and @{...} reads a file.
fake_repo="$TEST_ROOT/guard-repo"
mkdir -p "$fake_repo/scripts"
cp -R -- "$SCRIPT_DIR/../.agents" "$fake_repo/.agents"
cp -R -- "$SCRIPT_DIR/../templates" "$fake_repo/templates"
cp -- "$INSTALLER" "$fake_repo/scripts/install.sh"
for sigil in "'''" '!{echo pwned}' '@{/etc/passwd}'; do
  printf -- '---\nname: composer\ndescription: "planted"\n---\n\nBody with %s in it.\n' \
    "$sigil" >"$fake_repo/.agents/agents/composer.md"
  guard_home=$(new_home "guard-$(printf '%s' "$sigil" | cksum | cut -d' ' -f1)")
  if guard_output=$(NO_COLOR=1 HOME="$guard_home" \
    sh "$fake_repo/scripts/install.sh" --commands --gemini 2>&1); then
    printf 'expected the installer to reject an inlined body containing %s\n' \
      "$sigil" >&2
    exit 1
  fi
  assert_contains "$guard_output" 'refusing to inline'
  assert_absent "$guard_home/.gemini/commands/specify.toml"
done

home=$(new_home copilot-reasoning-effort)
run_install "$home" --agents --copilot
# A Copilot view that pins no effort runs at whatever effort the parent
# session happened to hold, so every view pins one. The levels themselves are
# per host: each host pins against its own models, and OpenCode's set already
# differs from Claude's, including agents it leaves unpinned entirely.
# The architect is the one agent whose level is not Claude's. Copilot resolves
# each level against the pinned model, and the level set differs per model:
# `GPT-5.5 (copilot)` offers no `max`, so the `max` Claude's architect uses
# would be dropped at dispatch and the agent would fall back to the session
# effort. `xhigh` is that model's ceiling and keeps the intent. Claude's
# architect can use `max` because it runs on Opus, which has it. Do not
# "restore" `max` here to match Claude without also changing the pinned model:
# the loader accepts any string for this key without warning, so a level the
# model does not offer installs clean and fails silently later.
assert_frontmatter "$home/.copilot/agents/architect.agent.md" 'reasoning-effort: xhigh'
assert_frontmatter "$home/.copilot/agents/sleuth.agent.md" 'reasoning-effort: xhigh'
for agent in arch-review composer conductor planner \
  go-coder go-tester ts-coder ts-tester; do
  assert_frontmatter "$home/.copilot/agents/$agent.agent.md" 'reasoning-effort: high'
done
# Copilot CLI 1.0.82 spells this key in kebab case, like its sibling
# `mcp-servers`, and not the `reasoningEffort` its own documentation table
# prints. The camel-case spelling is dropped as an unknown field, which costs
# nothing visible and silently leaves the agent on the parent's effort, so the
# two spellings are not interchangeable and the wrong one cannot be caught by
# reading the installed file. Pin the accepted one on every view.
for view in "$home"/.copilot/agents/*.agent.md; do
  assert_no_frontmatter_key "$view" 'reasoningEffort'
done
# Every frontmatter key outside Copilot's agent schema costs one
# "unknown field ignored" warning per file on every session start.
# `argument-hint` is a prompt and skill key, which is why the prompt templates
# still carry it, and `agents` describes IDE-side delegation that the CLI
# expresses through the `agent` tool alias inside `tools`. Neither reaches the
# agent loader, so neither may reappear here.
for view in "$home"/.copilot/agents/*.agent.md; do
  assert_no_frontmatter_key "$view" 'argument-hint'
  assert_no_frontmatter_key "$view" 'agents'
done

home=$(new_home sleuth-report-terminal)
run_install "$home" --agents --claude
# The sleuth workflow is an ordered list the agent executes, and it treats the
# last step as its final output. While that step was the `improve-self` trigger
# check, the agent closed on its own self-assessment and the deliverable had to
# be requested in a second message, costing a full extra run every time. So the
# report has to be the step that ends the list, and the self-assessment has to
# survive as a step that no longer ends it. Assert both: a body that drops the
# self-assessment altogether would satisfy the first half on its own.
sleuth_agent="$home/.claude/agents/sleuth.md"
assert_file "$sleuth_agent"
sleuth_workflow=$(sed -n '/^## Workflow$/,/^## /p' "$sleuth_agent")
sleuth_last_step=$(printf '%s\n' "$sleuth_workflow" | grep '^[0-9][0-9]*\. ' | tail -n 1)
assert_contains "$sleuth_last_step" '**Deliver the report.**'
assert_not_contains "$sleuth_last_step" 'improve-self'
assert_contains "$sleuth_workflow" '**Self-assess.**'
# That last step has to point somewhere, or it is one more imperative competing
# with the five above it. The output contract lives in its own section.
assert_file_contains "$sleuth_agent" '## Report'

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

# A document far over its word budget is a scope signal, not a writing problem,
# and the validator knows the number before review does. Both sides are
# asserted: a band that also fires on a modest overrun teaches the agent to
# ignore it, which costs more than saying nothing.
budget_warning='if it covers more than one independently shippable goal'
split_guidance='Ask the user whether to split it into two'

huge_spec="$TEST_ROOT/Spec-huge.md"
filler_spec 14000 "$huge_spec"
if huge_output=$(python3 "$validator" "$huge_spec"); then
  printf 'expected the validator to fail on a spec with no sections\n' >&2
  exit 1
fi
assert_contains "$huge_output" 'document_words=14000'
assert_contains "$huge_output" "$budget_warning"
assert_contains "$huge_output" "$split_guidance"

slight_spec="$TEST_ROOT/Spec-slightly-over.md"
filler_spec 7100 "$slight_spec"
if slight_output=$(python3 "$validator" "$slight_spec"); then
  printf 'expected the validator to fail on a spec with no sections\n' >&2
  exit 1
fi
assert_contains "$slight_output" 'document_words=7100'
assert_contains "$slight_output" "$budget_warning"
assert_not_contains "$slight_output" "$split_guidance"

# The broken spec above is two words long, so neither band may fire on it.
assert_not_contains "$validator_output" "$budget_warning"
assert_not_contains "$validator_output" "$split_guidance"

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
