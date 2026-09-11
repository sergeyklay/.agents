#!/bin/sh

# PostToolUse guard wired to Edit|Write|MultiEdit in .claude/settings.json. The
# stderr block at the bottom names every rule and exemption, so the agent that
# trips the guard can act without reading this file.

set -eu

# Fail open. A missing jq, an unreadable file or malformed hook JSON leaves no
# decision to make, and blocking there would cost more than a missed violation.
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat) || exit 0
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

[ -n "$file" ] || exit 0
case "$file" in
*.go | *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs) marker='//' ;;
*.py | *.pyi) marker='#' ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

violations=$(awk -v marker="$marker" '
# No apostrophe may appear in this awk source. It lives in a single-quoted shell
# string, and one apostrophe would end that string and silently void the guard.
BEGIN {
  SQ = sprintf("%c", 39)
  FENCE_DOUBLE = "\"\"\""
  FENCE_SINGLE = SQ SQ SQ
  QUOTES = "\"" SQ
  if (marker == "//") QUOTES = QUOTES "`"

  SEQ_LABEL = "(^|[^[:alnum:]])(step|phase|check|rule|section|part|case|pass|stage|round|scenario)[[:space:]]+[0-9]"
  SPEC_NOUN = "(^|[^[:alnum:]])(Table|Tables|Appendix|Figure|Diagram|Criterion|Criteria|Requirement|Spec)[-[:space:]]+[0-9]"
  DOC_REF   = "(docs/architecture|docs/decisions|architecture\\.md|architecture-digest|\\.specs/|\\.plans/|ADR-?[0-9])"
  SPEC_PREFIX = "(^|[^[:alnum:]])(AC|FR|NFR|REQ|US)-[0-9]"

  # Only I, U and Q. Every other single letter is fixture issue data here, and
  # no pattern separates C-1 the fixture row from C-1 the spec citation.
  TEST_TYPE = "(^|[^[:alnum:]])(I|U|Q)-[0-9]"

  # Three frame characters, spelled out rather than written as an interval so
  # BSD awk applies it too. Two would catch the prose "// == false, ..." and the
  # flag "--no-ask-user".
  FRAME = "^[[:space:]]*[-=*#~_+][-=*#~_+][-=*#~_+]"

  PREFORMATTED     = "^\t"
  EDITOR_DIRECTIVE = "^[[:space:]]*-\\*-.*-\\*-"
  BOX_BORDER       = "^[[:space:]]*\\+-+\\+"

  # The separator before the number keeps time.RFC3339 out of the exemption.
  RFC_CITATION = "(^|[^[:alnum:]])RFC[[:space:]-]+[0-9]"

  # A leading zero or a trailing hex letter marks a color, not an issue number.
  ISSUE_REF = "(^|[^[:alnum:]_./-])#[1-9][0-9]*($|[^0-9a-fA-F])"

  # A byte literal, so the match holds under any locale.
  EM_DASH      = "—"
  SECTION_MARK = "§[[:space:]]*[0-9]"
}
{
  scan($0)
  for (i = 1; i <= comment_count; i++) {
    kind = classify(comment_text[i])
    if (kind != "") { report(kind); next }
  }

  # A test name or an assertion message carries a spec reference into CI output.
  if (code ~ SPEC_NOUN || code ~ DOC_REF) report("spec reference outside a comment")
}

# A block comment, a backtick string and a docstring fence stay open into the
# next record; a plain quote closes at the end of its own.
function scan(s,   i, n, ch, three) {
  comment_count = 0
  code = ""
  i = 1
  n = length(s)
  while (i <= n) {
    if (open_span != "") { i = close_span(s, i); continue }
    ch = substr(s, i, 1)
    three = substr(s, i, 3)
    if (marker == "#" && (three == FENCE_DOUBLE || three == FENCE_SINGLE)) {
      open_span = three
      span_kind = "prose"
      i += 3
    } else if (substr(s, i, length(marker)) == marker) {
      add_comment(substr(s, i + length(marker)))
      i = n + 1
    } else if (marker == "//" && substr(s, i, 2) == "/*") {
      open_span = "*/"
      span_kind = "comment"
      i += 2
    } else if (index(QUOTES, ch) > 0) {
      open_span = ch
      span_kind = "code"
      code = code ch
      i++
    } else {
      code = code ch
      i++
    }
  }
  if (open_span == "\"" || open_span == SQ) open_span = ""
}

function close_span(s, from,   at, width) {
  width = length(open_span)
  at = span_end(s, from, open_span)
  collect(at > 0 ? substr(s, from, at - from) : substr(s, from), from == 1)
  if (at == 0) return length(s) + 1
  if (span_kind == "code") code = code open_span
  open_span = ""
  return at + width
}

function collect(text, block_continuation) {
  if (span_kind == "comment") {
    if (block_continuation) sub(/^[[:space:]]*\*/, "", text)
    add_comment(text)
  } else if (span_kind == "code") {
    code = code text
  }
}

function add_comment(text) { comment_text[++comment_count] = text }

# A backslash escapes the next character inside a quote, never inside a comment.
function span_end(s, from, delim,   i, last, width) {
  width = length(delim)
  last = length(s) - width + 1
  for (i = from; i <= last; i++) {
    if (delim != "*/" && substr(s, i, 1) == "\\") { i++; continue }
    if (substr(s, i, width) == delim) return i
  }
  return 0
}

function report(kind) { printf("  line %d [%s]: %s\n", NR, kind, $0) }

function classify(c) {
  if (c ~ RFC_CITATION) return ""
  if (tolower(c) ~ SEQ_LABEL) return "sequence/section label"
  if (c ~ SPEC_NOUN) return "spec-criteria reference"
  if (c ~ SPEC_PREFIX) return "spec-criteria reference"
  if (c ~ TEST_TYPE) return "test-type reference"
  if (c ~ DOC_REF) return "internal doc/ADR reference"
  if (c ~ FRAME && c !~ PREFORMATTED && c !~ EDITOR_DIRECTIVE && c !~ BOX_BORDER) return "banner decoration"
  if (index(c, EM_DASH) > 0) return "em-dash"
  if (c ~ SECTION_MARK) return "section-mark reference"
  if (c ~ ISSUE_REF) return "internal issue number"
  return ""
}
' "$file") || exit 0

[ -n "$violations" ] || exit 0

{
  echo "Comment-style violation in $file"
  echo
  echo "$violations"
  echo
  echo "This project forbids these in comments, doc comments included, because they"
  echo "rot, renumber, and point at documents that move or do not exist in the tree:"
  echo "  - sequence/section labels: Step N, Phase N, Check N, Case N, Section N.N"
  echo "                             (in any case: step 2, STEP 2, Step 2)"
  echo "  - spec-criteria refs:      AC-7, FR-1, NFR-2, REQ-3, US-4"
  echo "  - test-type refs:          I-1, U-1, Q-1"
  echo "  - spec artefact + number:  Table 3.1-B, Table-3, Appendix 2, Figure 4, Spec-706"
  echo "                             (these are flagged in string literals too)"
  echo "  - internal doc/ADR refs:   docs/architecture.md, docs/decisions/, ADR-3, .specs/, .plans/"
  echo "  - section-mark refs:       a section sign followed by a number"
  echo "  - internal issue numbers:  see #7, see #811"
  echo
  echo "It also forbids two decorations that carry no information for the reader:"
  echo "  - banner/frame comments:   --- Tests ---, ======, #####"
  echo "  - em-dashes in prose:      they read as machine-written"
  echo
  echo "Fix: delete the label/reference token and keep the plain-language reason."
  echo "  'Step 2: seed the store'     -> 'Seed the store'"
  echo "  'pins the AC-1 contract'     -> 'pins the success-envelope contract'"
  echo "  'I-1: decisive match wins'   -> 'a decisive match wins'"
  echo "  'a Table 3.1-B value ...'    -> 'a documented blocking value ...'"
  echo "  '--- Test helpers ---'       -> delete the line; the declaration names itself"
  echo "  'no retry - the slot is hot' -> use a comma, a semicolon, or two sentences"
  echo
  echo "Not a violation (do not change): test-data IDs in strings (\"PROJ-42\") or in"
  echo "comments (\"C-1\", \"D-1\"), standard tokens (ISO-8601, UTF-8, SHA-256), ordered"
  echo "lists in a doc comment, a \"---\" inside a preformatted block, upstream issue"
  echo "refs carrying an owner/repo prefix (golang/go#22315), a hex color (#000000),"
  echo "an upstream RFC citation carrying a number (\"RFC 7231 Section 6\", but not a"
  echo "bare \"RFC\" and not time.RFC3339), and a spaced en-dash, which is the"
  echo "sanctioned replacement for an em-dash."
} >&2
exit 2
