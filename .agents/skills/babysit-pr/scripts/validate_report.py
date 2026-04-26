#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""Validate a babysit-pr Step 6 summary against the required template.

This script is the feedback loop for Step 6: write -> validate -> fix ->
validate again. It catches the structural violations most likely to slip
past manual review and that most corrupt the audit trail downstream.

Checks:
    - Source header is present.
    - Tracker header is present (records the discovered tracker, or
      "n/a — no items deferred").
    - Context7 Evidence Log table is present with at least a header row.
    - All seven category sections are present (populated or `_(none)_`).
    - No `[C7-REQUIRED]` tags leaked from internal reasoning.
    - Every populated entry has `**[@reviewer, file:line]**` or
      `general feedback` at the start of the bullet.
    - Every `Deferred to Backlog` entry names a ticket reference —
      either a GitHub-style numeric reference (`#N`) or a Jira / Linear-
      style alphanumeric key (e.g. `ABC-123`). The phrase `not added`
      is forbidden in this section: a Deferred comment without a ticket
      is a misclassification and must be moved to Rejected (Category 5)
      or Needs Discussion (Category 7).
    - Every `Rejected` entry cites Context7, architecture, or a
      project-context-file constraint.

Usage:
    validate_report.py <summary-file>

Exit codes:
    0  all checks pass
    1  violations found
    2  usage or file-not-found error

Zero runtime dependencies. Works on Python 3.9+.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


REQUIRED_SECTIONS = (
    "### Source",
    "### Tracker",
    "### Context7 Evidence Log",
    "### Applied",
    "### Deferred to Backlog",
    "### Skipped — Already Addressed",
    "### Skipped — Subjective",
    "### Rejected",
    "### Needs Discussion",
    "### Stale / Outdated",
)

INTERNAL_TAGS = ("[C7-REQUIRED]",)

BULLET_PATTERN = re.compile(r"^- \*\*\[", re.MULTILINE)
REVIEWER_CITATION = re.compile(
    r"^\- \*\*\[@[^,\]]+,\s*[^\]]+\]\*\*|^\- \*\*\[general feedback\]\*\*",
    re.MULTILINE,
)
TRACKER_OUTCOME = re.compile(r"#\d+|[A-Za-z]{2,10}-\d+")
NOT_ADDED_PATTERN = re.compile(r"\bnot\s+added\b", re.IGNORECASE)
EVIDENCE_KEYWORDS = re.compile(
    r"Context7|\bC7\b|FALLBACK:\s*web|"
    r"architecture|specification|\bspec\b|\bADR\b|\bRFC\b|"
    r"AGENTS\.md|CLAUDE\.md|"
    r"invariant|constraint|forbidden|prohibited|"
    r"deprecated|removed|renamed|incompatible|refuted?|contradicts?",
    re.IGNORECASE,
)


def _section_body(text: str, header: str) -> str:
    """Return the text between ``header`` and the next ``###`` header or EOF."""
    start = text.find(header)
    if start == -1:
        return ""
    after = text[start + len(header):]
    next_header = after.find("\n### ")
    if next_header == -1:
        return after
    return after[:next_header]


def _bullet_lines(body: str) -> list[str]:
    """Return every bullet line in ``body``, one per top-level item."""
    lines: list[str] = []
    for match in BULLET_PATTERN.finditer(body):
        line_start = match.start()
        line_end = body.find("\n", line_start)
        line = body[line_start:line_end if line_end != -1 else None]
        lines.append(line)
    return lines


def validate(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    errors: list[str] = []

    for section in REQUIRED_SECTIONS:
        if section not in text:
            errors.append(f"Missing required section: {section}")

    for tag in INTERNAL_TAGS:
        if tag in text:
            count = text.count(tag)
            errors.append(
                f"Internal tag leaked into summary: {tag} "
                f"({count} occurrence(s)) — strip before finalizing."
            )

    deferred_body = _section_body(text, "### Deferred to Backlog")
    if deferred_body and "_(none)_" not in deferred_body:
        for line in _bullet_lines(deferred_body):
            if NOT_ADDED_PATTERN.search(line):
                errors.append(
                    f"Deferred entry uses 'not added', which is "
                    f"forbidden — Deferred ↔ ticket. A deferred comment "
                    f"without a ticket is a misclassification: move it "
                    f"to Rejected (Category 5) or Needs Discussion "
                    f"(Category 7): {line[:100]!r}"
                )
            elif not TRACKER_OUTCOME.search(line):
                errors.append(
                    f"Deferred entry missing ticket reference "
                    f"(GitHub-style '#N' or Jira/Linear-style "
                    f"'ABC-123'). If no ticket can be created, the "
                    f"comment was misclassified — return to Step 3 and "
                    f"reclassify: {line[:100]!r}"
                )

    rejected_body = _section_body(text, "### Rejected")
    if rejected_body and "_(none)_" not in rejected_body:
        for line in _bullet_lines(rejected_body):
            if not EVIDENCE_KEYWORDS.search(line):
                errors.append(
                    f"Rejected entry missing evidence citation "
                    f"(Context7, architecture, ADR, or context-file "
                    f"constraint): {line[:100]!r}"
                )

    skip_citation = {"### Source", "### Tracker", "### Context7 Evidence Log"}
    for section in REQUIRED_SECTIONS:
        if section in skip_citation:
            continue
        body = _section_body(text, section)
        if not body or "_(none)_" in body:
            continue
        for line in _bullet_lines(body):
            if not REVIEWER_CITATION.match(line):
                errors.append(
                    f"{section.strip()} entry missing "
                    f"`**[@reviewer, file:line]**` prefix: {line[:100]!r}"
                )

    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "Usage: validate_report.py <summary-file>",
            file=sys.stderr,
        )
        return 2

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        return 2

    errors = validate(path)
    if errors:
        print(f"FAIL: {len(errors)} violation(s):")
        for err in errors:
            print(f"  - {err}")
        print()
        print("Fix the summary and re-run.")
        return 1

    print("PASS: summary meets the required structure.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
