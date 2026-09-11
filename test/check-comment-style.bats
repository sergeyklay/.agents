load 'test_helper'

HOOK="$ROOT/.claude/hooks/check-comment-style.sh"

# The hook is handed a path and reads the source off disk, so a fixture is both.
write_probe() {
  PROBE="$BATS_TEST_TMPDIR/$1"
  cat >"$PROBE"
}

run_hook() {
  jq -n --arg path "$1" '{tool_name: "Edit", tool_input: {file_path: $path}}' | "$HOOK"
}

run_hook_raw() {
  printf '%s' "$1" | "$HOOK"
}

assert_flagged() {
  [ "$status" -eq 2 ] || fail "expected exit 2, got $status"$'\n'"$output"
  assert_contains "$output" "$1" || return 1
}

# A rule asserted only by its positive case cannot be told from one that
# matches everything, so every exemption asserts silence as well as exit 0.
assert_clean() {
  [ "$status" -eq 0 ] || fail "expected exit 0, got $status"$'\n'"$output"
  [ -z "$output" ] || fail "expected no output"$'\n'"$output"
}

# jq cannot be shadowed off a PATH, so the probe PATH carries nothing at all.
path_without_jq() {
  local dir="$BATS_TEST_TMPDIR/nojq"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

@test "the hook rejects a sequence label" {
  write_probe probe.go <<'PROBE'
package p

// Phase 2 warms the cache
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'sequence/section label'
}

@test "the hook allows a sequence noun carrying no number" {
  write_probe probe.go <<'PROBE'
package p

// Steps taken before the cache warms
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects a spec artefact and number" {
  write_probe probe.go <<'PROBE'
package p

// the Appendix 2 value blocks the write
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'spec-criteria reference'
}

@test "the hook allows a spec artefact carrying no number" {
  write_probe probe.go <<'PROBE'
package p

// the Appendix explains why the write blocks
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects a spec-criteria prefix" {
  write_probe probe.go <<'PROBE'
package p

// pins the AC-1 contract
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'spec-criteria reference'
}

@test "the hook allows a spec-criteria prefix inside a longer word" {
  write_probe probe.go <<'PROBE'
package p

// pins the MAC-1 fixture row
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects a test-type reference" {
  write_probe probe.go <<'PROBE'
package p

// I-1: a decisive match wins
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'test-type reference'
}

@test "the hook allows the single letters used as fixture issue data" {
  write_probe probe.go <<'PROBE'
package p

// C-1 and D-1 are the fixture rows
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook allows the standard tokens the contract names" {
  write_probe probe.go <<'PROBE'
package p

// stamps are ISO-8601, bodies are UTF-8, hashes are SHA-256
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects an internal doc reference" {
  write_probe probe.go <<'PROBE'
package p

// see docs/architecture.md
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'internal doc/ADR reference'
}

@test "the hook rejects a numbered ADR reference" {
  write_probe probe.go <<'PROBE'
package p

// per ADR-3
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'internal doc/ADR reference'
}

@test "the hook allows an ADR mention carrying no number" {
  write_probe probe.go <<'PROBE'
package p

// the ADR review settled this
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects a banner decoration" {
  write_probe probe.go <<'PROBE'
package p

// --- Test helpers ---
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'banner decoration'
}

@test "the hook allows two frame characters" {
  write_probe probe.go <<'PROBE'
package p

// -- not quite a banner
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook allows a dash run inside a preformatted block" {
  printf 'package p\n\n// Sample output:\n//\t---\n//\tname: probe\nvar x = 1\n' \
    >"$BATS_TEST_TMPDIR/preformatted.go"
  run run_hook "$BATS_TEST_TMPDIR/preformatted.go"
  assert_clean
}

@test "the hook allows an editor file-variable line" {
  write_probe probe.py <<'PROBE'
# -*- coding: utf-8 -*-
x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook allows an ASCII box border" {
  write_probe probe.go <<'PROBE'
package p

// +----+
// | ok |
// +----+
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects an em-dash" {
  write_probe probe.go <<'PROBE'
package p

// no retry — the slot is hot
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'em-dash'
}

@test "the hook allows a spaced en-dash" {
  write_probe probe.go <<'PROBE'
package p

// no retry – the slot is hot
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects a section mark" {
  write_probe probe.go <<'PROBE'
package p

// per § 4 of the grammar
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'section-mark reference'
}

@test "the hook allows the same clause named without a section mark" {
  write_probe probe.go <<'PROBE'
package p

// per clause 4 of the grammar
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects an internal issue number" {
  write_probe probe.go <<'PROBE'
package p

// see #811 for the cause
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'internal issue number'
}

@test "the hook allows an upstream issue reference behind an owner prefix" {
  write_probe probe.go <<'PROBE'
package p

// fixed upstream in golang/go#22315
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook allows an upstream RFC citation" {
  write_probe probe.go <<'PROBE'
package p

// Phase 2 of the handshake is RFC 7231 section 6
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

# time.RFC3339 is stdlib Go, so a whole-line exemption disarms the guard on
# ordinary code rather than on the citation it was written for.
@test "an RFC constant in code does not exempt the comment beside it" {
  write_probe probe.go <<'PROBE'
package p

func f(t time.Time) string {
	return t.Format(time.RFC3339) // Phase 2 stamps it
}
PROBE
  run run_hook "$PROBE"
  assert_flagged 'sequence/section label'
}

@test "a docstring citing an RFC still hides its body" {
  write_probe probe.py <<'PROBE'
def f():
    """Notes on RFC 7231.

    # Phase 2 is not a comment
    """
    return 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects a spec artefact in a string literal" {
  write_probe probe.go <<'PROBE'
package p

var name = "Table 3.1-B"
PROBE
  run run_hook "$PROBE"
  assert_flagged 'spec reference outside a comment'
}

@test "the hook rejects an internal doc path in a string literal" {
  write_probe probe.go <<'PROBE'
package p

var doc = "docs/decisions/0001.md"
PROBE
  run run_hook "$PROBE"
  assert_flagged 'spec reference outside a comment'
}

# The code path carries two of the nine rules, not all of them, so a token the
# comment rules reject has to survive in a string literal.
@test "the hook allows a test-data ID in a string literal" {
  write_probe probe.go <<'PROBE'
package p

var key = "PROJ-42"
var criterion = "AC-1"
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook reads no comment out of a slash inside a string literal" {
  write_probe probe.js <<'PROBE'
const ratio = "a // Phase 2 b";
const half = (a, b) => a / b;
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook reads no comment out of a hash inside a Python string" {
  write_probe probe.py <<'PROBE'
ground = "#000000 Step 9"
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook reads a block comment that opens and closes on one line" {
  write_probe probe.go <<'PROBE'
package p

var x = 1 /* Step 2: seed it */
PROBE
  run run_hook "$PROBE"
  assert_flagged 'sequence/section label'
}

@test "the hook reads a block comment that spans lines" {
  write_probe probe.go <<'PROBE'
package p

/*
 * Table 3.1-B is the source.
 */
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'spec-criteria reference'
}

@test "the hook reads no comment out of a block marker inside a string" {
  write_probe probe.go <<'PROBE'
package p

var pat = "/* Step 8: not a comment */"
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook reads no comment out of a Python docstring body" {
  write_probe probe.py <<'PROBE'
def f():
    """Notes.

    # Step 5: not a comment
    """
    return 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook reads the same line as a comment outside a docstring" {
  write_probe probe.py <<'PROBE'
def f():
    # Step 5: this one is a comment
    return 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'sequence/section label'
}

@test "every slash-marker extension is checked" {
  for ext in go ts tsx js jsx mjs cjs; do
    write_probe "probe.$ext" <<'PROBE'
// Phase 2 warms the cache
PROBE
    run run_hook "$PROBE"
    [ "$status" -eq 2 ] || fail "expected exit 2 for .$ext"$'\n'"$output"
  done
}

@test "every hash-marker extension is checked" {
  for ext in py pyi; do
    write_probe "probe.$ext" <<'PROBE'
# Phase 2 warms the cache
PROBE
    run run_hook "$PROBE"
    [ "$status" -eq 2 ] || fail "expected exit 2 for .$ext"$'\n'"$output"
  done
}

@test "a hash opens no comment in a slash-marker language" {
  write_probe probe.go <<'PROBE'
package p

# Phase 2 warms the cache
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "a slash opens no comment in a hash-marker language" {
  write_probe probe.py <<'PROBE'
x = 1 // 2  // Phase 2 warms the cache
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "an extension the hook does not handle blocks nothing" {
  for name in probe.rb probe.md probe.sh probe; do
    write_probe "$name" <<'PROBE'
# Phase 2 warms the cache
PROBE
    run run_hook "$PROBE"
    [ "$status" -eq 0 ] || fail "expected exit 0 for $name"$'\n'"$output"
    [ -z "$output" ] || fail "expected no output for $name"$'\n'"$output"
  done
}

@test "a clean source file blocks nothing" {
  write_probe probe.go <<'PROBE'
package p

// Warms the cache before the first read.
var x = 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "a violation carries the guidance the agent has to act on" {
  write_probe probe.go <<'PROBE'
package p

// Phase 2 warms the cache
var x = 1
PROBE
  run run_hook "$PROBE"
  [ "$status" -eq 2 ]
  assert_contains "$output" "Comment-style violation in $PROBE"
  assert_contains "$output" 'line 3 [sequence/section label]'
  assert_contains "$output" 'Fix: delete the label/reference token'
  assert_contains "$output" 'Not a violation (do not change)'
}

@test "a host without jq blocks nothing" {
  write_probe probe.go <<'PROBE'
package p

// Phase 2 warms the cache
PROBE
  nojq=$(path_without_jq)
  if env PATH="$nojq" sh -c 'command -v jq' >/dev/null 2>&1; then
    fail "expected no jq on the probe PATH"
  fi
  run env PATH="$nojq" "$HOOK" <<PAYLOAD
{"tool_name":"Edit","tool_input":{"file_path":"$PROBE"}}
PAYLOAD
  assert_clean
}

@test "a payload naming no file blocks nothing" {
  for payload in '{"tool_name":"Edit","tool_input":{}}' \
    '{"tool_name":"Edit","tool_input":{"file_path":""}}' \
    '{}' ''; do
    run run_hook_raw "$payload"
    [ "$status" -eq 0 ] || fail "expected exit 0 for: $payload"$'\n'"$output"
    [ -z "$output" ] || fail "expected no output for: $payload"$'\n'"$output"
  done
}

@test "a payload jq cannot parse blocks nothing" {
  for payload in '{"tool_input":{' 'hello world' '[1,2,3]'; do
    run run_hook_raw "$payload"
    [ "$status" -eq 0 ] || fail "expected exit 0 for: $payload"$'\n'"$output"
    [ -z "$output" ] || fail "expected no output for: $payload"$'\n'"$output"
  done
}

@test "a file that does not exist blocks nothing" {
  run run_hook "$BATS_TEST_TMPDIR/nosuch.go"
  assert_clean
}

@test "Claude settings run the hook after every edit" {
  jq -e '
    .hooks.PostToolUse[] | select(.matcher == "Edit|Write|MultiEdit")
    | .hooks[] | select(.command | endswith("check-comment-style.sh"))
  ' "$ROOT/.claude/settings.json" >/dev/null
}
