#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""
Validate Jira wiki markup syntax.

Checks files for common Markdown-in-Jira mistakes (headings, bold, code
fences, links, bullets) and structural problems (unclosed block macros,
code blocks without a language identifier, tables missing a header row).

Usage:
    validate_jira_syntax.py <file> [<file> ...]

Exit codes:
    0  validation passed (warnings are allowed)
    1  one or more errors found
    2  usage error or unreadable input

Zero runtime dependencies. Works on Python 3.9+.

Coloured output is emitted only when stdout is a TTY and the ``NO_COLOR``
environment variable is unset; ``--color`` and ``--no-color`` override
this detection.
"""

from __future__ import annotations

import argparse
import enum
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Sequence


# --- Issue model ---------------------------------------------------------------


class Severity(enum.Enum):
    ERROR = "ERROR"
    WARN = "WARN"
    OK = "OK"


@dataclass(frozen=True)
class LineMatch:
    line: int
    text: str


@dataclass(frozen=True)
class Issue:
    severity: Severity
    message: str
    matches: tuple[LineMatch, ...] = field(default_factory=tuple)


# --- ANSI rendering ------------------------------------------------------------

_ANSI_BY_SEVERITY: dict[Severity, str] = {
    Severity.ERROR: "\033[0;31m",
    Severity.WARN: "\033[1;33m",
    Severity.OK: "\033[0;32m",
}
_ANSI_RESET = "\033[0m"


def _paint(use_color: bool, severity: Severity, label: str) -> str:
    if not use_color:
        return label
    return f"{_ANSI_BY_SEVERITY[severity]}{label}{_ANSI_RESET}"


# --- Patterns ------------------------------------------------------------------

# Line-anchored patterns (used with re.MULTILINE).
RE_MD_HEADING = re.compile(r"^##+ ", re.MULTILINE)
RE_MD_FENCE = re.compile(r"^```", re.MULTILINE)
RE_MD_BULLET = re.compile(r"^- [^-]", re.MULTILINE)
RE_JIRA_HEADING_NO_SPACE = re.compile(r"^h[1-6]\.[^ ]", re.MULTILINE)
RE_JIRA_HEADING_OK = re.compile(r"^h[1-6]\. ", re.MULTILINE)
RE_TABLE_DATA_ROW = re.compile(r"^\|(?!\|)", re.MULTILINE)
RE_TABLE_HEADER_ROW = re.compile(r"^\|\|", re.MULTILINE)
RE_CODE_OPENING_BARE = re.compile(r"^\{code\}$", re.MULTILINE)
RE_CODE_OPENING_LANG = re.compile(r"^\{code:[a-zA-Z]+\}", re.MULTILINE)

# Span-level patterns.
RE_MD_BOLD = re.compile(r"\*\*[^*]+\*\*")
RE_MD_LINK = re.compile(r"\[[^\]]+\]\([^)]+\)")
RE_JIRA_CODE_LANG_ANY = re.compile(r"\{code:[a-zA-Z]+\}")
RE_JIRA_USER_MENTION = re.compile(r"\[~[A-Za-z._\-]+\]")
RE_JIRA_ISSUE_LINK = re.compile(r"\[[A-Z]+-[0-9]+\]")

# Block-macro tag patterns (used for occurrence counting).
RE_CODE_TAG = re.compile(r"\{code\b")
RE_PANEL_TAG = re.compile(r"\{panel\b")
RE_COLOR_TAG = re.compile(r"\{color\b")

MAX_EXAMPLES_PER_ISSUE = 5
MAX_BOLD_LINK_EXAMPLES = 3


# --- Search helpers ------------------------------------------------------------


def _line_matches(
    text: str, pattern: re.Pattern[str], limit: int
) -> tuple[LineMatch, ...]:
    """Return the first ``limit`` lines that match ``pattern``."""
    examples: list[LineMatch] = []
    for line_no, line in enumerate(text.splitlines(), 1):
        if pattern.search(line):
            examples.append(LineMatch(line_no, line))
            if len(examples) >= limit:
                break
    return tuple(examples)


# --- Individual checks ---------------------------------------------------------


def _check_markdown_headings(text: str) -> Iterable[Issue]:
    matches = _line_matches(text, RE_MD_HEADING, MAX_EXAMPLES_PER_ISSUE)
    if matches:
        yield Issue(
            Severity.ERROR,
            "Markdown headings found (##). Use: h2. Heading",
            matches,
        )


def _check_markdown_bold(text: str) -> Iterable[Issue]:
    matches = _line_matches(text, RE_MD_BOLD, MAX_BOLD_LINK_EXAMPLES)
    if matches:
        yield Issue(
            Severity.ERROR,
            "Markdown bold found (**text**). Use: *text*",
            matches,
        )


def _check_markdown_fences(text: str) -> Iterable[Issue]:
    matches = _line_matches(text, RE_MD_FENCE, MAX_EXAMPLES_PER_ISSUE)
    if matches:
        yield Issue(
            Severity.ERROR,
            "Markdown code fences found (```). Use: {code:language}...{code}",
            matches,
        )


def _check_markdown_links(text: str) -> Iterable[Issue]:
    matches = _line_matches(text, RE_MD_LINK, MAX_BOLD_LINK_EXAMPLES)
    if matches:
        yield Issue(
            Severity.ERROR,
            "Markdown links found ([text](url)). Use: [text|url]",
            matches,
        )


def _check_markdown_bullets(text: str) -> Iterable[Issue]:
    if RE_MD_BULLET.search(text):
        yield Issue(
            Severity.WARN,
            "Markdown bullets found (- item). Jira uses: * item",
        )


def _check_heading_spacing(text: str) -> Iterable[Issue]:
    matches = _line_matches(text, RE_JIRA_HEADING_NO_SPACE, MAX_EXAMPLES_PER_ISSUE)
    if matches:
        yield Issue(
            Severity.ERROR,
            "Heading missing space after period. Use: h2. Title",
            matches,
        )


def _check_code_block_language(text: str) -> Iterable[Issue]:
    """Warn when at least one code block opens without a language identifier.

    Closing tags are also bare ``{code}``, so a balanced file with two
    language-tagged openings has ``bare == lang``. ``bare > lang`` means at
    least one opening is missing a language.
    """
    bare_openings = len(RE_CODE_OPENING_BARE.findall(text))
    lang_openings = len(RE_CODE_OPENING_LANG.findall(text))
    if bare_openings > lang_openings:
        yield Issue(
            Severity.WARN,
            "Code block without language identifier. Use: {code:python}",
        )


def _check_block_balance(
    text: str,
    pattern: re.Pattern[str],
    tag: str,
    description: str,
    severity: Severity,
) -> Iterable[Issue]:
    count = len(pattern.findall(text))
    if count % 2 != 0:
        yield Issue(
            severity,
            f"Odd number of {{{tag}}} tags ({count}). Likely unclosed {description}.",
        )


def _check_code_balance(text: str) -> Iterable[Issue]:
    yield from _check_block_balance(
        text, RE_CODE_TAG, "code", "code block", Severity.ERROR
    )


def _check_panel_balance(text: str) -> Iterable[Issue]:
    yield from _check_block_balance(
        text, RE_PANEL_TAG, "panel", "panel", Severity.ERROR
    )


def _check_color_balance(text: str) -> Iterable[Issue]:
    yield from _check_block_balance(
        text, RE_COLOR_TAG, "color", "color block", Severity.WARN
    )


def _check_table_headers(text: str) -> Iterable[Issue]:
    has_data = RE_TABLE_DATA_ROW.search(text) is not None
    has_header = RE_TABLE_HEADER_ROW.search(text) is not None
    if has_data and not has_header:
        yield Issue(
            Severity.WARN,
            "Table rows found but no header rows (||Header||). "
            "Verify table formatting.",
        )


def _check_jira_features_present(text: str) -> Iterable[Issue]:
    if RE_JIRA_HEADING_OK.search(text):
        yield Issue(Severity.OK, "Correctly formatted Jira headings")
    if RE_JIRA_CODE_LANG_ANY.search(text):
        yield Issue(Severity.OK, "Code blocks with language identifiers")
    if RE_JIRA_USER_MENTION.search(text):
        yield Issue(Severity.OK, "User mentions ([~username])")
    if RE_JIRA_ISSUE_LINK.search(text):
        yield Issue(Severity.OK, "Issue links ([PROJ-123])")


# --- Per-file orchestrator -----------------------------------------------------

CheckFn = Callable[[str], Iterable[Issue]]

CHECKS: tuple[CheckFn, ...] = (
    _check_markdown_headings,
    _check_markdown_bold,
    _check_markdown_fences,
    _check_markdown_links,
    _check_markdown_bullets,
    _check_heading_spacing,
    _check_code_block_language,
    _check_code_balance,
    _check_panel_balance,
    _check_color_balance,
    _check_table_headers,
    _check_jira_features_present,
)


def validate_file(path: Path) -> list[Issue]:
    """Run every check against ``path`` and return the issues found."""
    if not path.is_file():
        return [Issue(Severity.ERROR, f"File not found: {path}")]
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return [Issue(Severity.ERROR, f"Cannot read file: {exc}")]

    issues: list[Issue] = []
    for check in CHECKS:
        issues.extend(check(text))
    return issues


# --- Output --------------------------------------------------------------------


def _format_issue(issue: Issue, use_color: bool) -> str:
    label = _paint(use_color, issue.severity, f"{issue.severity.value}:")
    lines = [f"{label} {issue.message}"]
    for match in issue.matches:
        lines.append(f"  {match.line}:{match.text}")
    return "\n".join(lines)


def _print_summary(
    file_count: int, errors: int, warnings: int, use_color: bool
) -> None:
    print()
    print("--- Summary ---")
    print(f"Files checked: {file_count}")
    print(_paint(use_color, Severity.ERROR, f"Errors: {errors}"))
    print(_paint(use_color, Severity.WARN, f"Warnings: {warnings}"))
    if errors == 0 and warnings == 0:
        print(_paint(use_color, Severity.OK, "All checks passed."))
    elif errors == 0:
        print(
            _paint(
                use_color,
                Severity.WARN,
                f"No errors. {warnings} warning(s).",
            )
        )
    else:
        print(
            _paint(
                use_color,
                Severity.ERROR,
                f"{errors} error(s) found. Fix before submitting to Jira.",
            )
        )


# --- CLI -----------------------------------------------------------------------


def _resolve_color(flag: bool | None) -> bool:
    if flag is not None:
        return flag
    if os.environ.get("NO_COLOR"):
        return False
    return sys.stdout.isatty()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="validate_jira_syntax.py",
        description=(
            "Validate Jira wiki markup syntax and flag Markdown mistakes."
        ),
    )
    parser.add_argument(
        "files",
        nargs="+",
        type=Path,
        help="One or more files to validate.",
    )
    color = parser.add_mutually_exclusive_group()
    color.add_argument(
        "--color",
        dest="color",
        action="store_true",
        default=None,
        help="Force coloured output even when stdout is not a TTY.",
    )
    color.add_argument(
        "--no-color",
        dest="color",
        action="store_false",
        help="Disable coloured output.",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    use_color = _resolve_color(args.color)

    total_errors = 0
    total_warnings = 0

    for path in args.files:
        print()
        print(f"--- {path} ---")
        issues = validate_file(path)
        for issue in issues:
            print(_format_issue(issue, use_color))
            if issue.severity is Severity.ERROR:
                total_errors += 1
            elif issue.severity is Severity.WARN:
                total_warnings += 1

    _print_summary(len(args.files), total_errors, total_warnings, use_color)
    return 1 if total_errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
