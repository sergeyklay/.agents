# Gemini skips the orchestrator agents entirely: Gemini CLI 0.58.0 strips
# agent-kind tools from subagent registries, so an orchestrator shipped as an
# agent loses invoke_agent silently. The protocol ships as a top-level
# command instead (see commands.bats).

load 'test_helper'

@test "Gemini receives no orchestrator agent" {
  run install_into --agents --gemini
  [ "$status" -eq 0 ]
  assert_absent "$TEST_HOME/.gemini/agents/composer.md"
  assert_absent "$TEST_HOME/.gemini/agents/conductor.md"
  assert_file "$TEST_HOME/.gemini/agents/architect.md"
}

# Skipping only stops writing: per-file views go through rsync without
# --delete, so a copy from an earlier install survives frozen, still
# advertising invoke_agent. The fresh-home case above passes trivially; this
# is the one that matters for a machine that ran the old installer.
@test "a stale Gemini orchestrator is removed" {
  mkdir -p "$TEST_HOME/.gemini/agents"
  for agent in composer conductor; do
    printf -- '---\nname: %s\ntools:\n  - invoke_agent\n---\n\nstale body\n' \
      "$agent" >"$TEST_HOME/.gemini/agents/$agent.md"
  done
  run install_into --agents --gemini
  [ "$status" -eq 0 ]
  assert_absent "$TEST_HOME/.gemini/agents/composer.md"
  assert_absent "$TEST_HOME/.gemini/agents/conductor.md"
  assert_contains "$output" 'removed disarmed orchestrator'
  # The removal is keyed to the skip list, not to the directory.
  assert_file "$TEST_HOME/.gemini/agents/architect.md"
  assert_file "$TEST_HOME/.gemini/agents/sleuth.md"
}

# rm -f fails on a directory and the installer runs under set -e, so a
# directory at the destination aborts the run before the summary prints. The
# directory must be reported and survive; the loop must continue past it.
@test "a directory at a stale orchestrator path is preserved" {
  mkdir -p "$TEST_HOME/.gemini/agents/composer.md"
  printf 'not an agent\n' >"$TEST_HOME/.gemini/agents/composer.md/inner.txt"
  printf -- '---\nname: conductor\n---\n\nstale body\n' \
    >"$TEST_HOME/.gemini/agents/conductor.md"
  run install_into --agents --gemini
  [ "$status" -eq 0 ]
  assert_contains "$output" 'not a regular file'
  assert_contains "$output" ':: Installation complete'
  [ -d "$TEST_HOME/.gemini/agents/composer.md" ]
  assert_absent "$TEST_HOME/.gemini/agents/conductor.md"
  assert_file "$TEST_HOME/.gemini/agents/architect.md"
}
