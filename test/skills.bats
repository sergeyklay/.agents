load 'test_helper'

@test "--skills installs skills on every host" {
  run install_into --skills
  [ "$status" -eq 0 ]
  for skill_root in "$TEST_HOME/.claude/skills" "$TEST_HOME/.codex/skills" \
    "$TEST_HOME/.copilot/skills" "$TEST_HOME/.gemini/skills" \
    "$TEST_HOME/.config/opencode/skills"; do
    assert_file "$skill_root/context-files/SKILL.md"
  done
}

# The writing-specs authoring procedure controls edit churn; skills install
# to all five hosts, so every copy must carry it, not only Claude's.
@test "writing-specs authoring procedure ships to every host" {
  run install_into --skills
  [ "$status" -eq 0 ]
  for skill_root in "$TEST_HOME/.claude/skills" "$TEST_HOME/.codex/skills" \
    "$TEST_HOME/.copilot/skills" "$TEST_HOME/.gemini/skills" \
    "$TEST_HOME/.config/opencode/skills"; do
    spec_skill="$skill_root/writing-specs/SKILL.md"
    assert_file "$spec_skill"
    assert_file_contains "$spec_skill" '#### Authoring procedure'
    assert_file_contains "$spec_skill" \
      '**Draft the whole document before the first write.**'
    assert_file_contains "$spec_skill" \
      '**Group revisions into as few calls as the host allows.**'
    assert_file_contains "$spec_skill" \
      '**Never re-read a file you wrote yourself.**'
  done
}

# The validator gathers every error before printing; the failure line must
# say so or agents re-run it after each single fix. The broken spec is two
# words long, so neither budget band may fire on it.
@test "the spec validator gathers every error before reporting" {
  run install_into --skills
  [ "$status" -eq 0 ]
  validator="$TEST_HOME/.claude/skills/writing-specs/scripts/validate_spec.py"
  broken_spec="$BATS_TEST_TMPDIR/Spec-broken.md"
  printf '# Broken\n' >"$broken_spec"
  run python3 "$validator" "$broken_spec"
  [ "$status" -ne 0 ]
  assert_contains "$output" 'VALIDATION_RESULT=FAIL'
  assert_contains "$output" 'fix all errors in one pass, then re-run once'
  assert_not_contains "$output" "$BUDGET_WARNING"
  assert_not_contains "$output" "$SPLIT_GUIDANCE"
}

# A document far over budget is a scope signal, not a writing problem. Both
# bands are asserted: one firing on a modest overrun teaches the agent to
# ignore it.
@test "a far-over-budget spec gets split guidance" {
  run install_into --skills
  [ "$status" -eq 0 ]
  validator="$TEST_HOME/.claude/skills/writing-specs/scripts/validate_spec.py"
  huge_spec="$BATS_TEST_TMPDIR/Spec-huge.md"
  filler_spec 14000 "$huge_spec"
  run python3 "$validator" "$huge_spec"
  [ "$status" -ne 0 ]
  assert_contains "$output" 'document_words=14000'
  assert_contains "$output" "$BUDGET_WARNING"
  assert_contains "$output" "$SPLIT_GUIDANCE"
}

@test "a slightly-over-budget spec warns without split guidance" {
  run install_into --skills
  [ "$status" -eq 0 ]
  validator="$TEST_HOME/.claude/skills/writing-specs/scripts/validate_spec.py"
  slight_spec="$BATS_TEST_TMPDIR/Spec-slightly-over.md"
  filler_spec 7100 "$slight_spec"
  run python3 "$validator" "$slight_spec"
  [ "$status" -ne 0 ]
  assert_contains "$output" 'document_words=7100'
  assert_contains "$output" "$BUDGET_WARNING"
  assert_not_contains "$output" "$SPLIT_GUIDANCE"
}
