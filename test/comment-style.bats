load 'test_helper'

GATE="$ROOT/test/comment_style.py"

# The gate reads `git ls-files`, so a fixture is a repository with the
# violating file staged (see AGENTS.md Gotchas).
stage_probe() {
  PROBE="$BATS_TEST_TMPDIR/probe"
  mkdir -p "$PROBE"
  git -C "$PROBE" init -q
  cat >"$PROBE/probe.py"
  git -C "$PROBE" add probe.py
}

@test "every tracked Python file passes the comment gate" {
  run python3 "$GATE" "$ROOT"
  [ -z "$output" ] || fail "comment-style violations:"$'\n'"$output"
  [ "$status" -eq 0 ]
}

@test "the comment gate rejects a banner separator" {
  stage_probe <<'EOF'
# -----------------------------------------------------------------
def probe(value: int) -> int:
    return value
EOF
  run python3 "$GATE" "$PROBE"
  [ "$status" -eq 1 ]
  assert_contains "$output" 'banner separator'
}

@test "the comment gate rejects a step label" {
  stage_probe <<'EOF'
def probe(value: int) -> int:
    # step 1: double it
    total = value * 2
    total = total + 1
    total = total - 1
    total = total * 1
    # 2: hand it back
    return total
EOF
  run python3 "$GATE" "$PROBE"
  [ "$status" -eq 1 ]
  assert_contains "$output" 'step or section label'
}

@test "the comment gate rejects a file over the density ceiling" {
  stage_probe <<'EOF'
# The caller passes an integer.
# The function hands the integer straight back.
# Nothing else happens in here.
def probe(value: int) -> int:
    return value
EOF
  run python3 "$GATE" "$PROBE"
  [ "$status" -eq 1 ]
  assert_contains "$output" 'ceiling 35%'
}
