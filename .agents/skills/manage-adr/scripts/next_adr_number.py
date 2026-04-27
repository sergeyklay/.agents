#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""Output the next available ADR number(s) in docs/decisions/.

By default, resolves docs/decisions/ relative to this script's own
location, so it works regardless of the current working directory. Pass
--decision-dir to override and scan a different directory.

Usage:
    next_adr_number.py                          # prints one number, e.g. 0004
    next_adr_number.py --count 3                # prints three numbers
    next_adr_number.py --decision-dir path/to   # scan a custom directory

Exit codes:
    0  success
    1  decisions directory not found
    2  usage error (e.g. --count < 1)

Zero runtime dependencies. Works on Python 3.9+.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# scripts/ → manage-adr/ → skills/ → .claude/ → <project root>/docs/decisions
DEFAULT_DECISIONS_DIR = (
    Path(__file__).resolve().parents[4] / "docs" / "decisions"
)

ADR_FILENAME_PATTERN = re.compile(r"^(\d{4})-.+\.md$")


def highest_existing_number(decisions_dir: Path) -> int:
    """Return the largest 4-digit ADR prefix in decisions_dir, or 0."""
    max_num = 0
    for entry in decisions_dir.iterdir():
        if not entry.is_file():
            continue
        match = ADR_FILENAME_PATTERN.match(entry.name)
        if match is None:
            continue
        num = int(match.group(1))
        if num > max_num:
            max_num = num
    return max_num


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="next_adr_number.py",
        description=(
            "Output the next available ADR number(s) in docs/decisions/."
        ),
    )
    parser.add_argument(
        "--count",
        type=int,
        default=1,
        help="Number of sequential ADR numbers to emit (default: 1).",
    )
    parser.add_argument(
        "--decision-dir",
        type=Path,
        default=None,
        help=(
            "Directory to scan for existing ADRs (default: docs/decisions/ "
            "resolved relative to this script)."
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)

    if args.count < 1:
        print(
            f"Error: --count must be >= 1, got {args.count}",
            file=sys.stderr,
        )
        return 2

    decisions_dir = (
        args.decision_dir.expanduser().resolve()
        if args.decision_dir is not None
        else DEFAULT_DECISIONS_DIR
    )

    if not decisions_dir.is_dir():
        print(
            f"Error: decisions directory not found at {decisions_dir}",
            file=sys.stderr,
        )
        return 1

    start = highest_existing_number(decisions_dir) + 1
    for i in range(args.count):
        print(f"{start + i:04d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
