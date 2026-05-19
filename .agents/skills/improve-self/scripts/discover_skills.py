#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""
Discover installed Agent Skills across vendor directories.

Scans `.{vendor}/skills/` under the project root and `~/.{vendor}/skills/`
in the user's home, extracts each skill's `name` and `description` from
its frontmatter, and prints the result as a structured record per skill
so the agent can compare existing descriptions against a candidate gap
before proposing a new skill.

The caller MUST pass `--vendors`. There is no implicit default — the
list is supplied by the agent after enumerating which `.{name}/skills/`
directories actually exist on the filesystem. This avoids scanning
vendor prefixes the current host does not use, and surfaces obvious
typos (an unknown vendor name triggers an exit-2 error so the agent
can self-correct).

Output record fields (stable contract):
    name         Value of the `name:` frontmatter key.
    category     Optional taxonomy label, read from `metadata.category`
                 first (project convention) and a top-level `category:`
                 second. Emitted as an empty section
                 (`<category></category>` / `"category": ""`) when not
                 present, so the field is always part of the record.
    description  Value of the `description:` frontmatter key (folded).

Three optional fields are omitted from the default output and added
only when the caller opts in. They share a single mechanism — the
``--with-<field>`` flag — and slot into the record at canonical
positions (``type`` before ``name``; ``agent`` between them; ``path``
at the end):

    type         "project" if the skill lives under the project root,
                 "user" if it lives under the user's home. Emitted
                 only when ``--with-type`` is set. Pass it when the
                 caller needs to distinguish project-local skills
                 from user-global ones.
    agent        Vendor prefix (``.{agent}/skills/``). Emitted only
                 when ``--with-agent`` is set. Useful for cross-vendor
                 disambiguation; rarely needed when answering "what
                 skills exist and what do they do?".
    path         Path to the SKILL.md file. Emitted only when
                 ``--with-path`` is set. Project-scope entries are
                 emitted relative to the project root
                 (``.claude/skills/foo/SKILL.md``); user-scope entries
                 are abbreviated with a leading ``~``
                 (``~/.claude/skills/foo/SKILL.md``); anything
                 discovered through a symlink that escapes both roots
                 stays absolute. The path shape itself signals scope
                 (leading ``~`` vs none), so ``--with-path`` is useful
                 without ``--with-type``.

Precedence:
    When the same skill `name` exists in both user (home) and project
    scopes, the user entry wins and the project entry is omitted from
    the output. This matches what every supported agent actually loads
    at runtime when both are present.

Ordering:
    Output is sorted alphabetically by ``--order-by`` (default:
    ``category``), with ``name`` as a stable secondary key. The agent
    treats every returned skill with equal priority, so a deterministic
    alphabetical scan is more useful than discovery order. All fields
    in ``ALL_FIELDS`` are valid choices, including opt-in ones that
    are not in the rendered output.

Usage:
    discover_skills.py --vendors VENDORS [options]
    discover_skills.py --list-supported

Options:
    --vendors VENDORS    Comma-separated vendor names to scan. REQUIRED.
                         Each name must be in the supported set
                         (see --list-supported).
    --list-supported     Print the supported vendor names and exit.
    --project-root PATH  Project root to scan (default: current dir).
    --no-project         Skip project-local `.{vendor}/skills/`.
    --no-home            Skip `~/.{vendor}/skills/`.
    --format FORMAT      Output format: xml (default), json, markdown,
                         csv (RFC 4180 with header row).
    --order-by FIELD     Sort the result alphabetically by this field
                         (default: category). All ALL_FIELDS are valid
                         choices; `name` is the stable secondary key.
    --with-type          Include the `type` field (project|user scope).
                         Omitted by default — pass when project vs
                         user matters to the caller.
    --with-agent         Include the `agent` field (vendor prefix).
                         Omitted by default — useful only when
                         cross-vendor disambiguation matters.
    --with-path          Include the `path` field (SKILL.md location).
                         Omitted by default — pass only when the
                         caller needs to open or edit the SKILL.md.
    --quiet              Suppress warnings about malformed SKILL.md.

Exit codes:
    0  Discovery completed (zero or more skills found).
    1  Recoverable error (some SKILL.md unreadable; results still printed).
    2  Usage error (missing/empty/unsupported --vendors, bad flags).

Examples:
    discover_skills.py --vendors agents,claude
    discover_skills.py --vendors github,copilot --format json --no-home
    discover_skills.py --list-supported

The script has zero runtime dependencies and works on Python 3.9+. It
parses only the subset of YAML used in skill frontmatter: plain scalars,
single/double-quoted scalars, and `>`/`|` block scalars for the
description. Flow style is not supported.
"""

from __future__ import annotations

import argparse
import csv
import enum
import io
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Sequence


# --- Public constants ---------------------------------------------------------

# The set of vendor names this script accepts as `--vendors`. Vendor names
# differ between project and home scope on some platforms (notably GitHub
# Copilot uses `.github/skills/` for project skills but `.copilot/skills/`
# for user-level skills). All recognised names live in one set; the agent
# decides which ones to pass based on what actually exists on the host.
SUPPORTED_VENDORS: frozenset[str] = frozenset({
    "agents",       # OpenAI Codex; emerging cross-platform convention
    "claude",       # Claude Code
    "cursor",       # Cursor
    "gemini",       # Gemini CLI
    "github",       # VS Code / GitHub Copilot (project scope)
    "copilot",      # GitHub Copilot (home scope)
    "opencode",     # OpenCode
    "antigravity",  # Antigravity
    "windsurf",     # Windsurf
})

DEFAULT_FORMAT: str = "xml"
DEFAULT_ORDER_BY: str = "category"
FRONTMATTER_DELIMITER: str = "---"


# --- Data model ---------------------------------------------------------------


class Scope(enum.Enum):
    """Where a skill was discovered.

    Output field name is ``type`` (per agent-facing contract); the value is
    ``project`` when the skill lives under the project root and ``user``
    when it lives in the home directory.
    """

    PROJECT = "project"
    USER = "user"


def _abbreviate_home(path: Path, home: Path | None = None) -> str:
    """Return ``path`` with the user's home directory collapsed to ``~``.

    Keeps the agent-facing output free of the literal home-directory name
    (e.g. ``/home/alice``) without losing the ability to round-trip into
    a shell: every supported shell expands a leading ``~`` to ``$HOME``.
    Paths that do not sit under the user's home are returned as-is.
    """
    home = home or Path.home()
    try:
        relative = path.relative_to(home)
    except ValueError:
        return str(path)
    return "~" if str(relative) == "." else f"~/{relative}"


@dataclass(frozen=True)
class SkillEntry:
    """A successfully-discovered skill.

    Internal field names (``vendor``, ``scope``) are mapped to the
    agent-facing field names (``agent``, ``type``) at serialization time.

    ``project_root`` is populated for project-scope entries so the path
    field of the output can be rendered relative to the project root
    (``.claude/skills/foo/SKILL.md``) instead of an absolute or
    home-abbreviated path. The ``type`` field already disambiguates
    project from user, so a relative project path remains unambiguous.
    """

    vendor: str
    scope: Scope
    path: Path
    name: str
    description: str
    category: str = ""
    project_root: Path | None = None

    def as_record(self) -> dict[str, str]:
        """Return the agent-facing record with externally-stable keys."""
        return {
            "type": self.scope.value,
            "agent": self.vendor,
            "name": self.name,
            "category": self.category,
            "description": self.description,
            "path": self._render_path(),
        }

    def _render_path(self) -> str:
        """Render the path per scope: relative for project, ~-abbreviated for user."""
        if self.scope is Scope.PROJECT and self.project_root is not None:
            try:
                return str(self.path.relative_to(self.project_root))
            except ValueError:
                pass  # symlink out of the project root → fall through to absolute
        return _abbreviate_home(self.path)


@dataclass(frozen=True)
class DiscoveryError:
    """A SKILL.md that could not be parsed."""

    path: Path
    reason: str


# --- Frontmatter parser -------------------------------------------------------


class FrontmatterError(ValueError):
    """Raised when frontmatter is missing or required fields cannot be read."""


def read_frontmatter_fields(skill_md: Path) -> tuple[str, str, str]:
    """Return ``(name, description, category)`` from a SKILL.md frontmatter.

    ``name`` and ``description`` are required (top-level keys); raises
    ``FrontmatterError`` if either is missing or the file cannot be read.

    ``category`` is read from the project convention ``metadata.category``
    and falls back to a top-level ``category:`` for skills that omit the
    ``metadata`` block. Returns the empty string if neither is present —
    category is an optional taxonomy field, not a required one.
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
    category = (
        _extract_nested_scalar(block, "metadata", "category")
        or _extract_scalar(block, "category")
    )

    if not name:
        raise FrontmatterError("missing or empty 'name' field")
    if not description:
        raise FrontmatterError("missing or empty 'description' field")
    return name, description, category


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


def _extract_nested_scalar(block: str, parent: str, child: str) -> str:
    """Find ``child:`` nested one level under top-level ``parent:`` and return its value.

    Walks lines after a zero-indent ``parent:`` header, accepts the first
    indented ``child:`` it finds at consistent indentation, and stops at the
    next zero-indent key. Returns an empty string if either the parent
    block or the nested key is absent.
    """
    lines = block.splitlines()
    parent_prefix = f"{parent}:"
    in_parent = False
    nested_indent: int | None = None

    for raw in lines:
        stripped = raw.lstrip(" ")
        if stripped == "" or stripped.startswith("#"):
            continue
        indent = len(raw) - len(stripped)

        if not in_parent:
            if indent == 0 and stripped.startswith(parent_prefix):
                in_parent = True
            continue

        if indent == 0:
            return ""  # left the parent mapping

        if nested_indent is None:
            nested_indent = indent
        if indent != nested_indent:
            continue

        child_prefix = f"{child}:"
        if stripped.startswith(child_prefix):
            rest = stripped[len(child_prefix):].lstrip()
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
                project_root=project_root,
            )
        if include_home:
            yield from _scan_directory(
                home / f".{vendor}" / "skills",
                vendor=vendor,
                scope=Scope.USER,
                project_root=None,
            )


def _scan_directory(
    skills_root: Path, vendor: str, scope: Scope,
    project_root: Path | None = None,
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
            name, description, category = read_frontmatter_fields(skill_md)
        except FrontmatterError as exc:
            yield DiscoveryError(path=skill_md, reason=str(exc))
            continue
        yield SkillEntry(
            vendor=vendor,
            scope=scope,
            path=skill_md,
            name=name,
            description=description,
            category=category,
            project_root=project_root,
        )


# --- Precedence ---------------------------------------------------------------


def sort_entries(
    entries: Sequence[SkillEntry], order_by: str,
) -> list[SkillEntry]:
    """Return ``entries`` sorted alphabetically by ``order_by``.

    The agent treats every returned skill with equal priority, so a
    deterministic, easy-to-scan order is more useful than discovery order.
    ``name`` is used as a stable secondary key — Python's ``sorted`` is
    stable, so when the primary key matches (e.g. two skills in the same
    category), entries fall back to alphabetical name order.

    ``order_by`` must be a key produced by ``SkillEntry.as_record()``;
    callers (the CLI parser via ``choices``) are expected to validate it
    before calling this function.
    """
    return sorted(
        entries,
        key=lambda e: (e.as_record()[order_by], e.name),
    )


def resolve_precedence(entries: Sequence[SkillEntry]) -> list[SkillEntry]:
    """Apply 'user scope wins over project scope on name collisions'.

    When the same skill ``name`` appears in both the user's home and the
    project, the home version takes precedence because that is what every
    supported agent actually loads when both are present. Emitting both
    would mislead the agent into believing the project version is also
    visible at runtime.

    Rule, applied per unique ``name``:

    * If at least one entry has ``scope=USER``, keep only the USER entries
      and drop every PROJECT entry that shares that name.
    * Otherwise keep all entries for that name (typically just one, but
      multi-vendor project installs are preserved as-is).

    The original discovery order is preserved among the kept entries so
    downstream formatters render deterministic output.
    """
    grouped: dict[str, list[SkillEntry]] = {}
    for entry in entries:
        grouped.setdefault(entry.name, []).append(entry)

    keep: set[Path] = set()
    for siblings in grouped.values():
        user_entries = [e for e in siblings if e.scope is Scope.USER]
        winners = user_entries if user_entries else siblings
        keep.update(e.path for e in winners)

    return [e for e in entries if e.path in keep]


# --- Formatters ---------------------------------------------------------------

Formatter = Callable[[Sequence[SkillEntry], Sequence[str]], str]

# Every field SkillEntry.as_record() produces, in canonical output order.
# Formatters pick a subset at call time so the on-the-wire schema can shrink
# without changing the data model.
ALL_FIELDS: tuple[str, ...] = (
    "type", "agent", "name", "category", "description", "path",
)

# Fields that are omitted from the default output and emitted only when the
# matching ``--with-<field>`` flag is set. The default record answers the
# common "what skills exist, classified how, doing what?" question with
# nothing more than name + category + description; the entries below are
# extra detail the caller asks for explicitly.
#
# Maps each opt-in field name to the help string of its CLI flag. Adding a
# new opt-in field is a single-line addition here plus a placement in
# ALL_FIELDS for canonical ordering; the CLI parser and the main runtime
# pick it up automatically.
OPT_IN_FIELDS: dict[str, str] = {
    "type": (
        "Include the <type> field (project|user scope) in the output. "
        "Omitted by default; pass when the caller needs to distinguish "
        "project-local skills from user-global ones."
    ),
    "agent": (
        "Include the <agent> field (vendor prefix) in the output. "
        "Omitted by default; useful only when cross-vendor "
        "disambiguation matters."
    ),
    "path": (
        "Include the <path> field (SKILL.md location) in the output. "
        "Omitted by default; useful when the caller needs to open or "
        "edit the discovered SKILL.md files."
    ),
}


def _opt_in_flag(field: str) -> str:
    """Return the CLI flag name for an opt-in field (``--with-<field>``)."""
    return f"--with-{field}"


def _opt_in_attr(field: str) -> str:
    """Return the argparse attribute name for an opt-in field's flag."""
    return f"with_{field.replace('-', '_')}"

# Default agent-facing schema: ALL_FIELDS minus the opt-in ones.
DEFAULT_FIELDS: tuple[str, ...] = tuple(
    f for f in ALL_FIELDS if f not in OPT_IN_FIELDS
)


def _select_fields(opt_ins: set[str]) -> tuple[str, ...]:
    """Return the active field list given the set of opted-in optional fields.

    Preserves the canonical order from ``ALL_FIELDS`` so output schema is
    deterministic regardless of which flags the caller passes.
    """
    return tuple(
        f for f in ALL_FIELDS if f not in OPT_IN_FIELDS or f in opt_ins
    )


def _xml_escape(text: str) -> str:
    """Escape the five characters that may not appear raw inside XML text."""
    return (
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&apos;")
    )


def format_xml(entries: Sequence[SkillEntry], fields: Sequence[str]) -> str:
    """Render entries as ``<skills><skill>…</skill></skills>``.

    XML is the default agent-facing format because it tolerates freeform
    description text without escaping headaches, is unambiguous to parse,
    and matches Anthropic's published guidance on structured prompt inputs.
    """
    if not entries:
        return "<skills/>"
    out: list[str] = ["<skills>"]
    for entry in entries:
        record = entry.as_record()
        out.append("  <skill>")
        for field in fields:
            out.append(f"    <{field}>{_xml_escape(record[field])}</{field}>")
        out.append("  </skill>")
    out.append("</skills>")
    return "\n".join(out)


def format_json(entries: Sequence[SkillEntry], fields: Sequence[str]) -> str:
    """Render entries as a JSON array of records keyed by ``fields``."""
    return json.dumps(
        [{f: e.as_record()[f] for f in fields} for e in entries],
        indent=2,
        ensure_ascii=False,
    )


def format_markdown(entries: Sequence[SkillEntry], fields: Sequence[str]) -> str:
    """Render entries as a Markdown table for human review."""
    if not entries:
        return "_(no skills discovered)_"
    header = "| " + " | ".join(fields) + " |"
    divider = "|" + "|".join("---" for _ in fields) + "|"
    rows = [header, divider]
    for entry in entries:
        record = entry.as_record()
        cells = [
            record[f].replace("|", "\\|").replace("\n", " ")
            for f in fields
        ]
        # Wrap the name in backticks for readability.
        if "name" in fields:
            cells[fields.index("name")] = f"`{record['name']}`"
        rows.append("| " + " | ".join(cells) + " |")
    return "\n".join(rows)


def format_csv(entries: Sequence[SkillEntry], fields: Sequence[str]) -> str:
    """Render entries as RFC 4180 CSV with a header row.

    Delegates quoting and escaping to the standard library's ``csv``
    module (``QUOTE_MINIMAL`` — only fields containing a comma, quote, or
    newline are quoted; embedded quotes are doubled). On empty input the
    header row is still emitted so the schema is communicated.
    """
    buf = io.StringIO()
    writer = csv.DictWriter(
        buf,
        fieldnames=list(fields),
        quoting=csv.QUOTE_MINIMAL,
        lineterminator="\n",
    )
    writer.writeheader()
    for entry in entries:
        record = entry.as_record()
        writer.writerow({f: record[f] for f in fields})
    return buf.getvalue().rstrip("\n")


FORMATTERS: dict[str, Formatter] = {
    "xml": format_xml,
    "json": format_json,
    "markdown": format_markdown,
    "csv": format_csv,
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
        epilog=(
            "Required: --vendors. Run --list-supported to see accepted names. "
            "Example: discover_skills.py --vendors agents,claude,github"
        ),
    )
    parser.add_argument(
        "--vendors",
        default=None,
        help=(
            "Comma-separated vendor names to scan. REQUIRED unless "
            "--list-supported is used. Each name must be in the "
            "supported set (see --list-supported)."
        ),
    )
    parser.add_argument(
        "--list-supported",
        action="store_true",
        help="Print the supported vendor names (one per line) and exit.",
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
        "--order-by",
        default=DEFAULT_ORDER_BY,
        choices=ALL_FIELDS,
        help=(
            "Sort the result alphabetically by this field, with `name` "
            f"as a stable tiebreaker (default: {DEFAULT_ORDER_BY}). "
            "All fields are valid choices, including opt-in ones that "
            "are not in the rendered output — the sort still applies."
        ),
    )
    for field, help_text in OPT_IN_FIELDS.items():
        parser.add_argument(
            _opt_in_flag(field), action="store_true", help=help_text,
        )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress warnings about malformed SKILL.md files.",
    )
    return parser


def _parse_vendors(raw: str) -> list[str]:
    return [_validate_vendor(v) for v in raw.split(",") if v.strip()]


def _dedupe_preserve_order(vendors: Sequence[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for v in vendors:
        if v not in seen:
            seen.add(v)
            out.append(v)
    return out


def _supported_hint() -> str:
    return f"supported vendors: {', '.join(sorted(SUPPORTED_VENDORS))}"


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)

    if args.list_supported:
        for vendor in sorted(SUPPORTED_VENDORS):
            print(vendor)
        return 0

    if args.vendors is None:
        print(
            "error: --vendors is required "
            "(or use --list-supported to enumerate accepted names)",
            file=sys.stderr,
        )
        print(_supported_hint(), file=sys.stderr)
        return 2

    try:
        vendors = _parse_vendors(args.vendors)
    except argparse.ArgumentTypeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if not vendors:
        print(
            "error: --vendors must contain at least one non-empty name",
            file=sys.stderr,
        )
        print(_supported_hint(), file=sys.stderr)
        return 2

    unsupported = [v for v in vendors if v not in SUPPORTED_VENDORS]
    if unsupported:
        print(
            f"error: unsupported vendor(s): {', '.join(sorted(set(unsupported)))}",
            file=sys.stderr,
        )
        print(_supported_hint(), file=sys.stderr)
        return 2

    if args.no_project and args.no_home:
        print(
            "error: --no-project and --no-home cancel each other",
            file=sys.stderr,
        )
        return 2

    vendors = _dedupe_preserve_order(vendors)

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

    entries = resolve_precedence(entries)
    entries = sort_entries(entries, args.order_by)

    opt_ins = {f for f in OPT_IN_FIELDS if getattr(args, _opt_in_attr(f))}
    fields = _select_fields(opt_ins)
    print(FORMATTERS[args.format](entries, fields))

    if errors and not args.quiet:
        print(file=sys.stderr)
        for err in errors:
            print(f"warning: {err.path}: {err.reason}", file=sys.stderr)

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
