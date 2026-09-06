# Agent definition placement. The orchestrator content rules live in
# orchestrators.bats, the Gemini skip logic in gemini-agents.bats.

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
