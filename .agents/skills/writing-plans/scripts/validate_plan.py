#!/usr/bin/env python3
"""
Validate an implementation plan produced by the writing-plans skill.

Universal, stack-agnostic checks only. The script is a feedback-loop helper
to be run during Phase 5 of the workflow; it is not a substitute for the
manual philosophy checklist at references/philosophy-checklist.md.

Usage:
    validate_plan.py <path-to-plan.md>

Checks (each maps to a class of defect the agent or a reviewer would catch
by hand):

    - File exists, has the .md extension, lives under .plans/
      with a Plan-{slug}.md filename.
    - Required sections present and non-empty:
        Title heading, TL;DR, Dependency graph,
        at least one Phase, Files Affected,
        Decisions, Plan extensions, Further considerations,
        Philosophy checklist.
    - Phase headings number in strictly ascending order.
    - The terminal phase contains a verification keyword
      (Verification, Verify, Cleanup).
    - Every productive phase (a phase with at least one checkbox step)
      contains a Verify: line.
    - Every productive phase ends with a Constraint Check bullet
      that is not "TBD" or a single word.
    - Implementation steps use the - [ ] checkbox format.
    - No fenced code blocks tagged with a language identifier
      (go, ts, tsx, python, sql, rust, java, etc.).
    - No em-dashes or en-dashes anywhere in the file.
    - No backslash paths inside inline code spans.
    - No oversized fenced code blocks (heuristic for implementation
      rather than signature). Default threshold is 50 lines; pass
      --code-block-limit to override.

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

LANGUAGE_TAGS = {
    "go", "ts", "tsx", "typescript", "javascript", "js", "jsx",
    "python", "py", "sql", "rust", "rs", "java", "kotlin", "kt",
    "swift", "php", "ruby", "rb", "csharp", "cs", "cpp", "c++", "c",
    "scala", "haskell", "hs", "ocaml", "ml", "elixir", "ex", "erlang", "erl",
    "clojure", "clj", "fsharp", "fs", "dart", "lua", "perl", "pl", "r",
    "shell", "bash", "sh", "zsh", "fish", "powershell", "ps1",
}

REQUIRED_SECTIONS = [
    (r"^##\s+TL;DR\s*$", "TL;DR"),
    (r"^##\s+Dependency graph\s*$", "Dependency graph"),
    (r"^##\s+Files Affected\s*$", "Files Affected"),
    (r"^##\s+Decisions\s*$", "Decisions"),
    (r"^##\s+Plan extensions\s*$", "Plan extensions"),
    (r"^##\s+Further considerations\s*$", "Further considerations"),
    (r"^##\s+Philosophy checklist\s*$", "Philosophy checklist"),
]

VERIFY_KEYWORDS = ("verification", "verify", "cleanup")

FILENAME_PATTERN = re.compile(r"^Plan-[\w.\-]+\.md$")
EM_OR_EN_DASH = re.compile(r"[–—]")
PHASE_HEADING = re.compile(r"^##\s+Phase\s+(\d+):\s*(.+?)\s*$", re.MULTILINE)
CHECKBOX = re.compile(r"^-\s*\[\s?[xX]?\s?\]", re.MULTILINE)
CONSTRAINT_CHECK = re.compile(
    r"^-\s*\[\s?[xX]?\s?\]\s*\*\*Constraint Check[^*]*\*\*:?\s*(.+?)$",
    re.MULTILINE,
)
FENCED_BLOCK = re.compile(r"^```([^\n]*)\n(.*?)^```", re.MULTILINE | re.DOTALL)
BACKSLASH_PATH = re.compile(r"`[^`\n]*\\[A-Za-z][^`\n]*`")
NEXT_H2 = re.compile(r"^##\s+", re.MULTILINE)


def section_body(content: str, header_re: re.Pattern[str]) -> str:
    m = header_re.search(content)
    if not m:
        return ""
    start = m.end()
    nxt = NEXT_H2.search(content, pos=start)
    end = nxt.start() if nxt else len(content)
    return content[start:end]


def phase_bodies(content: str) -> list[tuple[int, str, str, str]]:
    """Return [(phase_number, heading, body, body_lower)] for each phase H2."""
    phases: list[tuple[int, str, str, str]] = []
    matches = list(PHASE_HEADING.finditer(content))
    for i, m in enumerate(matches):
        num = int(m.group(1))
        name = m.group(2).strip()
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
        nxt_section = NEXT_H2.search(content, pos=body_start)
        if nxt_section and nxt_section.start() < body_end:
            # Trim to next H2 if it appears before next phase.
            non_phase_h2 = nxt_section.start()
            if i + 1 >= len(matches) or non_phase_h2 < matches[i + 1].start():
                body_end = non_phase_h2
        body = content[body_start:body_end]
        phases.append((num, name, body, body.lower()))
    return phases


def validate(path: Path, code_block_limit: int) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    if not path.exists():
        errors.append(f"File not found: {path}")
        return errors, warnings

    if path.suffix != ".md":
        warnings.append(f"Expected .md extension, got {path.suffix!r}")

    if path.parent.name != ".plans":
        warnings.append(
            f"Plan file should live under .plans/, found in {path.parent.name!r}"
        )

    if not FILENAME_PATTERN.match(path.name):
        warnings.append(
            f"Filename {path.name!r} does not match Plan-{{slug}}.md pattern"
        )

    content = path.read_text(encoding="utf-8")

    # Title heading
    if not re.search(r"^#\s+Plan:\s+", content, re.MULTILINE):
        errors.append("Missing top-level title heading '# Plan: ...'")

    # Required sections
    for pattern, label in REQUIRED_SECTIONS:
        header_re = re.compile(pattern, re.MULTILINE)
        if not header_re.search(content):
            errors.append(f"Missing section: '{label}'")
            continue
        body = section_body(content, header_re)
        cleaned = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
        if not cleaned:
            errors.append(f"Empty section: '{label}'")

    # At least one phase
    phases = phase_bodies(content)
    if not phases:
        errors.append(
            "No Phase sections found. A plan MUST contain at least one "
            "'## Phase N: <Name>' heading."
        )

    # Phase numbering strictly increasing
    prev_num = 0
    for num, name, _, _ in phases:
        if num <= prev_num:
            errors.append(
                f"Phase numbering out of order: 'Phase {num}: {name}' appears "
                f"after phase {prev_num}. Phase numbers MUST strictly increase."
            )
            break
        prev_num = num

    # Terminal phase contains verification keyword
    if phases:
        last_num, last_name, _, _ = phases[-1]
        if not any(kw in last_name.lower() for kw in VERIFY_KEYWORDS):
            errors.append(
                f"Terminal phase 'Phase {last_num}: {last_name}' does not "
                "contain a verification keyword. The last phase MUST be a "
                "verification or cleanup phase."
            )

    # Productive phases must have Verify: and Constraint Check
    for num, name, body, body_lower in phases:
        is_terminal_verify = any(kw in name.lower() for kw in VERIFY_KEYWORDS)
        checkboxes_in_phase = CHECKBOX.findall(body)
        if not checkboxes_in_phase:
            # Prose-only phase; skip the per-phase gates.
            continue
        if is_terminal_verify:
            # Terminal phase is verification by construction;
            # do not require an extra Verify: line or Constraint Check.
            continue
        if "verify:" not in body_lower and "**verify:**" not in body_lower:
            errors.append(
                f"Phase {num} ('{name}') has checkbox steps but no 'Verify:' "
                "line. Every productive phase MUST include at least one verify "
                "gate naming a specific runnable command with a named target."
            )
        cc_matches = CONSTRAINT_CHECK.findall(body)
        if not cc_matches:
            errors.append(
                f"Phase {num} ('{name}') ends without a Constraint Check "
                "bullet. Every productive phase MUST close with "
                "'- [ ] **Constraint Check (Phase N):** <assertion>'."
            )
        else:
            for cc_text in cc_matches:
                cc_clean = cc_text.strip()
                if cc_clean.lower() in {"tbd", "todo", "n/a", "none"}:
                    errors.append(
                        f"Phase {num} ('{name}') has a placeholder Constraint "
                        f"Check ({cc_clean!r}). Name the specific boundary the "
                        "phase honors."
                    )
                elif len(cc_clean.split()) < 3:
                    warnings.append(
                        f"Phase {num} ('{name}') Constraint Check is very short "
                        f"({cc_clean!r}). Verify it names a specific invariant."
                    )

    # Language-tagged code fences
    for m in FENCED_BLOCK.finditer(content):
        tag = m.group(1).strip().lower()
        block_body = m.group(2)
        line_no = content.count("\n", 0, m.start()) + 1
        if tag in LANGUAGE_TAGS:
            errors.append(
                f"Line {line_no}: fenced code block tagged with language "
                f"identifier '{tag}'. Plans MUST NOT use language tags; "
                "the tag signals runnable code. Use inline signatures in "
                "prose or untagged pseudo-code."
            )
        # Oversized block heuristic regardless of tag.
        body_lines = block_body.count("\n")
        if body_lines > code_block_limit:
            warnings.append(
                f"Line {line_no}: fenced code block is {body_lines} lines "
                f"(limit {code_block_limit}). Verify the block is signature, "
                "schema, or pseudo-code, not implementation."
            )

    # Em-dashes and en-dashes
    for m in EM_OR_EN_DASH.finditer(content):
        line_no = content.count("\n", 0, m.start()) + 1
        char_name = "em-dash" if m.group() == "—" else "en-dash"
        errors.append(
            f"Line {line_no}: contains {char_name}; replace with comma, "
            "period, parenthesis, semicolon, or colon."
        )

    # Backslash paths in code spans
    for m in BACKSLASH_PATH.finditer(content):
        line_no = content.count("\n", 0, m.start()) + 1
        warnings.append(
            f"Line {line_no}: backslash path in code span: {m.group()!r}; "
            "use forward slashes."
        )

    # Heuristic: at least one checkbox somewhere
    if not CHECKBOX.findall(content):
        errors.append(
            "No Markdown checkboxes found. Every implementation step MUST "
            "use the format '- [ ] **N.M** <step title>'."
        )

    return errors, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a writing-plans plan.")
    parser.add_argument("plan_path", help="Path to the plan markdown file.")
    parser.add_argument(
        "--code-block-limit",
        type=int,
        default=50,
        help="Maximum lines per fenced code block before warning (default 50).",
    )
    args = parser.parse_args()

    path = Path(args.plan_path).resolve()
    print(f"Validating: {path}")
    print()

    errors, warnings = validate(path, args.code_block_limit)

    for w in warnings:
        print(f"  [!] {w}")
    for e in errors:
        print(f"  [x] {e}")

    print()
    if errors:
        print(f"FAIL: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1
    print(f"PASS: 0 error(s), {len(warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
