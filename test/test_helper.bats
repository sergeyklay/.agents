load 'test_helper'

setup() {
  FIXTURE="$BATS_TEST_TMPDIR/skill.md"
  # Without the blank line inside the frontmatter, assert_frontmatter fails
  # on its own and its test passes even with the guard removed.
  printf '%s\n' '---' 'name: demo' '' '---' '' 'Body.' >"$FIXTURE"
}

@test "assert_contains refuses an empty needle" {
  run assert_contains 'some real output' ''
  [ "$status" -ne 0 ] || fail "assert_contains passed on an empty needle"
  assert_contains "$output" 'refusing to match output against an empty needle'
}

@test "assert_file_contains refuses an empty needle" {
  run assert_file_contains "$FIXTURE" ''
  [ "$status" -ne 0 ] || fail "assert_file_contains passed on an empty needle"
  assert_contains "$output" "refusing to match $FIXTURE against an empty needle"
}

@test "assert_frontmatter refuses an empty needle" {
  run assert_frontmatter "$FIXTURE" ''
  [ "$status" -ne 0 ] || fail "assert_frontmatter passed on an empty needle"
  assert_contains "$output" \
    "refusing to match the frontmatter of $FIXTURE against an empty needle"
}

@test "assert_no_frontmatter_key refuses an empty key" {
  run assert_no_frontmatter_key "$FIXTURE" ''
  [ "$status" -ne 0 ] || fail "assert_no_frontmatter_key passed on an empty key"
  assert_contains "$output" \
    "refusing to match the frontmatter keys of $FIXTURE against an empty needle"
}

@test "assert_no_frontmatter refuses an empty needle" {
  run assert_no_frontmatter "$FIXTURE" ''
  [ "$status" -ne 0 ] || fail "assert_no_frontmatter passed on an empty needle"
  assert_contains "$output" \
    "refusing to match the frontmatter lines of $FIXTURE against an empty needle"
}
