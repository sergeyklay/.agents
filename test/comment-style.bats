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

stage_shell_probe() {
  PROBE="$BATS_TEST_TMPDIR/shell-probe"
  mkdir -p "$PROBE"
  git -C "$PROBE" init -q
  cat >"$PROBE/probe.bats"
  git -C "$PROBE" add probe.bats
}

@test "every tracked source file passes the comment gate" {
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

@test "the comment gate rejects a banner separator in a bats file" {
  stage_shell_probe <<'PROBE'
# =================================================
@test "probe" {
  run true
}
PROBE
  run python3 "$GATE" "$PROBE"
  [ "$status" -eq 1 ]
  assert_contains "$output" 'banner separator'
}

@test "the comment gate reads no comment out of a heredoc body" {
  stage_shell_probe <<'PROBE'
@test "probe" {
  cat <<'INNER'
# ===============================
# step 1: this is data, not code
INNER
}
PROBE
  run python3 "$GATE" "$PROBE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the comment gate rejects a comment block over the ceiling" {
  stage_shell_probe <<'PROBE'
# one
# two
# three
# four
# five
# six
@test "probe" {
  run true
}
PROBE
  run python3 "$GATE" "$PROBE"
  [ "$status" -eq 1 ]
  assert_contains "$output" '6-line comment block'
}

@test "the comment gate allows a block at the ceiling" {
  stage_shell_probe <<'PROBE'
# one
# two
# three
# four
# five
@test "probe" {
  run true
}
PROBE
  run python3 "$GATE" "$PROBE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the comment gate rejects a docstring over the ceiling" {
  stage_probe <<'PROBE'
def probe() -> int:
    """Summary.

    one
    two
    three
    """
    return 1
PROBE
  run python3 "$GATE" "$PROBE"
  [ "$status" -eq 1 ]
  assert_contains "$output" '6-line docstring'
}

@test "the comment gate exempts a module docstring" {
  stage_probe <<'PROBE'
"""Module summary.

one
two
three
"""


def probe() -> int:
    total = 1
    total = total + 1
    total = total + 1
    total = total + 1
    total = total + 1
    total = total + 1
    total = total + 1
    total = total + 1
    return total
PROBE
  run python3 "$GATE" "$PROBE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
