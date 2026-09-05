#!/usr/bin/env python3
"""Validate a technical specification produced by the writing-specs skill.

Usage:
    validate_spec.py <path-to-spec.md>

Errors are structural (missing section, undelivered STOP, banned character) and
exit 1. Budgets are warnings and never fail the run: gating on size halts specs
that are correct but long, and teaches the agent to rename headings rather than
write less. Every budget has a --flag; see --help.

Exit codes: 0 no structural errors, 1 structural errors, 2 usage error.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REQUIRED_SECTIONS: list[tuple[str, str]] = [
    (r"^##\s+Compliance check\s*$", "Compliance check"),
    (r"^##\s+1\.\s+Business goal and value\s*$", "1. Business goal and value"),
    (r"^##\s+3\.\s+Technical architecture\s*$", "3. Technical architecture"),
    (r"^##\s+4\.\s+Risk assessment\s*$", "4. Risk assessment"),
    (r"^##\s+6\.\s+File structure summary\s*$", "6. File structure summary"),
    (r"^##\s+7\.\s+Acceptance criteria\s*$", "7. Acceptance criteria"),
]

EM_OR_EN_DASH = re.compile(r"[–—]")
FILENAME_PATTERN = re.compile(r"^Spec-[\w.\-]+\.md$")
COMPLIANCE_HEADER = re.compile(r"^##\s+Compliance check\s*$", re.MULTILINE)
RISK_HEADER = re.compile(r"^##\s+4\.\s+Risk assessment\s*$", re.MULTILINE)
QUESTIONS_HEADER = re.compile(r"^##\s+5\.\s+Open questions\s*$", re.MULTILINE)
FILE_SUMMARY_HEADER = re.compile(
    r"^##\s+6\.\s+File structure summary\s*$", re.MULTILINE
)
NEXT_SECTION = re.compile(r"^##\s+", re.MULTILINE)
TABLE_ROW = re.compile(r"^\|(?P<cells>.+)\|\s*$", re.MULTILINE)
SEPARATOR_ROW = re.compile(r"^\|\s*[:\- ]+\s*\|")
FENCED_BLOCK = re.compile(r"^```[^\n]*\n(.*?)^```", re.MULTILINE | re.DOTALL)
BACKSLASH_PATH = re.compile(r"`[^`\n]*\\[A-Za-z][^`\n]*`")
CODE_SPAN = re.compile(r"`[^`\n]*`")
# Freehand prose: match the claim, not one phrasing.
COMPLIANCE_ALL_GO = re.compile(
    r"all\s+(?:nine\s+|9\s+)?checks?\b[^.\n]*\b(?:GO|passed|pass|clear)\b",
    re.IGNORECASE,
)
COMPLIANCE_FLAG_LINE = re.compile(r"(?m)^\s*(?:[-*]\s*)?(?:\*\*)?FLAG\b")
COMPLIANCE_PREREQ_LINE = re.compile(r"(?m)^\s*(?:[-*]\s*)?(?:\*\*)?Prerequisites\b")
COMPLIANCE_STOP_LINE = re.compile(r"(?m)^\s*(?:[-*]\s*)?(?:\*\*)?STOP\b")
# Bold marker is optional; a mandatory asterisk made the heading and bullet
# branches unreachable and missed the dominant "OQ-N" convention.
QUESTION_LABEL = re.compile(
    r"(?im)^\s*(?:#{2,4}\s+|[-*]\s+)?(?:\*\*|__)?"
    r"(?:O?Q[-.\s]?\d+|(?:open\s+)?questions?\s+\d+)\b"
)


def section_body(content: str, header_re: re.Pattern[str]) -> str:
    """Return the text between header_re's match and the next H2, or end."""
    m = header_re.search(content)
    if not m:
        return ""
    start = m.end()
    nxt = NEXT_SECTION.search(content, pos=start)
    end = nxt.start() if nxt else len(content)
    return content[start:end]


def table_data_rows(section: str) -> list[list[str]]:
    """Return cell lists for every non-header, non-separator pipe row."""
    rows: list[list[str]] = []
    saw_separator = False
    for line in section.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            # Reset: without it a second table's header counts as data.
            saw_separator = False
            continue
        if SEPARATOR_ROW.match(stripped):
            saw_separator = True
            continue
        if not saw_separator:
            # Header row before the separator. Skip.
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        rows.append(cells)
    return rows


def words_outside_listing(section: str) -> int:
    """Count prose outside fenced blocks and table rows; both are listings."""
    stripped = FENCED_BLOCK.sub(" ", section)
    lines = [ln for ln in stripped.splitlines() if not ln.strip().startswith("|")]
    return len("\n".join(lines).split())


def validate(
    path: Path,
    code_block_limit: int,
    questions_word_limit: int,
    file_summary_prose_limit: int,
    questions_max: int,
    risk_max_rows: int,
    document_word_limit: int,
) -> tuple[list[str], list[str], dict[str, int]]:
    errors: list[str] = []
    warnings: list[str] = []
    metrics: dict[str, int] = {}

    if not path.exists():
        errors.append(f"File not found: {path}")
        return errors, warnings, metrics

    if path.suffix != ".md":
        warnings.append(f"Expected .md extension, got {path.suffix!r}")

    if not FILENAME_PATTERN.match(path.name):
        warnings.append(
            f"Filename {path.name!r} does not match Spec-{{slug}}.md pattern"
        )

    content = path.read_text(encoding="utf-8")

    document_words = len(content.split())
    metrics["document_words"] = document_words
    if document_words > document_word_limit:
        warnings.append(
            f"Document is {document_words} words (budget {document_word_limit}); "
            "if it covers more than one independently shippable goal, split it "
            "and respecify the narrowed scope rather than compressing prose"
        )

    # Required sections
    for pattern, label in REQUIRED_SECTIONS:
        header_re = re.compile(pattern, re.MULTILINE)
        body = section_body(content, header_re)
        # Strip HTML comments so a section that contains only a comment counts as empty.
        cleaned = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
        if not header_re.search(content):
            errors.append(f"Missing section: {label}")
        elif len(cleaned) < 20 and label != "Compliance check":
            errors.append(f"Empty or minimal section: {label}")

    # Exception format, or the legacy nine-row table for older specs.
    # Gate on the header, not on the body: the header pattern's trailing \s*
    # consumes the newline, so a section holding only whitespace yields an
    # empty body and would otherwise skip every verdict check below.
    compliance_body = section_body(content, COMPLIANCE_HEADER)
    if COMPLIANCE_HEADER.search(content):
        rows = table_data_rows(compliance_body)
        if rows:
            if len(rows) < 9:
                errors.append(
                    f"Compliance-check table has {len(rows)} data rows; expected 9 "
                    "(one per analysis check) or use the exception format instead"
                )
            for idx, row in enumerate(rows, start=1):
                verdict_cell = row[1] if len(row) >= 2 else ""
                if "STOP" in verdict_cell.upper().split():
                    errors.append(
                        f"Compliance-check row {idx} carries a STOP verdict; STOP halts "
                        "drafting and must be resolved before delivery"
                    )
        else:
            # Strip code spans first: the template quotes the verdict as an
            # example, a filled spec asserts it. Without this a spec that kept
            # the template's instructions and recorded nothing still passes.
            asserted = CODE_SPAN.sub(" ", compliance_body)
            if not (
                COMPLIANCE_ALL_GO.search(asserted)
                or COMPLIANCE_FLAG_LINE.search(asserted)
                or COMPLIANCE_PREREQ_LINE.search(asserted)
            ):
                errors.append(
                    "Compliance check does not record the analysis verdict: add "
                    '"All nine checks: GO.", one FLAG bullet per flagged check, '
                    "or the Prerequisites bullet"
                )
        if COMPLIANCE_STOP_LINE.search(compliance_body):
            errors.append(
                "Compliance check carries a STOP verdict; STOP halts drafting "
                "and must be resolved before delivery"
            )

    risk_body = section_body(content, RISK_HEADER)
    if risk_body:
        rows = table_data_rows(risk_body)
        metrics["risk_rows"] = len(rows)
        if not rows:
            errors.append("Risk-assessment table has no data rows")
        elif len(rows) > risk_max_rows:
            warnings.append(
                f"Risk-assessment table has {len(rows)} data rows (budget "
                f"{risk_max_rows}); keep the risks that name an observable failure "
                "and move design consequences into section 3"
            )

    questions_body = section_body(content, QUESTIONS_HEADER)
    if questions_body:
        count = len(questions_body.split())
        metrics["questions_words"] = count
        if count > questions_word_limit:
            warnings.append(
                f"Section 5 is {count} words (budget {questions_word_limit}); keep each "
                "question to the template's four bullets and drop option catalogues"
            )
        labeled = len(QUESTION_LABEL.findall(questions_body))
        metrics["questions"] = labeled
        if labeled > questions_max:
            warnings.append(
                f"Section 5 lists {labeled} questions (budget {questions_max}); a question "
                "resolved with a recommendation is a decision and belongs in section 3"
            )

    summary_body = section_body(content, FILE_SUMMARY_HEADER)
    if summary_body:
        prose = words_outside_listing(summary_body)
        metrics["file_summary_prose_words"] = prose
        if prose > file_summary_prose_limit:
            warnings.append(
                f"Section 6 carries {prose} words of prose around the file listing "
                f"(budget {file_summary_prose_limit}); annotate entries inside the tree "
                "rather than restating section 3"
            )

    # Em-dash and en-dash check.
    for m in EM_OR_EN_DASH.finditer(content):
        line_no = content.count("\n", 0, m.start()) + 1
        char_name = "em-dash" if m.group() == "—" else "en-dash"
        errors.append(
            f"Line {line_no}: contains {char_name}; replace with comma, period, parenthesis, semicolon, or colon"
        )

    # Backslash paths inside inline code spans.
    for m in BACKSLASH_PATH.finditer(content):
        line_no = content.count("\n", 0, m.start()) + 1
        warnings.append(
            f"Line {line_no}: backslash path in code span: {m.group()!r}; use forward slashes"
        )

    # Oversized fenced code blocks (heuristic for implementation rather than signature).
    for m in FENCED_BLOCK.finditer(content):
        block_body = m.group(1)
        lines = block_body.count("\n")
        if lines > code_block_limit:
            line_no = content.count("\n", 0, m.start()) + 1
            warnings.append(
                f"Line {line_no}: fenced code block is {lines} lines (limit {code_block_limit}); "
                "verify the block is signature, schema, or pseudo-code, not implementation"
            )

    return errors, warnings, metrics


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a writing-specs specification."
    )
    parser.add_argument("spec_path", help="Path to the specification markdown file.")
    parser.add_argument(
        "--code-block-limit",
        type=int,
        default=80,
        help="Maximum lines per fenced code block before warning (default 80).",
    )
    parser.add_argument(
        "--questions-word-limit",
        type=int,
        default=400,
        help="Maximum words in section 5, Open questions (default 400).",
    )
    parser.add_argument(
        "--file-summary-prose-limit",
        type=int,
        default=80,
        help="Maximum words of prose around the file listing in section 6 (default 80).",
    )
    parser.add_argument(
        "--questions-max",
        type=int,
        default=5,
        help="Maximum labeled questions in section 5, Open questions (default 5).",
    )
    parser.add_argument(
        "--risk-max-rows",
        type=int,
        default=8,
        help="Maximum data rows in the risk-assessment table (default 8).",
    )
    parser.add_argument(
        "--document-word-limit",
        type=int,
        default=7000,
        help="Word budget for the whole specification (default 7000).",
    )
    args = parser.parse_args()

    path = Path(args.spec_path).resolve()
    errors, warnings, metrics = validate(
        path,
        args.code_block_limit,
        args.questions_word_limit,
        args.file_summary_prose_limit,
        args.questions_max,
        args.risk_max_rows,
        args.document_word_limit,
    )

    if metrics:
        measured = ", ".join(f"{k}={v}" for k, v in sorted(metrics.items()))
        print(f"  [i] {measured}")
    for w in warnings:
        print(f"  [!] {w}")
    for e in errors:
        print(f"  [x] {e}")

    if errors:
        print("VALIDATION_RESULT=FAIL")
        print(
            f"Validation failed: {len(errors)} error(s), "
            f"{len(warnings)} warning(s); fix all errors in one pass, "
            "then re-run once"
        )
        return 1

    print("VALIDATION_RESULT=PASS")
    print(f"Validation passed ({len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
