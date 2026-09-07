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

@test "assert_no_frontmatter matches a needle that starts with a dash" {
  printf '%s\n' '---' 'tools:' '- Task' '' '---' '' 'Body.' >"$FIXTURE"
  run assert_no_frontmatter "$FIXTURE" '- Task'
  [ "$status" -ne 0 ] || fail "assert_no_frontmatter missed a dash-leading needle"
  assert_contains "$output" "unexpected frontmatter line in $FIXTURE: - Task"
}

@test "assert_no_frontmatter_key catches every accepted key spelling" {
  for form in 'mcp_servers:' '"mcp_servers":' "'mcp_servers':" 'mcp_servers :' \
    '!!str mcp_servers:' '&a mcp_servers:' '&a !!str mcp_servers :'; do
    printf '%s\n' '---' 'name: demo' "$form" '---' '' 'Body.' >"$FIXTURE"
    run assert_no_frontmatter_key "$FIXTURE" mcp_servers
    [ "$status" -ne 0 ] || fail "assert_no_frontmatter_key missed the spelling: $form"
    assert_contains "$output" "unexpected frontmatter key in $FIXTURE: mcp_servers"
  done
}

@test "assert_no_frontmatter_key ignores a key the frontmatter never declares" {
  printf '%s\n' '---' 'nested:' '  mcp_servers: x' 'list:' '  - mcp_servers' \
    'value: mcp_servers' 'quoted: "mcp_servers:"' 'mcp_servers_extra: x' \
    '---' '' 'mcp_servers: x' >"$FIXTURE"
  run assert_no_frontmatter_key "$FIXTURE" mcp_servers
  [ "$status" -eq 0 ] || fail "assert_no_frontmatter_key over-blocked: $output"
}

@test "assert_no_frontmatter_key matches a key with regex metacharacters literally" {
  run assert_no_frontmatter_key "$FIXTURE" 'nam.|demo'
  [ "$status" -eq 0 ] || fail "assert_no_frontmatter_key read the key as a pattern: $output"
}
