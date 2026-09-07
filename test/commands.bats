# The Gemini prompt sigil and path traversal guards live in gemini-guard.bats.
load 'test_helper'

# Orchestrator commands must fork, and the fork must survive past the invoking
# turn or it never receives the subagent's completion notification.
@test "orchestrator commands fork without pinning the turn" {
  run install_into --commands --claude
  [ "$status" -eq 0 ]
  for command in specify implement; do
    assert_file "$TEST_HOME/.claude/commands/$command.md"
    assert_frontmatter "$TEST_HOME/.claude/commands/$command.md" 'context: fork'
    assert_no_frontmatter_key "$TEST_HOME/.claude/commands/$command.md" 'background'
  done
  assert_frontmatter "$TEST_HOME/.claude/commands/specify.md" 'agent: composer'
  assert_frontmatter "$TEST_HOME/.claude/commands/implement.md" 'agent: conductor'
}

# Gemini CLI 0.58.0 keeps invoke_agent only in the primary session, so the
# orchestrator protocol ships as a command with `agent: <name>` inlining the
# canonical agent body into the generated prompt.
@test "Gemini command TOML inlines the canonical orchestrator body" {
  run install_into --commands --gemini
  [ "$status" -eq 0 ]
  for pair in specify:composer implement:conductor; do
    command=${pair%:*}
    agent=${pair#*:}
    toml="$TEST_HOME/.gemini/commands/$command.toml"
    assert_file "$toml"
    assert_toml_parses "$toml"
    # Derived from the canonical file so it cannot drift; distinct per agent
    # so inlining the wrong body still fails.
    assert_file_contains "$toml" "$(first_body_line "$ROOT/.agents/agents/$agent.md")"
    assert_file_contains "$toml" '{{args}}'
    # Unknown keys in the TOML command schema are stripped without warning;
    # an `agent` key would look present and do nothing.
    if grep -q '^agent[[:space:]]*=' "$toml"; then
      fail "unexpected agent key in $toml"
    fi
  done
}

@test "Gemini review command TOML inlines the arch-review body" {
  run install_into --commands --gemini
  [ "$status" -eq 0 ]
  for command in vet-impl vet-spec; do
    toml="$TEST_HOME/.gemini/commands/$command.toml"
    assert_file "$toml"
    assert_toml_parses "$toml"
    assert_file_contains "$toml" "$(first_body_line "$ROOT/.agents/agents/arch-review.md")"
    assert_file_contains "$toml" '{{args}}'
    if grep -qF -- '@arch-review' "$toml"; then
      fail "inert bare mention left in $toml"
    fi
    if grep -q '^name: arch-review$' "$toml"; then
      fail "agent frontmatter leaked into $toml"
    fi
  done
}
