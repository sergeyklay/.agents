#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""
Discover installed Agent Skills across vendor directories.

Scans `.{vendor}/skills/` under the project root and `~/.{vendor}/skills/`
in the user's home, extracts each skill's `name` and `description` from
its frontmatter, and prints the result so the agent can compare existing
descriptions against a candidate gap before proposing a new skill.

Usage:
    discover_skills.py [options]

Options:
    --vendors VENDORS    Comma-separated vendor names to scan.
                         Default: agents,claude,cursor,gemini,github
    --project-root PATH  Project root to scan (default: current dir).
    --no-project         Skip project-local `.{vendor}/skills/`.
    --no-home            Skip `~/.{vendor}/skills/`.
    --format FORMAT      Output format: text (default), json, markdown.
    --quiet              Suppress warnings about malformed SKILL.md.

Exit codes:
    0  Discovery completed (zero or more skills found).
    1  Recoverable error (some SKILL.md unreadable; results still printed).
    2  Usage error.

Examples:
    discover_skills.py
    discover_skills.py --vendors agents,claude
    discover_skills.py --format json --no-home
    discover_skills.py --project-root /home/me/work/project

The script has zero runtime dependencies and works on Python 3.9+. It
parses only the subset of YAML used in skill frontmatter: plain scalars,
single/double-quoted scalars, and `>`/`|` block scalars for the
description. Flow style is not supported.
"""

from __future__ import annotations

import argparse
import enum
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Sequence


# --- Public constants ---------------------------------------------------------

DEFAULT_VENDORS: tuple[str, ...] = (
    "agents",
    "claude",
    "opencode",
    "gemini",
    "copilot",
)
DEFAULT_FORMAT: str = "text"
FRONTMATTER_DELIMITER: str = "---"


# --- Data model ---------------------------------------------------------------


class Scope(enum.Enum):
    """Where a skill was discovered."""

    PROJECT = "project"
    HOME = "home"


@dataclass(frozen=True)
class SkillEntry:
    """A successfully-discovered skill."""

    vendor: str
    scope: Scope
    path: Path
    name: str
    description: str

    def as_dict(self) -> dict[str, str]:
        return {
            "vendor": self.vendor,
            "scope": self.scope.value,
            "path": str(self.path),
            "name": self.name,
            "description": self.description,
        }


@dataclass(frozen=True)
class DiscoveryError:
    """A SKILL.md that could not be parsed."""

    path: Path
    reason: str


# --- Frontmatter parser -------------------------------------------------------


class FrontmatterError(ValueError):
    """Raised when frontmatter is missing or required fields cannot be read."""


def read_name_and_description(skill_md: Path) -> tuple[str, str]:
    """Return `(name, description)` from a SKILL.md frontmatter block.

    Raises `FrontmatterError` when the file lacks frontmatter delimiters,
    when required keys are missing, or when the file cannot be read.
    """
    try:
        text = skill_md.read_text(encoding="utf-8-sig", errors="replace")
    except OSError as exc:
        raise FrontmatterError(f"cannot read file: {exc}") from exc

    block = _extract_frontmatter_block(text)
    if block is None:
        raise FrontmatterError("missing '---' frontmatter delimiters")

    name = _extract_scalar(block, "name")
    description = _extract_scalar(block, "description")

    if not name:
        raise FrontmatterError("missing or empty 'name' field")
    if not description:
        raise FrontmatterError("missing or empty 'description' field")
    return name, description


def _extract_frontmatter_block(text: str) -> str | None:
    """Return the text between the first two '---' lines, or None."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != FRONTMATTER_DELIMITER:
        return None
    for i in range(1, len(lines)):
        if lines[i].strip() == FRONTMATTER_DELIMITER:
            return "\n".join(lines[1:i])
    return None


def _extract_scalar(block: str, key: str) -> str:
    """Find a top-level `key:` and return its value (folded if block scalar)."""
    lines = block.splitlines()
    prefix = f"{key}:"
    for i, raw in enumerate(lines):
        if not raw.startswith(prefix):
            continue
        rest = raw[len(prefix):].lstrip()
        if not rest or rest[0] in (">", "|"):
            return _read_block_scalar(lines, i + 1)
        return _unquote(rest)
    return ""


def _read_block_scalar(lines: Sequence[str], start: int) -> str:
    """Collect indented continuation lines and fold them for display.

    The discovery script always folds (whitespace-collapses) regardless of
    YAML block style (`>`, `|`, or implicit nested mapping value) because
    the output is intended for visual scanning by the agent, not for
    round-tripping the YAML. Literal vs folded semantics do not affect
    that use case.
    """
    collected: list[str] = []
    base_indent: int | None = None
    for raw in lines[start:]:
        if raw.strip() == "":
            collected.append("")
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent == 0:
            break
        if base_indent is None:
            base_indent = indent
        if indent < base_indent:
            break
        collected.append(raw[base_indent:])
    folded = " ".join(line.strip() for line in collected if line.strip())
    return folded


def _unquote(value: str) -> str:
    """Strip a single pair of surrounding quotes if present."""
    value = value.rstrip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


# --- Discovery ----------------------------------------------------------------


def discover(
    vendors: Sequence[str],
    project_root: Path,
    include_project: bool,
    include_home: bool,
) -> Iterable[SkillEntry | DiscoveryError]:
    """Yield one item per SKILL.md found across all vendor directories."""
    home = Path.home()
    for vendor in vendors:
        if include_project:
            yield from _scan_directory(
                project_root / f".{vendor}" / "skills",
                vendor=vendor,
                scope=Scope.PROJECT,
            )
        if include_home:
            yield from _scan_directory(
                home / f".{vendor}" / "skills",
                vendor=vendor,
                scope=Scope.HOME,
            )


def _scan_directory(
    skills_root: Path, vendor: str, scope: Scope,
) -> Iterable[SkillEntry | DiscoveryError]:
    if not skills_root.is_dir():
        return
    for child in sorted(skills_root.iterdir()):
        if not child.is_dir():
            continue
        skill_md = child / "SKILL.md"
        if not skill_md.is_file():
            continue
        try:
            name, description = read_name_and_description(skill_md)
        except FrontmatterError as exc:
            yield DiscoveryError(path=skill_md, reason=str(exc))
            continue
        yield SkillEntry(
            vendor=vendor,
            scope=scope,
            path=skill_md,
            name=name,
            description=description,
        )


# --- Formatters ---------------------------------------------------------------

Formatter = Callable[[Sequence[SkillEntry]], str]


def format_text(entries: Sequence[SkillEntry]) -> str:
    if not entries:
        return "(no skills discovered)"
    parts: list[str] = []
    for e in entries:
        parts.append(f"[{e.scope.value}:{e.vendor}] {e.name}")
        parts.append(f"  {e.description}")
        parts.append(f"  ({e.path})")
        parts.append("")
    return "\n".join(parts).rstrip()


def format_json(entries: Sequence[SkillEntry]) -> str:
    return json.dumps(
        [e.as_dict() for e in entries], indent=2, ensure_ascii=False,
    )


def format_markdown(entries: Sequence[SkillEntry]) -> str:
    if not entries:
        return "_(no skills discovered)_"
    rows = ["| scope | vendor | name | description |",
            "|---|---|---|---|"]
    for e in entries:
        desc = e.description.replace("|", "\\|").replace("\n", " ")
        rows.append(
            f"| {e.scope.value} | {e.vendor} | `{e.name}` | {desc} |"
        )
    return "\n".join(rows)


FORMATTERS: dict[str, Formatter] = {
    "text": format_text,
    "json": format_json,
    "markdown": format_markdown,
}


# --- CLI ----------------------------------------------------------------------


def _validate_vendor(name: str) -> str:
    name = name.strip()
    if not name:
        raise argparse.ArgumentTypeError("vendor name must not be empty")
    if "/" in name or "\\" in name or name.startswith("."):
        raise argparse.ArgumentTypeError(
            f"invalid vendor name {name!r}: no slashes or leading dot"
        )
    return name


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="discover_skills.py",
        description=(
            "Discover installed Agent Skills across vendor directories "
            "and print their frontmatter for the agent to inspect."
        ),
    )
    parser.add_argument(
        "--vendors",
        default=",".join(DEFAULT_VENDORS),
        help=(
            "Comma-separated vendor names to scan "
            f"(default: {','.join(DEFAULT_VENDORS)})."
        ),
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path.cwd(),
        help="Project root to scan (default: current working directory).",
    )
    parser.add_argument(
        "--no-project",
        action="store_true",
        help="Skip project-local .{vendor}/skills/.",
    )
    parser.add_argument(
        "--no-home",
        action="store_true",
        help="Skip ~/.{vendor}/skills/.",
    )
    parser.add_argument(
        "--format",
        default=DEFAULT_FORMAT,
        choices=sorted(FORMATTERS),
        help=f"Output format (default: {DEFAULT_FORMAT}).",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress warnings about malformed SKILL.md files.",
    )
    return parser


def _parse_vendors(raw: str) -> list[str]:
    return [_validate_vendor(v) for v in raw.split(",") if v.strip()]


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)

    try:
        vendors = _parse_vendors(args.vendors)
    except argparse.ArgumentTypeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if not vendors:
        print("error: --vendors must not be empty", file=sys.stderr)
        return 2

    if args.no_project and args.no_home:
        print(
            "error: --no-project and --no-home cancel each other",
            file=sys.stderr,
        )
        return 2

    entries: list[SkillEntry] = []
    errors: list[DiscoveryError] = []

    for item in discover(
        vendors=vendors,
        project_root=args.project_root.expanduser().resolve(),
        include_project=not args.no_project,
        include_home=not args.no_home,
    ):
        if isinstance(item, SkillEntry):
            entries.append(item)
        else:
            errors.append(item)

    print(FORMATTERS[args.format](entries))

    if errors and not args.quiet:
        print(file=sys.stderr)
        for err in errors:
            print(f"warning: {err.path}: {err.reason}", file=sys.stderr)

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
