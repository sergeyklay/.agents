load 'test_helper'

@test "--rules installs rules without the global context" {
  run install_into --rules --claude
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.claude/rules/commit-messages.md"
  assert_absent "$TEST_HOME/.claude/CLAUDE.md"
}

# The absence below is equally satisfied by an installer that wrote nothing,
# so commit-messages, which carries no Claude overlay, rides along as the
# control proving the OpenCode destination was reached at all.
@test "a Claude paths overlay keeps a rule out of OpenCode" {
  run install_into --rules --claude --copilot --opencode
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.claude/rules/go-toolchain.md"
  assert_file "$TEST_HOME/.copilot/instructions/go-toolchain.instructions.md"
  assert_absent "$TEST_HOME/.config/opencode/rules/go-toolchain.md"
  assert_file "$TEST_HOME/.config/opencode/rules/commit-messages.md"
}
