load 'test_helper'

@test "--context installs the canonical context on every host" {
  run install_into --context
  [ "$status" -eq 0 ]
  assert_same "$CONTEXT" "$TEST_HOME/.claude/CLAUDE.md"
  assert_same "$CONTEXT" "$TEST_HOME/.codex/AGENTS.md"
  assert_same "$CONTEXT" "$TEST_HOME/.copilot/copilot-instructions.md"
  assert_same "$CONTEXT" "$TEST_HOME/.gemini/GEMINI.md"
  assert_same "$CONTEXT" "$TEST_HOME/.config/opencode/AGENTS.md"
}

@test "--context installs nothing but context" {
  run install_into --context
  [ "$status" -eq 0 ]
  assert_absent "$TEST_HOME/.copilot/instructions/context.instructions.md"
  assert_absent "$TEST_HOME/.claude/agents"
  assert_absent "$TEST_HOME/.codex/skills"
  assert_absent "$TEST_HOME/.copilot/agents"
  assert_absent "$TEST_HOME/.gemini/agents"
  assert_absent "$TEST_HOME/.config/opencode/agents"
}

@test "--context replaces a stale working-agreement rule with the canonical content" {
  mkdir -p "$TEST_HOME/.claude/rules" "$TEST_HOME/.copilot/instructions" \
    "$TEST_HOME/.config/opencode/rules"
  cp -- "$CONTEXT" "$TEST_HOME/.claude/rules/working-agreement.md"
  cp -- "$CONTEXT" "$TEST_HOME/.copilot/instructions/working-agreement.instructions.md"
  cp -- "$CONTEXT" "$TEST_HOME/.config/opencode/rules/working-agreement.md"
  printf '\n' >>"$TEST_HOME/.claude/rules/working-agreement.md"
  printf 'old context\n' >"$TEST_HOME/.claude/CLAUDE.md"
  run install_into --context --claude --copilot --opencode
  [ "$status" -eq 0 ]
  assert_same "$CONTEXT" "$TEST_HOME/.claude/CLAUDE.md"
  assert_absent "$TEST_HOME/.claude/rules/working-agreement.md"
  assert_absent "$TEST_HOME/.copilot/instructions/working-agreement.instructions.md"
  assert_absent "$TEST_HOME/.config/opencode/rules/working-agreement.md"
}

@test "--context preserves a modified stale rule" {
  mkdir -p "$TEST_HOME/.config/opencode/rules"
  cp -- "$CONTEXT" "$TEST_HOME/.config/opencode/rules/working-agreement.md"
  printf '\n# Local change\n' >>"$TEST_HOME/.config/opencode/rules/working-agreement.md"
  run install_into --context --opencode
  [ "$status" -eq 0 ]
  assert_contains "$output" 'modified stale file preserved'
  assert_file "$TEST_HOME/.config/opencode/rules/working-agreement.md"
  assert_same "$CONTEXT" "$TEST_HOME/.config/opencode/AGENTS.md"
}
