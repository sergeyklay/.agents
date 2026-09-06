# Rules installation. `--rules` does not remove stale destination files.

load 'test_helper'

@test "--rules installs rules without the global context" {
  run install_into --rules --claude
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.claude/rules/commit-messages.md"
  assert_absent "$TEST_HOME/.claude/CLAUDE.md"
}
