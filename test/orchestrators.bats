load 'test_helper'

# Orchestrators inspect artifacts they never write; every host with a tool
# list must carry both a content search and a filename search.
@test "orchestrator views carry content and filename search tools" {
  run install_into --agents
  [ "$status" -eq 0 ]
  for agent in composer conductor; do
    assert_frontmatter "$TEST_HOME/.claude/agents/$agent.md" '  - Grep'
    assert_frontmatter "$TEST_HOME/.claude/agents/$agent.md" '  - Glob'
    assert_frontmatter "$TEST_HOME/.copilot/agents/$agent.agent.md" '  - search/textSearch'
    assert_frontmatter "$TEST_HOME/.copilot/agents/$agent.agent.md" '  - search/fileSearch'
    # OpenCode has no tool list to widen: an agent naming no tools keeps the
    # default `"*": allow`, and an explicit `tools` key fails the whole
    # config load on OpenCode 1.18.27.
    assert_no_frontmatter_key "$TEST_HOME/.config/opencode/agents/$agent.md" 'tools'
  done
  # Gemini receives no orchestrator; see gemini-agents.bats.
  for agent in architect arch-review planner sleuth \
    go-coder go-tester ts-coder ts-tester; do
    assert_frontmatter "$TEST_HOME/.gemini/agents/$agent.md" '  - grep_search'
    assert_frontmatter "$TEST_HOME/.gemini/agents/$agent.md" '  - glob'
  done
}

# OpenCode 1.18.27 derives subagent permissions and appends `task: deny` and
# `todowrite: deny` unless the agent carries rules named literally that; a
# blanket `"*": allow` resolves to a rule named `*` and does not satisfy it.
# Without the spelled-out keys the tool is dropped silently and the agent
# simply never delegates.
@test "OpenCode orchestrators keep the delegation protocol" {
  run install_into --agents --settings --opencode
  [ "$status" -eq 0 ]
  for agent in composer conductor; do
    assert_frontmatter "$TEST_HOME/.config/opencode/agents/$agent.md" 'permission:'
    assert_frontmatter "$TEST_HOME/.config/opencode/agents/$agent.md" '  task: allow'
    assert_frontmatter "$TEST_HOME/.config/opencode/agents/$agent.md" '  todowrite: allow'
  done
  # Cancelling the deny leaves the depth ceiling; at the default of 1 a
  # subagent cannot spawn one. The setting is global, so the repo copy must
  # carry it.
  assert_file_contains "$TEST_HOME/.config/opencode/opencode.json" '"subagent_depth": 2'
}

# A `"*"` here outranks OpenCode's built-in skill allow-list: merge concats and
# evaluate takes the last match.
@test "OpenCode settings keep the built-in external_directory allow-list" {
  run install_into --settings --skills --opencode
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.config/opencode/skills/writing-specs/references/authoring-procedure.md"
  jq -e '
    .permission.external_directory as $rules
    | ($rules | has("*") | not)
      and ($rules["~/.config/opencode/**"] == "allow")
      and ($rules["~/.claude/skills/**"] == "allow")
  ' "$TEST_HOME/.config/opencode/opencode.json" >/dev/null
}

# A view that pins no effort inherits the parent session's, so every view pins
# one. Levels are per model: `GPT-5.5 (copilot)` offers no `max`, so the
# architect pins `xhigh`, that model's ceiling. The loader accepts any string
# without warning, so a level the model does not offer installs clean and
# fails silently. Do not restore `max` without also changing the pinned model.
@test "Copilot views pin a reasoning effort per model" {
  run install_into --agents --copilot
  [ "$status" -eq 0 ]
  assert_frontmatter "$TEST_HOME/.copilot/agents/architect.agent.md" 'reasoning-effort: xhigh'
  assert_frontmatter "$TEST_HOME/.copilot/agents/sleuth.agent.md" 'reasoning-effort: xhigh'
  for agent in arch-review composer conductor planner \
    go-coder go-tester ts-coder ts-tester; do
    assert_frontmatter "$TEST_HOME/.copilot/agents/$agent.agent.md" 'reasoning-effort: high'
  done
}

# Copilot CLI 1.0.82 spells this key `reasoning-effort`, not the
# `reasoningEffort` its documentation prints; the camel-case spelling is
# dropped silently and leaves the agent on the parent's effort.
@test "Copilot views use the kebab-case effort key" {
  run install_into --agents --copilot
  [ "$status" -eq 0 ]
  for view in "$TEST_HOME"/.copilot/agents/*.agent.md; do
    assert_no_frontmatter_key "$view" 'reasoningEffort'
  done
}

# Keys outside Copilot's agent schema cost one warning per file per session
# start. `argument-hint` is a prompt/skill key; `agents` describes IDE-side
# delegation, which the CLI expresses through the `agent` tool alias.
@test "Copilot views carry no prompt or IDE keys" {
  run install_into --agents --copilot
  [ "$status" -eq 0 ]
  for view in "$TEST_HOME"/.copilot/agents/*.agent.md; do
    assert_no_frontmatter_key "$view" 'argument-hint'
    assert_no_frontmatter_key "$view" 'agents'
  done
}

@test "agent views spend each list number once" {
  run install_into --agents
  [ "$status" -eq 0 ]
  for view in "$TEST_HOME"/.claude/agents/*.md \
    "$TEST_HOME"/.copilot/agents/*.agent.md \
    "$TEST_HOME"/.gemini/agents/*.md \
    "$TEST_HOME"/.config/opencode/agents/*.md; do
    assert_file "$view"
    assert_unique_list_numbers "$view"
  done
}

# The workflow's last step is the agent's final output. While that step was
# the improve-self check, the agent closed on its own self-assessment and the
# deliverable needed a second run. The report must end the list; the
# self-assessment must remain a non-final step. A body dropping the
# self-assessment would satisfy the first half alone.
@test "sleuth ends its workflow with the report" {
  run install_into --agents --claude
  [ "$status" -eq 0 ]
  sleuth_agent="$TEST_HOME/.claude/agents/sleuth.md"
  assert_file "$sleuth_agent"
  sleuth_workflow=$(sed -n '/^## Workflow$/,/^## /p' "$sleuth_agent")
  sleuth_last_step=$(printf '%s\n' "$sleuth_workflow" | grep '^[0-9][0-9]*\. ' | tail -n 1)
  assert_contains "$sleuth_last_step" '**Deliver the report.**'
  assert_not_contains "$sleuth_last_step" 'improve-self'
  assert_contains "$sleuth_workflow" '**Self-assess.**'
  # The final step points at the output contract rather than restating it.
  assert_file_contains "$sleuth_agent" '## Report'
}
