load 'test_helper'

MEASURE="$ROOT/test/measure-comment-style.bash"
HOOK="$ROOT/.claude/hooks/check-comment-style.sh"

# The script reads the hook at a revision, so the fixture commits a hook without
# the em-dash rule and leaves the full hook in the working tree.
fixture_repo() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/.claude/hooks" "$REPO/test"
  cp "$MEASURE" "$REPO/test/"
  grep -v 'return "em-dash"' "$HOOK" >"$REPO/.claude/hooks/check-comment-style.sh"
  chmod +x "$REPO/.claude/hooks/check-comment-style.sh"
  git -C "$REPO" init -q
  git -C "$REPO" add .
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -qm fixture
  cp "$HOOK" "$REPO/.claude/hooks/check-comment-style.sh"
  assert_contains "$(git -C "$REPO" diff --stat)" 'check-comment-style.sh'
}

@test "the measurement names a report the working tree adds" {
  fixture_repo || return 1
  mkdir -p "$BATS_TEST_TMPDIR/corpus"
  printf 'package p\n\n// warm it \342\200\224 then read\nvar x = 1\n' >"$BATS_TEST_TMPDIR/corpus/probe.go"
  run "$REPO/test/measure-comment-style.bash" -r HEAD "$BATS_TEST_TMPDIR/corpus:*.go"
  [ "$status" -eq 0 ] || fail "expected exit 0, got $status"$'\n'"$output"
  assert_contains "$output" "+ $BATS_TEST_TMPDIR/corpus/probe.go: line 3 [em-dash]"
}

@test "a corpus with no matching file fails the measurement" {
  fixture_repo || return 1
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  run "$REPO/test/measure-comment-style.bash" -r HEAD "$BATS_TEST_TMPDIR/empty:*.go"
  [ "$status" -eq 1 ] || fail "expected exit 1, got $status"$'\n'"$output"
  assert_contains "$output" 'a zero here is not a clean corpus'
}

@test "a corpus find cannot fully read fails the measurement" {
  [ "$(id -u)" -ne 0 ] || skip 'root reads a mode-000 directory, so the partial corpus goes unchecked'
  fixture_repo || return 1
  local corpus="$BATS_TEST_TMPDIR/partial"
  mkdir -p "$corpus/locked"
  printf 'package p\n' >"$corpus/open.go"
  printf 'package p\n' >"$corpus/locked/hidden.go"
  chmod 000 "$corpus/locked"
  if ls "$corpus/locked" >/dev/null 2>&1; then
    chmod 755 "$corpus/locked"
    fail 'mode 000 left the directory readable'
  fi
  run "$REPO/test/measure-comment-style.bash" -r HEAD "$corpus:*.go"
  chmod 755 "$corpus/locked"
  [ "$status" -eq 1 ] || fail "expected exit 1, got $status"$'\n'"$output"
  assert_contains "$output" 'the counts cover part of the corpus'
}
