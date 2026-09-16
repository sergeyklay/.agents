# Orchestrator content rules live in orchestrators.bats, the Gemini skip
# logic in gemini-agents.bats.
load 'test_helper'

@test "--agents installs agent views on every host" {
  run install_into --agents
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.claude/agents/arch-review.md"
  assert_file "$TEST_HOME/.copilot/agents/arch-review.agent.md"
  assert_file "$TEST_HOME/.gemini/agents/arch-review.md"
  assert_file "$TEST_HOME/.config/opencode/agents/arch-review.md"
  assert_file "$TEST_HOME/.codex/agents/arch-review.toml"
}

@test "Claude agent views list no dead Task tool names" {
  run install_into --agents --claude
  [ "$status" -eq 0 ]
  for view in "$TEST_HOME"/.claude/agents/*.md; do
    assert_file "$view"
    for dead in Task TaskCreate TaskGet TaskList TaskUpdate; do
      assert_no_frontmatter "$view" "  - $dead"
    done
  done
}

@test "Claude agent views keep the live Agent and TaskStop tools" {
  run install_into --agents --claude
  [ "$status" -eq 0 ]
  for agent in composer conductor sleuth; do
    assert_frontmatter "$TEST_HOME/.claude/agents/$agent.md" '  - Agent'
  done
  for agent in sleuth go-coder ts-coder; do
    assert_frontmatter "$TEST_HOME/.claude/agents/$agent.md" '  - TaskStop'
  done
}

# A `tools` list fails OpenCode's schema decode uncaught, so one agent file
# takes all ten down; a canonical body reaches the view with templates clean.
@test "OpenCode agent templates and views declare no tools key" {
  run install_into --agents --opencode
  [ "$status" -eq 0 ]
  for template in "$ROOT"/templates/.opencode/agents/*.yaml; do
    assert_file "$template"
    assert_no_yaml_key "$template" 'tools'
  done
  for view in "$TEST_HOME"/.config/opencode/agents/*.md; do
    assert_file "$view"
    assert_no_frontmatter_key "$view" 'tools'
  done
}

# Every host dispatches an agent by its `name:`, so a template that overrides
# it makes one call, typed by the user or written in a delegating body, reach
# the agent on one host and miss it on the next.
@test "agent views answer to their canonical name on every host" {
  run install_into --agents
  [ "$status" -eq 0 ]
  local spec host dir suffix source_body agent view views
  for spec in \
    "claude|$TEST_HOME/.claude/agents|.md" \
    "copilot|$TEST_HOME/.copilot/agents|.agent.md" \
    "gemini|$TEST_HOME/.gemini/agents|.md" \
    "opencode|$TEST_HOME/.config/opencode/agents|.md"; do
    IFS='|' read -r host dir suffix <<<"$spec"
    views=0
    for source_body in "$ROOT"/.agents/agents/*.md; do
      agent=$(basename -- "$source_body" .md)
      view="$dir/$agent$suffix"
      # Gemini receives no orchestrator; see gemini-agents.bats.
      case "$host:$agent" in
      gemini:composer | gemini:conductor) continue ;;
      esac
      assert_file "$view"
      assert_frontmatter "$view" "name: $agent"
      views=$((views + 1))
    done
    [ "$views" -gt 0 ] || fail "no agent view under $dir to check"
  done
}
