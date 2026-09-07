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
  assert_absent "$TEST_HOME/.codex/agents"
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
