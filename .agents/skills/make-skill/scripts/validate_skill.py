#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""
Validate an Agent Skill directory against the agentskills.io specification.

Usage:
    validate_skill.py <path-to-skill-directory>

Exit codes:
    0  validation passed (no errors; warnings are allowed)
    1  validation failed (one or more errors)
    2  usage error or unreadable input

The script has zero runtime dependencies and works on Python 3.9+. The
bundled YAML parser handles the subset of YAML used in skill frontmatter:
block mappings, block sequences, plain and quoted scalars, and block
scalars ('>' folded, '|' literal, with optional chomping). Flow style,
anchors, aliases, tags and multi-document streams are intentionally not
supported.
"""

from __future__ import annotations

import argparse
import enum
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


# --- Public limits and patterns ------------------------------------------------

NAME_PATTERN = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
XML_TAG_PATTERN = re.compile(r"<[^>]+>")
MARKDOWN_LINK_PATTERN = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
# Drive letters (C:\, D:\) or "\" + path char that is not a common escape.
WINDOWS_PATH_PATTERN = re.compile(
    r"[A-Za-z]:\\"
    r"|"
    r"\\(?![ntrfvb\"'\\])[A-Za-z0-9_]"
)
BLOCK_SCALAR_HEADER = re.compile(r"^[>|][+\-1-9]*\s*(#.*)?$")

MAX_NAME_LENGTH = 64
MAX_DESCRIPTION_LENGTH = 1024
MAX_COMPATIBILITY_LENGTH = 500
MAX_BODY_LINES = 500
MAX_REFERENCE_LINES_WITHOUT_TOC = 100

RESERVED_WORDS: tuple[str, ...] = ("anthropic", "claude")
KNOWN_DIRECTORIES: frozenset[str] = frozenset(
    {"scripts", "references", "assets", "evals", "agents"}
)
TRIGGER_KEYWORDS: tuple[str, ...] = (
    "use when",
    "use this",
    "trigger",
    "whenever",
    "also use",
)
TOC_KEYWORDS: tuple[str, ...] = ("contents", "table of contents", "## toc")
FIRST_OR_SECOND_PERSON_PREFIXES: tuple[str, ...] = (
    "I ",
    "I can",
    "You ",
    "You can",
)


# --- Issue model ---------------------------------------------------------------


class Severity(enum.Enum):
    ERROR = "ERROR"
    WARN = "WARN"
    INFO = "INFO"


_SEVERITY_MARKER: dict[Severity, str] = {
    Severity.ERROR: "x",
    Severity.WARN: "!",
    Severity.INFO: "-",
}


@dataclass(frozen=True)
class Issue:
    severity: Severity
    message: str

    def __str__(self) -> str:
        return f"  [{_SEVERITY_MARKER[self.severity]}] {self.message}"


# --- Frontmatter parsing -------------------------------------------------------


class FrontmatterError(ValueError):
    """Raised when frontmatter is missing or cannot be parsed."""


_DELIMITER = "---"


def split_frontmatter(text: str) -> tuple[str, str]:
    """Return (frontmatter_yaml, body) by splitting at '---' delimiters.

    The opening delimiter must be the very first line of the file. Raises
    FrontmatterError if the frontmatter block is missing or unterminated.
    """
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != _DELIMITER:
        raise FrontmatterError(
            "SKILL.md must begin with YAML frontmatter ('---' on the first line)"
        )

    fm_start = len(lines[0])
    cursor = fm_start
    for line in lines[1:]:
        if line.rstrip("\r\n") == _DELIMITER:
            return text[fm_start:cursor], text[cursor + len(line):]
        cursor += len(line)

    raise FrontmatterError("frontmatter is missing closing '---' delimiter")


def parse_yaml(text: str) -> Any:
    """Parse the YAML subset used in skill frontmatter."""
    parser = _Parser(text)
    value = parser.parse_root()
    parser.expect_eof()
    return value


class _Parser:
    """Recursive-descent parser for skill-frontmatter YAML."""

    def __init__(self, text: str) -> None:
        self._lines = text.splitlines()
        self._pos = 0

    # --- Public entry points --------------------------------------------------

    def parse_root(self) -> Any:
        head = self._peek()
        if head is None:
            return {}
        _, indent, body = head
        if _is_sequence_item(body):
            return self._parse_sequence(indent)
        return self._parse_mapping(indent)

    def expect_eof(self) -> None:
        head = self._peek()
        if head is not None:
            line_no, _, body = head
            raise FrontmatterError(
                f"line {line_no}: unexpected content {body!r}"
            )

    # --- Cursor helpers -------------------------------------------------------

    def _peek(self) -> tuple[int, int, str] | None:
        """Return (line_no, indent, body) for the next significant line."""
        while self._pos < len(self._lines):
            raw = self._lines[self._pos]
            stripped = raw.strip()
            if stripped == "" or stripped.startswith("#"):
                self._pos += 1
                continue
            indent = len(raw) - len(raw.lstrip(" "))
            return self._pos + 1, indent, raw[indent:]
        return None

    def _advance(self) -> None:
        self._pos += 1

    # --- Mapping --------------------------------------------------------------

    def _parse_mapping(self, indent: int) -> dict[str, Any]:
        result: dict[str, Any] = {}
        while True:
            head = self._peek()
            if head is None:
                break
            line_no, cur_indent, body = head
            if cur_indent < indent:
                break
            if cur_indent > indent:
                raise FrontmatterError(
                    f"line {line_no}: unexpected indentation "
                    f"(expected {indent}, got {cur_indent})"
                )
            if _is_sequence_item(body):
                raise FrontmatterError(
                    f"line {line_no}: expected mapping key, got list item"
                )

            key, after_colon = _split_key(body, line_no)
            self._advance()
            value = self._parse_value(after_colon, indent, line_no)

            if key in result:
                raise FrontmatterError(
                    f"line {line_no}: duplicate key {key!r}"
                )
            result[key] = value
        return result

    # --- Value dispatch -------------------------------------------------------

    def _parse_value(
        self, value_text: str, parent_indent: int, line_no: int
    ) -> Any:
        if BLOCK_SCALAR_HEADER.match(value_text):
            return self._parse_block_scalar(value_text, parent_indent, line_no)

        cleaned = _strip_trailing_comment(value_text).strip()
        if cleaned == "":
            return self._parse_nested(parent_indent)
        if cleaned.startswith('"'):
            return _decode_double_quoted(cleaned, line_no)
        if cleaned.startswith("'"):
            return _decode_single_quoted(cleaned, line_no)
        if cleaned[0] in ("[", "{"):
            raise FrontmatterError(
                f"line {line_no}: flow style ([...] or {{...}}) is not supported"
            )
        return cleaned

    def _parse_nested(self, parent_indent: int) -> Any:
        head = self._peek()
        if head is None:
            return ""
        _, indent, body = head
        if indent <= parent_indent:
            return ""
        if _is_sequence_item(body):
            return self._parse_sequence(indent)
        return self._parse_mapping(indent)

    # --- Sequence -------------------------------------------------------------

    def _parse_sequence(self, indent: int) -> list[Any]:
        items: list[Any] = []
        while True:
            head = self._peek()
            if head is None:
                break
            line_no, cur_indent, body = head
            if cur_indent < indent:
                break
            if cur_indent > indent:
                raise FrontmatterError(
                    f"line {line_no}: unexpected indentation in sequence"
                )
            if not _is_sequence_item(body):
                break

            self._advance()
            inner = body[2:] if body.startswith("- ") else ""

            if BLOCK_SCALAR_HEADER.match(inner):
                items.append(self._parse_block_scalar(inner, indent, line_no))
                continue

            cleaned = _strip_trailing_comment(inner).strip()
            if cleaned == "":
                items.append(self._parse_nested(indent))
            elif cleaned.startswith('"'):
                items.append(_decode_double_quoted(cleaned, line_no))
            elif cleaned.startswith("'"):
                items.append(_decode_single_quoted(cleaned, line_no))
            elif cleaned[0] in ("[", "{"):
                raise FrontmatterError(
                    f"line {line_no}: flow style is not supported"
                )
            else:
                items.append(cleaned)
        return items

    # --- Block scalars --------------------------------------------------------

    def _parse_block_scalar(
        self, indicator: str, parent_indent: int, line_no: int
    ) -> str:
        style, chomp = _parse_block_indicator(indicator, line_no)

        block_lines: list[str] = []
        block_indent: int | None = None

        while self._pos < len(self._lines):
            raw = self._lines[self._pos]
            if raw.strip() == "":
                block_lines.append("")
                self._pos += 1
                continue
            cur_indent = len(raw) - len(raw.lstrip(" "))
            if cur_indent <= parent_indent:
                break
            if block_indent is None:
                block_indent = cur_indent
            if cur_indent < block_indent:
                break
            block_lines.append(raw[block_indent:])
            self._pos += 1

        # Discard surrounding blank lines (track trailing for chomping).
        while block_lines and block_lines[0] == "":
            block_lines.pop(0)
        trailing_blanks = 0
        while block_lines and block_lines[-1] == "":
            block_lines.pop()
            trailing_blanks += 1

        if not block_lines:
            return "\n" * trailing_blanks if chomp == "+" else ""

        joined = (
            "\n".join(block_lines)
            if style == "|"
            else _fold_block_lines(block_lines)
        )

        if chomp == "-":  # strip
            return joined
        if chomp == "+":  # keep
            return joined + "\n" * (1 + trailing_blanks)
        return joined + "\n"  # clip (default)


# --- Parser helpers ------------------------------------------------------------


def _is_sequence_item(body: str) -> bool:
    return body == "-" or body.startswith("- ")


def _split_key(body: str, line_no: int) -> tuple[str, str]:
    if body.startswith(("'", '"')):
        raise FrontmatterError(
            f"line {line_no}: quoted keys are not supported"
        )
    colon = body.find(":")
    if colon == -1:
        raise FrontmatterError(
            f"line {line_no}: expected 'key: value' (no ':' found)"
        )
    key = body[:colon].rstrip()
    if not key:
        raise FrontmatterError(f"line {line_no}: empty key")
    rest = body[colon + 1:]
    if rest and not rest.startswith(" "):
        raise FrontmatterError(
            f"line {line_no}: expected space after ':' for key {key!r}"
        )
    return key, rest.lstrip(" ")


def _parse_block_indicator(text: str, line_no: int) -> tuple[str, str]:
    """Return (style, chomp) where style is '>' or '|' and chomp is '', '-' or '+'."""
    style = text[0]
    chomp = ""
    for ch in text[1:]:
        if ch == " ":
            continue
        if ch == "#":
            break
        if ch in ("+", "-"):
            if chomp:
                raise FrontmatterError(
                    f"line {line_no}: invalid block scalar chomping indicator"
                )
            chomp = ch
        elif ch.isdigit():
            continue  # explicit indentation indicator: accepted but auto-detected
        else:
            raise FrontmatterError(
                f"line {line_no}: invalid block scalar indicator {text!r}"
            )
    return style, chomp


def _fold_block_lines(lines: list[str]) -> str:
    """Join lines per YAML '>' (folded) semantics.

    A single line break between two non-empty lines becomes a space; each
    empty line within the block contributes one literal newline to the output.
    """
    parts: list[str] = []
    blank_run = 0
    has_content = False
    for line in lines:
        if line == "":
            if has_content:
                blank_run += 1
            continue
        if blank_run:
            parts.append("\n" * blank_run)
            blank_run = 0
        elif has_content:
            parts.append(" ")
        parts.append(line)
        has_content = True
    return "".join(parts)


def _strip_trailing_comment(text: str) -> str:
    """Remove a trailing ' # comment'; respect quoted strings."""
    if not text:
        return text
    if text.lstrip().startswith("#"):
        return ""
    in_single = False
    in_double = False
    for i, ch in enumerate(text):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            if i == 0 or text[i - 1] != "\\":
                in_double = not in_double
        elif ch == "#" and not in_single and not in_double and i > 0 and text[i - 1] == " ":
            return text[:i].rstrip()
    return text


def _decode_double_quoted(text: str, line_no: int) -> str:
    if len(text) < 2 or not text.endswith('"'):
        raise FrontmatterError(
            f"line {line_no}: unterminated double-quoted string"
        )
    inner = text[1:-1]
    out: list[str] = []
    escapes = {
        "n": "\n",
        "t": "\t",
        "r": "\r",
        "\\": "\\",
        '"': '"',
        "'": "'",
        "0": "\0",
        "/": "/",
    }
    i = 0
    while i < len(inner):
        ch = inner[i]
        if ch == "\\" and i + 1 < len(inner):
            replacement = escapes.get(inner[i + 1])
            if replacement is not None:
                out.append(replacement)
                i += 2
                continue
        out.append(ch)
        i += 1
    return "".join(out)


def _decode_single_quoted(text: str, line_no: int) -> str:
    if len(text) < 2 or not text.endswith("'"):
        raise FrontmatterError(
            f"line {line_no}: unterminated single-quoted string"
        )
    return text[1:-1].replace("''", "'")


# --- Individual checks ---------------------------------------------------------


def _check_name(fm: dict[str, Any], skill_dir: Path) -> Iterable[Issue]:
    raw = fm.get("name")
    if raw is None or (isinstance(raw, str) and not raw.strip()):
        yield Issue(Severity.ERROR, "Missing required field: name")
        return

    name = str(raw).strip()
    if len(name) > MAX_NAME_LENGTH:
        yield Issue(
            Severity.ERROR,
            f"name exceeds {MAX_NAME_LENGTH} chars ({len(name)})",
        )
    if not NAME_PATTERN.match(name):
        yield Issue(
            Severity.ERROR,
            f"name {name!r} must be lowercase alphanumeric with single hyphens",
        )
    if "--" in name:
        yield Issue(
            Severity.ERROR,
            "name cannot contain consecutive hyphens (--)",
        )
    for word in RESERVED_WORDS:
        if word in name.lower():
            yield Issue(
                Severity.ERROR,
                f"name contains reserved word {word!r}",
            )
    if XML_TAG_PATTERN.search(name):
        yield Issue(Severity.ERROR, "name cannot contain XML tags")
    if name != skill_dir.name:
        yield Issue(
            Severity.WARN,
            f"name {name!r} does not match directory name {skill_dir.name!r}",
        )


def _check_description(fm: dict[str, Any]) -> Iterable[Issue]:
    raw = fm.get("description")
    if raw is None:
        yield Issue(Severity.ERROR, "Missing required field: description")
        return

    desc = str(raw).strip()
    if not desc:
        yield Issue(Severity.ERROR, "description cannot be empty")
        return

    if len(desc) > MAX_DESCRIPTION_LENGTH:
        yield Issue(
            Severity.ERROR,
            f"description exceeds {MAX_DESCRIPTION_LENGTH} chars ({len(desc)})",
        )
    if XML_TAG_PATTERN.search(desc):
        yield Issue(Severity.ERROR, "description cannot contain XML tags")
    if desc.startswith(FIRST_OR_SECOND_PERSON_PREFIXES):
        yield Issue(
            Severity.WARN,
            "description should use third person, not first or second person",
        )
    if "[TODO" in desc:
        yield Issue(
            Severity.WARN,
            "description contains [TODO marker - complete before using",
        )

    desc_lower = desc.lower()
    has_trigger = any(kw in desc_lower for kw in TRIGGER_KEYWORDS)
    if not has_trigger and len(desc) < 200:
        yield Issue(
            Severity.WARN,
            "description may lack trigger phrases - "
            "agents need explicit guidance on when to activate",
        )


def _check_compatibility(fm: dict[str, Any]) -> Iterable[Issue]:
    compat = fm.get("compatibility")
    if compat is None:
        return
    if isinstance(compat, list):
        compat = ", ".join(str(x) for x in compat)
    text = str(compat)
    if len(text) > MAX_COMPATIBILITY_LENGTH:
        yield Issue(
            Severity.ERROR,
            f"compatibility exceeds {MAX_COMPATIBILITY_LENGTH} chars "
            f"({len(text)})",
        )


def _check_body(body: str) -> Iterable[Issue]:
    line_count = len(body.splitlines())
    if line_count == 0:
        yield Issue(Severity.WARN, "SKILL.md body is empty")
        return

    if line_count > MAX_BODY_LINES:
        yield Issue(
            Severity.WARN,
            f"SKILL.md body is {line_count} lines "
            f"(recommended: under {MAX_BODY_LINES}). "
            f"Consider splitting into reference files.",
        )
    else:
        yield Issue(Severity.INFO, f"SKILL.md body: {line_count} lines")

    if WINDOWS_PATH_PATTERN.search(body):
        yield Issue(
            Severity.WARN,
            "Body may contain backslash paths. "
            "Use forward slashes for cross-platform compatibility.",
        )


def _check_reference_depth(skill_dir: Path, body: str) -> Iterable[Issue]:
    for _, href in MARKDOWN_LINK_PATTERN.findall(body):
        if href.startswith(("http://", "https://", "#")):
            continue
        ref_path = skill_dir / href
        if not (ref_path.exists() and ref_path.suffix == ".md"):
            continue
        try:
            ref_text = ref_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        nested = [
            target
            for _, target in MARKDOWN_LINK_PATTERN.findall(ref_text)
            if target.endswith(".md")
            and not target.startswith(("http://", "https://"))
        ]
        if nested:
            yield Issue(
                Severity.WARN,
                f"Nested reference: {href} links to {', '.join(nested)}. "
                f"Keep references one level deep from SKILL.md.",
            )


def _check_directory_structure(skill_dir: Path) -> Iterable[Issue]:
    for item in sorted(skill_dir.iterdir()):
        if not item.is_dir() or item.name.startswith("."):
            continue
        if item.name in KNOWN_DIRECTORIES:
            continue
        yield Issue(Severity.INFO, f"Non-standard directory: {item.name}/")


def _check_reference_files(skill_dir: Path) -> Iterable[Issue]:
    refs_dir = skill_dir / "references"
    if not refs_dir.is_dir():
        return
    for ref_file in sorted(refs_dir.glob("*.md")):
        try:
            ref_text = ref_file.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        line_count = len(ref_text.splitlines())
        if line_count <= MAX_REFERENCE_LINES_WITHOUT_TOC:
            continue
        head = ref_text[:500].lower()
        if any(kw in head for kw in TOC_KEYWORDS):
            continue
        yield Issue(
            Severity.WARN,
            f"references/{ref_file.name} is {line_count} lines "
            f"but has no table of contents",
        )


# --- Orchestrator --------------------------------------------------------------


def validate(skill_dir: Path) -> list[Issue]:
    """Run every check and return all issues, ending with a summary INFO line."""
    if not skill_dir.is_dir():
        return [Issue(Severity.ERROR, f"Not a directory: {skill_dir}")]

    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        return [Issue(Severity.ERROR, "SKILL.md not found")]

    try:
        content = skill_md.read_text(encoding="utf-8-sig")
    except OSError as exc:
        return [Issue(Severity.ERROR, f"Cannot read SKILL.md: {exc}")]

    try:
        fm_text, body = split_frontmatter(content)
        fm = parse_yaml(fm_text)
    except FrontmatterError as exc:
        return [Issue(Severity.ERROR, str(exc))]

    if not isinstance(fm, dict):
        return [Issue(Severity.ERROR, "frontmatter must be a YAML mapping")]

    issues: list[Issue] = []
    issues.extend(_check_name(fm, skill_dir))
    issues.extend(_check_description(fm))
    issues.extend(_check_compatibility(fm))
    issues.extend(_check_body(body))
    issues.extend(_check_reference_depth(skill_dir, body))
    issues.extend(_check_directory_structure(skill_dir))
    issues.extend(_check_reference_files(skill_dir))
    issues.append(_summary(issues))
    return issues


def _summary(issues: Iterable[Issue]) -> Issue:
    errors = sum(1 for i in issues if i.severity is Severity.ERROR)
    warns = sum(1 for i in issues if i.severity is Severity.WARN)
    word = "passed" if errors == 0 else "failed"
    return Issue(
        Severity.INFO,
        f"Validation {word}: "
        f"{errors} error{'s' if errors != 1 else ''}, "
        f"{warns} warning{'s' if warns != 1 else ''}",
    )


# --- CLI -----------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="validate_skill.py",
        description="Validate an Agent Skill directory against agentskills.io.",
    )
    parser.add_argument(
        "skill_dir",
        type=Path,
        help="Path to the skill directory to validate.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    issues = validate(args.skill_dir.expanduser().resolve())
    for issue in issues:
        print(issue)
    return 1 if any(i.severity is Severity.ERROR for i in issues) else 0


if __name__ == "__main__":
    sys.exit(main())
