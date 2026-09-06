#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "scripts"))

from validate_skill import MAX_BODY_BYTES, Issue, Severity, validate  # noqa: E402

FRONTMATTER = (
    "---\n"
    "name: fixture-skill\n"
    "description: Fixture skill. Use when testing the body-size gate.\n"
    "---\n"
)


class BodyByteCeilingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.skill_dir = Path(self.tempdir.name) / "fixture-skill"
        self.skill_dir.mkdir()

    def _byte_warnings(self, body: str) -> list[Issue]:
        skill_md = self.skill_dir / "SKILL.md"
        skill_md.write_bytes((FRONTMATTER + body).encode("utf-8"))
        return [
            issue
            for issue in validate(self.skill_dir)
            if issue.severity is Severity.WARN and "bytes" in issue.message
        ]

    def test_body_under_the_ceiling_is_not_flagged(self) -> None:
        self.assertEqual(self._byte_warnings("x" * (MAX_BODY_BYTES - 1)), [])

    def test_body_exactly_at_the_ceiling_is_not_flagged(self) -> None:
        self.assertEqual(self._byte_warnings("x" * MAX_BODY_BYTES), [])

    def test_body_over_the_ceiling_is_flagged_once_with_its_size(self) -> None:
        warnings = self._byte_warnings("x" * (MAX_BODY_BYTES + 1))

        self.assertEqual(len(warnings), 1)
        self.assertEqual(
            warnings[0].message,
            f"SKILL.md body is {MAX_BODY_BYTES + 1} bytes "
            f"(recommended: under {MAX_BODY_BYTES}). "
            f"Consider splitting into reference files.",
        )

    def test_the_ceiling_counts_bytes_not_characters(self) -> None:
        body = "é" * (MAX_BODY_BYTES // 2 + 1)

        self.assertLess(len(body), MAX_BODY_BYTES)
        self.assertEqual(len(self._byte_warnings(body)), 1)


class BodyByteCeilingValueTest(unittest.TestCase):
    # The ceiling is derived, not chosen. The agentskills.io specification
    # <https://agentskills.io/specification> and make-skill's own SKILL.md
    # (section "Progressive Disclosure") both put the SKILL.md body budget at
    # under 5000 tokens, and Anthropic's glossary puts a token at roughly 3.5
    # English characters, so 5000 x 3.5 = 17500 bytes. Pinning the value keeps
    # the gate honest: the other tests here fix the comparison as strict, but
    # every one of them derives its fixture from MAX_BODY_BYTES, so they stay
    # green no matter what the constant is changed to.
    def test_the_ceiling_matches_its_documented_derivation(self) -> None:
        self.assertEqual(
            MAX_BODY_BYTES,
            17_500,
            msg=(
                "MAX_BODY_BYTES no longer matches its documented derivation "
                "of 5000 tokens x 3.5 bytes per token. This gate exists so "
                "that oversized bodies keep being caught after the cleanup "
                "that introduced it, and a ceiling that can be loosened "
                "silently catches nothing. Re-derive the value from the token "
                "budget and update the comment above it; do not edit this "
                "number to match a new constant."
            ),
        )


if __name__ == "__main__":
    unittest.main()
