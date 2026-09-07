#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""Reject the comment shapes AGENTS.md "Comments Explain Why" forbids.

Reads every tracked Python and shell file and reports banner separators, step and
section labels, and files whose comments and docstrings take up more than
MAX_DENSITY of their lines.

Usage:
    comment_style.py [REPO_ROOT]

Exit codes:
    0  every tracked Python file is clean
    1  at least one violation, one line each on stdout

Zero runtime dependencies. Works on Python 3.9+.
"""

from __future__ import annotations

import ast
import io
import re
import subprocess
import sys
import tokenize
from pathlib import Path

MAX_DENSITY = 0.35
MAX_BLOCK = 5

BANNER = re.compile(r"^#\s*[#=*-]\s*(?:[#=*-]\s*){2,}$")
LABELED_BANNER = re.compile(r"^#\s*[#=*-]{2,}.*[#=*-]{2,}\s*$")
STEP_LABEL = re.compile(r"^#\s*(?:step\s*\d+|\d+\s*[.):]|section\s*:)", re.IGNORECASE)
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")

# These files predate the gate. It freezes what each already carries as its
# ceiling, so anything added to them from now on still fails.
LEGACY_BANNERS = {
    ".agents/skills/context-files/scripts/validate_context_file.py": 9,
    ".agents/skills/improve-self/scripts/discover_skills.py": 7,
    ".agents/skills/jira-syntax/scripts/validate_jira_syntax.py": 8,
    ".agents/skills/make-skill/scripts/validate_skill.py": 13,
}


def tracked_sources(root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--", "*.py", "*.sh", "*.bats"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.splitlines()


def full_line_comments(source: str) -> list[tuple[int, str]]:
    """Return (line number, text) for every comment that owns its line."""
    lines = source.splitlines()
    found: list[tuple[int, str]] = []
    for token in tokenize.generate_tokens(io.StringIO(source).readline):
        if token.type != tokenize.COMMENT:
            continue
        row = token.start[0]
        if lines[row - 1].lstrip().startswith("#"):
            found.append((row, token.string.strip()))
    return found


def shell_full_line_comments(source: str) -> list[tuple[int, str]]:
    """Return (line number, text) for every comment that owns its line."""
    found: list[tuple[int, str]] = []
    terminator: str | None = None
    for row, line in enumerate(source.splitlines(), start=1):
        if terminator is not None:
            if line.strip() == terminator:
                terminator = None
            continue
        opener = HEREDOC.search(line)
        if opener:
            terminator = opener.group(2)
            continue
        if row == 1 and line.startswith("#!"):
            continue
        if line.lstrip().startswith("#"):
            found.append((row, line.strip()))
    return found


def docstring_spans(source: str) -> list[tuple[int, int]]:
    spans: list[tuple[int, int]] = []
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Module) or not isinstance(
            node, (ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)
        ):
            continue
        first = node.body[0] if node.body else None
        if not isinstance(first, ast.Expr):
            continue
        value = first.value
        if isinstance(value, ast.Constant) and isinstance(value.value, str):
            spans.append((value.lineno, (value.end_lineno or value.lineno)))
    return spans


def docstring_lines(source: str) -> int:
    counted = 0
    for node in ast.walk(ast.parse(source)):
        if not isinstance(
            node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)
        ):
            continue
        first = node.body[0] if node.body else None
        if not isinstance(first, ast.Expr):
            continue
        value = first.value
        if isinstance(value, ast.Constant) and isinstance(value.value, str):
            counted += (value.end_lineno or value.lineno) - value.lineno + 1
    return counted


def banner_violations(path: str, comments: list[tuple[int, str]]) -> list[str]:
    hits = [
        f"{path}:{row}: banner separator, not a why: {text}"
        for row, text in comments
        if BANNER.match(text) or LABELED_BANNER.match(text)
    ]
    if len(hits) <= LEGACY_BANNERS.get(path, 0):
        return []
    return hits


def label_violations(path: str, comments: list[tuple[int, str]]) -> list[str]:
    return [
        f"{path}:{row}: step or section label: {text}"
        for row, text in comments
        if STEP_LABEL.match(text)
    ]


def block_violations(
    path: str, comments: list[tuple[int, str]], docstrings: list[tuple[int, int]]
) -> list[str]:
    blocks: list[list[int]] = []
    for row, _ in comments:
        if blocks and row == blocks[-1][-1] + 1:
            blocks[-1].append(row)
        else:
            blocks.append([row])
    spans = [(block[0], len(block), "comment block") for block in blocks]
    spans += [(start, end - start + 1, "docstring") for start, end in docstrings]
    return [
        f"{path}:{row}: {length}-line {kind}, ceiling {MAX_BLOCK}; "
        "a block this long is narrative, not a why"
        for row, length, kind in sorted(spans)
        if length > MAX_BLOCK
    ]


def density_violation(path: str, source: str, prose: int) -> list[str]:
    total = len(source.splitlines())
    if total == 0:
        return []
    density = prose / total
    if density <= MAX_DENSITY:
        return []
    return [
        f"{path}: comments and docstrings are {density:.0%} of {total} lines, "
        f"ceiling {MAX_DENSITY:.0%}; the code is not done"
    ]


def check(root: Path) -> list[str]:
    problems: list[str] = []
    for path in tracked_sources(root):
        source = (root / path).read_text(encoding="utf-8")
        if path.endswith(".py"):
            comments = full_line_comments(source)
            docstrings = docstring_spans(source)
            problems.extend(
                density_violation(path, source, len(comments) + docstring_lines(source))
            )
        else:
            comments = shell_full_line_comments(source)
            docstrings = []
        problems.extend(banner_violations(path, comments))
        problems.extend(label_violations(path, comments))
        problems.extend(block_violations(path, comments, docstrings))
    return problems


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else repo_root
    problems = check(root)
    for problem in problems:
        print(problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
