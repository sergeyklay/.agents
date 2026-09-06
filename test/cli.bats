# CLI behavior: help, argument handling, plan reporting, host selection.

load 'test_helper'

@test "--help documents usage, assets, hosts, and examples" {
  run env NO_COLOR=1 TERM=xterm sh "$INSTALLER" --help
  [ "$status" -eq 0 ]
  assert_contains "$output" 'Usage'
  assert_contains "$output" 'Asset options'
  assert_contains "$output" 'Host options'
  assert_contains "$output" 'Examples'
  assert_contains "$output" '--context'
  assert_contains "$output" '# Install every supported asset for Claude Code.'
  assert_contains "$output" 'bash scripts/install.sh --agents --opencode'
  assert_contains "$output" 'bash scripts/install.sh --context --claude --gemini'
  assert_contains "$output" 'NO_COLOR'
}

@test "--help output is colorless" {
  escape=$(printf '\033')
  run env NO_COLOR=1 TERM=xterm sh "$INSTALLER" --help
  assert_not_contains "$output" "$escape"
}

@test "no options prints usage and exits 2" {
  run install_into
  [ "$status" -eq 2 ]
  assert_contains "$output" 'Usage'
}

@test "an unknown option fails with a hint" {
  run install_into --frobnicate
  [ "$status" -ne 0 ]
  assert_contains "$output" "unknown option: --frobnicate (try --help)"
}

@test "a positional argument fails with a hint" {
  run install_into extra
  [ "$status" -ne 0 ]
  assert_contains "$output" "unexpected argument: extra (try --help)"
}

@test "the installer reports the plan and the summary" {
  run install_into --agents --opencode
  [ "$status" -eq 0 ]
  escape=$(printf '\033')
  assert_contains "$output" ':: Installing agent assets'
  assert_contains "$output" 'Assets  agents'
  assert_contains "$output" 'Hosts   opencode'
  assert_contains "$output" 'Agent definitions'
  assert_contains "$output" \
    '+ .opencode/agents/arch-review -> ~/.config/opencode/agents/arch-review.md'
  assert_contains "$output" ':: Installation complete: 10 updated, 0 skipped'
  assert_not_contains "$output" 'Commands and prompts'
  assert_not_contains "$output" "$BATS_TEST_TMPDIR"
  assert_not_contains "$output" "$escape"
}

@test "host options select which hosts are installed" {
  run install_into --gemini --commands --opencode
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.gemini/commands/challenge-pr.toml"
  assert_file "$TEST_HOME/.config/opencode/commands/challenge-pr.md"
  assert_absent "$TEST_HOME/.claude/commands"
  assert_absent "$TEST_HOME/.copilot/prompts"
  assert_absent "$TEST_HOME/.gemini/agents"
  assert_absent "$TEST_HOME/.config/opencode/agents"
}

@test "no host option targets every registered host" {
  run install_into --commands
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.claude/commands/challenge-pr.md"
  assert_file "$TEST_HOME/.copilot/prompts/challenge-pr.prompt.md"
  assert_file "$TEST_HOME/.gemini/commands/challenge-pr.toml"
  assert_file "$TEST_HOME/.config/opencode/commands/challenge-pr.md"
  assert_absent "$TEST_HOME/.codex/commands"
  assert_absent "$TEST_HOME/.claude/CLAUDE.md"
}

@test "a host whose root directory is missing is skipped" {
  rmdir "$TEST_HOME/.codex"
  run install_into --codex
  [ "$status" -eq 0 ]
  assert_contains "$output" '- Codex not found at ~/.codex; skipping'
  assert_contains "$output" '- No destinations were updated (1 skipped)'
  assert_absent "$TEST_HOME/.codex"
}
