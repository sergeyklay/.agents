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
  SEQ_LABEL = "(^|[^[:alnum:]])(Step|Phase|Check|Rule|Section|Part|Case|Pass|Stage|Round|Scenario)[[:space:]]+[0-9]"
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

  SQ = sprintf("%c", 39)
  DOCSTRING_FENCE = "\"\"\"|" SQ SQ SQ

  # Behind an owner/repo prefix the number is upstream, which the rules allow.
  ISSUE_REF = "(^|[^[:alnum:]_./-])#[0-9][0-9]+"

  # Byte literals, so the match holds under any locale.
  EM_DASH      = "—"
  SECTION_MARK = "§"
}
{
  if ($0 ~ /RFC/) next                 # an upstream RFC citation is allowed

  # A hash inside a docstring is prose, and the per-line quote scan below cannot
  # see an enclosing fence opened on an earlier line. Track the fence instead.
  if (marker == "#") {
    fenced = $0
    opened_inside = in_docstring
    if (gsub(DOCSTRING_FENCE, "&", fenced) % 2 == 1) in_docstring = !in_docstring
    if (opened_inside) next
  }

  code = $0
  content = ""

  if (in_block) {
    stop = index($0, "*/")
    content = stop > 0 ? substr($0, 1, stop - 1) : $0
    code = stop > 0 ? substr($0, stop + 2) : ""
    if (stop > 0) in_block = 0
    sub(/^[[:space:]]*\*/, "", content)
  } else {
    line_at = marker_outside_quotes($0, marker)
    block_at = marker == "//" ? marker_outside_quotes($0, "/*") : 0

    if (block_at > 0 && (line_at == 0 || block_at < line_at)) {
      stop = index(substr($0, block_at), "*/")
      content = stop > 0 ? substr($0, block_at + 2, stop - 3) : substr($0, block_at + 2)
      code = substr($0, 1, block_at - 1)
      if (stop == 0) in_block = 1
    } else if (line_at > 0) {
      content = substr($0, line_at + length(marker))
      code = substr($0, 1, line_at - 1)
    }
  }

  if (content != "") {
    kind = classify(content)
    if (kind != "") { report(kind); next }
  }

  # A test name or an assertion message carries a spec reference into CI output.
  if (code ~ SPEC_NOUN || code ~ DOC_REF) report("spec reference outside a comment")
}

function marker_outside_quotes(s, m,   i, last, ch, quote, escaped) {
  last = length(s) - length(m) + 1
  quote = ""
  escaped = 0
  for (i = 1; i <= length(s); i++) {
    ch = substr(s, i, 1)
    if (escaped) { escaped = 0; continue }
    if (ch == "\\") { escaped = 1; continue }
    if (quote != "") { if (ch == quote) quote = ""; continue }
    if (ch == "\"" || ch == "\047" || ch == "`") { quote = ch; continue }
    if (i <= last && substr(s, i, length(m)) == m) return i
  }
  return 0
}

function report(kind) { printf("  line %d [%s]: %s\n", NR, kind, $0) }

function classify(c) {
  if (c ~ SEQ_LABEL) return "sequence/section label"
  if (c ~ SPEC_NOUN) return "spec-criteria reference"
  if (c ~ SPEC_PREFIX) return "spec-criteria reference"
  if (c ~ TEST_TYPE) return "test-type reference"
  if (c ~ DOC_REF) return "internal doc/ADR reference"
  if (c ~ FRAME && c !~ PREFORMATTED && c !~ EDITOR_DIRECTIVE && c !~ BOX_BORDER) return "banner decoration"
  if (index(c, EM_DASH) > 0) return "em-dash"
  if (index(c, SECTION_MARK) > 0) return "section-mark reference"
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
  echo "  - spec-criteria refs:      AC-7, FR-1, NFR-2, REQ-3, US-4"
  echo "  - test-type refs:          I-1, U-1, Q-1"
  echo "  - spec artefact + number:  Table 3.1-B, Table-3, Appendix 2, Figure 4, Spec-706"
  echo "                             (these are flagged in string literals too)"
  echo "  - internal doc/ADR refs:   docs/architecture.md, docs/decisions/, ADR-3, .specs/, .plans/"
  echo "  - section-mark refs:       a section sign followed by a number"
  echo "  - internal issue numbers:  see #811"
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
  echo "refs carrying an owner/repo prefix (golang/go#22315), and a spaced en-dash,"
  echo "which is the sanctioned replacement for an em-dash."
} >&2
exit 2
