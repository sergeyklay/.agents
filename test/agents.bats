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

# OpenCode types `tools` as a deprecated name-to-boolean map
# (`$defs.AgentConfig.properties.tools` in https://opencode.ai/config.json), so
# the YAML list every other host uses fails schema decoding uncaught and one
# agent file takes all ten agents down. Both layers are checked because they
# diverge: a canonical body's `tools` reaches the view, leaving templates clean.
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
