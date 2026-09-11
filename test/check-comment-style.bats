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

# A case and the control that makes it a defect differ by one comment, which a
# heredoc cannot vary.
go_comment_probe() {
  PROBE="$BATS_TEST_TMPDIR/probe.go"
  printf 'package p\n\n// %s\nvar x = 1\n' "$1" >"$PROBE"
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

# Lowercase is the spelling AGENTS.md and the rules files use, so a title-case
# pattern misses the shape the guard exists to catch.
@test "the hook rejects a sequence label in any case" {
  for comment in 'Step 2: seed it' 'step 2: seed it' 'STEP 2: seed it' \
    'section 3: the header'; do
    go_comment_probe "$comment"
    run run_hook "$PROBE"
    [ "$status" -eq 2 ] || fail "expected exit 2 for: $comment"$'\n'"$output"
  done
}

@test "the hook keeps the genuinely case-sensitive tokens case-sensitive" {
  for comment in 'pins the ac-1 contract' 'i-1 is a fixture row' \
    'see Docs/Architecture.MD'; do
    go_comment_probe "$comment"
    run run_hook "$PROBE"
    [ "$status" -eq 0 ] || fail "expected exit 0 for: $comment"$'\n'"$output"
    [ -z "$output" ] || fail "expected no output for: $comment"$'\n'"$output"
  done
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

@test "the hook allows an ordered list in a doc comment" {
  write_probe probe.go <<'PROBE'
package p

// 1. warm the cache
// 2. read it back
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

# The contract calls the rule "a section sign followed by a number", and a bare
# substring test rejects the sign used as a word.
@test "the hook allows a section sign carrying no number" {
  go_comment_probe 'section § is reserved'
  run run_hook "$PROBE"
  assert_clean
}

@test "the hook rejects a section sign with or without a space before its number" {
  for comment in 'per § 4' 'per §4'; do
    go_comment_probe "$comment"
    run run_hook "$PROBE"
    assert_flagged 'section-mark reference' || return 1
  done
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

@test "the hook rejects a single-digit issue number" {
  go_comment_probe 'see #7 for the cause'
  run run_hook "$PROBE"
  assert_flagged 'internal issue number'
}

# An issue number never carries a leading zero and never ends in a hex letter,
# which is what separates it from a color the guard must leave alone.
@test "the hook reads no issue number out of a hex color" {
  for comment in 'the color #000000 is the default' \
    'the color #1a2b3c is the default' 'the color #fff is the default'; do
    go_comment_probe "$comment"
    run run_hook "$PROBE"
    [ "$status" -eq 0 ] || fail "expected exit 0 for: $comment"$'\n'"$output"
    [ -z "$output" ] || fail "expected no output for: $comment"$'\n'"$output"
  done
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

# Without the number the three letters are a bypass of every rule in the
# classifier, and three letters is what an author has to type to disarm it.
@test "the hook exempts nothing for an RFC mention carrying no number" {
  for comment in 'Step 2 handles RFC input' 'RFC Step 2: seed it' \
    'RFC: see docs/architecture.md' 'no retry — RFC'; do
    go_comment_probe "$comment"
    run run_hook "$PROBE"
    [ "$status" -eq 2 ] || fail "expected exit 2 for: $comment"$'\n'"$output"
  done
}

# time.RFC3339 is stdlib Go, so the exemption has to need a separator as well
# as a number or ordinary date handling disarms the guard by accident.
@test "an RFC constant inside the comment exempts nothing" {
  go_comment_probe 'Phase 2 stamps it with time.RFC3339'
  run run_hook "$PROBE"
  assert_flagged 'sequence/section label'
}

@test "an RFC mention in a comment does not exempt the code beside it" {
  write_probe probe.go <<'PROBE'
package p

var x = "docs/architecture.md" // RFC note
PROBE
  run run_hook "$PROBE"
  assert_flagged 'spec reference outside a comment'
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

# The control is the same line without the block comment: it was already
# flagged, so what the block changed is the extractor, not the rule.
@test "a closed block comment hides no comment later on its line" {
  for prefix in 'var x = 1 /* fine */ ' 'var x = 1 '; do
    printf 'package p\n\n%s// Phase 2: seed it\n' "$prefix" >"$BATS_TEST_TMPDIR/probe.go"
    run run_hook "$BATS_TEST_TMPDIR/probe.go"
    assert_flagged 'sequence/section label' || return 1
  done
}

@test "a closed block comment hides no code later on its line" {
  for prefix in 'var x = 1 /* fine */ ; ' 'var x = 1 ; '; do
    printf 'package p\n\n%suseTable(%s)\n' "$prefix" '"Table 3.1-B"' \
      >"$BATS_TEST_TMPDIR/probe.go"
    run run_hook "$BATS_TEST_TMPDIR/probe.go"
    assert_flagged 'spec reference outside a comment' || return 1
  done
}

@test "the hook classifies every block comment on a line, not the first" {
  write_probe probe.go <<'PROBE'
package p

var x = 1 /* fine */ /* also fine */ /* Phase 2 */
PROBE
  run run_hook "$PROBE"
  assert_flagged 'sequence/section label'
}

@test "the hook reads no comment out of a block marker inside a string" {
  write_probe probe.go <<'PROBE'
package p

var pat = "/* Step 8: not a comment */"
PROBE
  run run_hook "$PROBE"
  assert_clean
}

# A false positive costs more than a miss: it rejects a write the rules allow
# and the author has no rule to point at.
@test "a Go raw string spanning lines carries no comment" {
  write_probe probe.go <<'PROBE'
package p

var s = `first
// Phase 2 inside a raw string
`
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "a TypeScript template literal spanning lines carries no comment" {
  write_probe probe.ts <<'PROBE'
const s = `first
// Phase 2 inside a template literal
`;
PROBE
  run run_hook "$PROBE"
  assert_clean
}

# The second arm of the false-positive proof: silence on the literal must not
# be silence on the comment that follows it.
@test "a comment after a raw string closes is still read" {
  write_probe probe.go <<'PROBE'
package p

var s = `first
`

// Phase 2 warms the cache
PROBE
  run run_hook "$PROBE"
  assert_flagged 'sequence/section label'
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

@test "a comment after the closing docstring fence is read" {
  write_probe probe.py <<'PROBE'
def f():
    """Notes.

    body
    """  # Phase 2 warms the cache
    return 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'sequence/section label'
}

@test "a comment after a one-line docstring is read" {
  write_probe probe.py <<'PROBE'
def f():
    """Summary."""  # Phase 2 warms the cache
    return 1
PROBE
  run run_hook "$PROBE"
  assert_flagged 'sequence/section label'
}

# The control for the two above: on the opening fence the hash is still inside
# the docstring, so the fence decides, not the count of quotes on the line.
@test "a hash on the docstring opening line stays inside the docstring" {
  write_probe probe.py <<'PROBE'
def f():
    """Notes.  # Phase 2 is not a comment

    body
    """
    return 1
PROBE
  run run_hook "$PROBE"
  assert_clean
}

@test "a triple quote inside a string opens no docstring" {
  for first in "value = '\"\"\"'" "value = 'x'"; do
    printf '%s\n# Phase 2 warms the cache\n' "$first" >"$BATS_TEST_TMPDIR/probe.py"
    run run_hook "$BATS_TEST_TMPDIR/probe.py"
    assert_flagged 'sequence/section label' || return 1
  done
}

@test "a triple quote inside a comment opens no docstring" {
  for first in '# mention """' '# mention'; do
    printf '%s\n# Phase 2 warms the cache\n' "$first" >"$BATS_TEST_TMPDIR/probe.py"
    run run_hook "$BATS_TEST_TMPDIR/probe.py"
    assert_flagged 'sequence/section label' || return 1
  done
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
  for ext in py pyi bats bash sh; do
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
  for name in probe.rb probe.md probe; do
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

# The guard and the suites that probe it are written out of the patterns it
# forbids, so a report on them is noise that teaches the reader to skip the next
# one.
@test "the hook is silent on the guard and on the suites that probe it" {
  for path in "$ROOT/.claude/hooks/check-comment-style.sh" \
    "$ROOT/test/check-comment-style.bats" "$ROOT/test/comment-style.bats"; do
    run run_hook "$path"
    [ "$status" -eq 0 ] || fail "expected exit 0 for $path"$'\n'"$output"
    [ -z "$output" ] || fail "expected no output for $path"$'\n'"$output"
  done
}

# A basename the exemption does not name has to stay guarded, or the carve-out
# is a directory exemption wearing a filename.
@test "the exemption reaches the guard family and nothing beside it" {
  for name in check-comment-style.sh check-comment-style.bats comment-style.bats; do
    write_probe "$name" <<'PROBE'
# Phase 2 warms the cache
PROBE
    run run_hook "$PROBE"
    [ "$status" -eq 0 ] || fail "expected exit 0 for $name"$'\n'"$output"
    [ -z "$output" ] || fail "expected no output for $name"$'\n'"$output"
  done

  for name in my-check-comment-style.sh check-comment-style.py comment-style.sh; do
    write_probe "$name" <<'PROBE'
# Phase 2 warms the cache
PROBE
    run run_hook "$PROBE"
    [ "$status" -eq 2 ] || fail "expected exit 2 for $name"$'\n'"$output"
  done
}

# Every case above runs the hook out of the working tree, which says nothing
# about what a host ends up with.
@test "the installer ships the hook and the settings that run it" {
  run install_into --hooks --settings --claude
  [ "$status" -eq 0 ] || fail "installer exited $status"$'\n'"$output"

  installed="$TEST_HOME/.claude/hooks/check-comment-style.sh"
  assert_file "$installed"
  [ -x "$installed" ] || fail "expected the installed hook to be executable"
  jq -e '
    .hooks.PostToolUse[] | select(.matcher == "Edit|Write|MultiEdit")
    | .hooks[] | select(.command | endswith("check-comment-style.sh"))
  ' "$TEST_HOME/.claude/settings.json" >/dev/null

  write_probe probe.go <<'PROBE'
package p

// Phase 2 warms the cache
var x = 1
PROBE
  run "$installed" <<PAYLOAD
{"tool_name":"Edit","tool_input":{"file_path":"$PROBE"}}
PAYLOAD
  assert_flagged 'sequence/section label'
}
