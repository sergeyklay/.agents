#!/usr/bin/env python3
"""
Validate a technical specification produced by the writing-specs skill.

Universal, stack-agnostic checks only. The script is a feedback-loop helper,
not a substitute for the manual quality checklist at
references/quality-checklist.md.

Usage:
    validate_spec.py <path-to-spec.md>

Checks (each maps to a class of defect the agent or a reviewer would catch
by hand):
    - File exists and has the .md extension.
    - Filename matches Spec-{slug}.md.
    - All required sections present and non-empty:
        Compliance check, 1. Business goal and value,
        3. Technical architecture, 4. Risk assessment,
        6. File structure summary, 7. Acceptance criteria.
    - Compliance-check table has nine data rows (one per analysis check).
    - Compliance-check table contains no STOP verdicts (a STOP halts
      drafting and MUST NOT appear in a delivered spec).
    - Risk-assessment table has at least one data row.
    - No em-dashes or en-dashes anywhere in the document.
    - No backslash paths inside backtick code spans.
    - No oversized fenced code blocks (heuristic for runnable code rather
      than signature). Default threshold is 80 lines; pass --code-block-limit
      to override.

Exit codes:
    0   no errors (warnings may be present)
    1   at least one error
    2   usage error
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
NEXT_SECTION = re.compile(r"^##\s+", re.MULTILINE)
TABLE_ROW = re.compile(r"^\|(?P<cells>.+)\|\s*$", re.MULTILINE)
SEPARATOR_ROW = re.compile(r"^\|\s*[:\- ]+\s*\|")
FENCED_BLOCK = re.compile(r"^```[^\n]*\n(.*?)^```", re.MULTILINE | re.DOTALL)
BACKSLASH_PATH = re.compile(r"`[^`\n]*\\[A-Za-z][^`\n]*`")


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


def validate(path: Path, code_block_limit: int) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    if not path.exists():
        errors.append(f"File not found: {path}")
        return errors, warnings

    if path.suffix != ".md":
        warnings.append(f"Expected .md extension, got {path.suffix!r}")

    if not FILENAME_PATTERN.match(path.name):
        warnings.append(
            f"Filename {path.name!r} does not match Spec-{{slug}}.md pattern"
        )

    content = path.read_text(encoding="utf-8")

    # Required sections
    for pattern, label in REQUIRED_SECTIONS:
        header_re = re.compile(pattern, re.MULTILINE)
        body = section_body(content, header_re)
        # Strip HTML comments so a section that contains only a comment counts as empty.
        cleaned = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
        if not header_re.search(content):
            errors.append(f"Missing section: {label}")
        elif len(cleaned) < 20:
            errors.append(f"Empty or minimal section: {label}")

    # Compliance-check table: nine data rows, no STOP verdicts.
    compliance_body = section_body(content, COMPLIANCE_HEADER)
    if compliance_body:
        rows = table_data_rows(compliance_body)
        if len(rows) < 9:
            errors.append(
                f"Compliance-check table has {len(rows)} data rows; expected 9 (one per analysis check)"
            )
        for idx, row in enumerate(rows, start=1):
            verdict_cell = row[1] if len(row) >= 2 else ""
            if "STOP" in verdict_cell.upper().split():
                errors.append(
                    f"Compliance-check row {idx} carries a STOP verdict; STOP halts drafting and must be resolved before delivery"
                )

    # Risk-assessment table: at least one data row.
    risk_body = section_body(content, RISK_HEADER)
    if risk_body:
        rows = table_data_rows(risk_body)
        if not rows:
            errors.append("Risk-assessment table has no data rows")

    # Em-dash and en-dash check.
    for m in EM_OR_EN_DASH.finditer(content):
        line_no = content.count("\n", 0, m.start()) + 1
        char_name = "em-dash" if m.group() == "—" else "en-dash"
        errors.append(f"Line {line_no}: contains {char_name}; replace with comma, period, parenthesis, semicolon, or colon")

    # Backslash paths inside inline code spans.
    for m in BACKSLASH_PATH.finditer(content):
        line_no = content.count("\n", 0, m.start()) + 1
        warnings.append(f"Line {line_no}: backslash path in code span: {m.group()!r}; use forward slashes")

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

    return errors, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a writing-specs specification.")
    parser.add_argument("spec_path", help="Path to the specification markdown file.")
    parser.add_argument(
        "--code-block-limit",
        type=int,
        default=80,
        help="Maximum lines per fenced code block before warning (default 80).",
    )
    args = parser.parse_args()

    path = Path(args.spec_path).resolve()
    errors, warnings = validate(path, args.code_block_limit)

    for w in warnings:
        print(f"  [!] {w}")
    for e in errors:
        print(f"  [x] {e}")

    if errors:
        print(f"Validation failed: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1

    print(f"Validation passed ({len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
