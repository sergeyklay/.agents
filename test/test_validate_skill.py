#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

# Tests live outside .agents/skills so they never ship to a host; the
# module under test is imported from the skill it belongs to.
REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / ".agents/skills/make-skill/scripts"))

from validate_skill import (  # noqa: E402
    MAX_BODY_BYTES,
    SPEC_FIELDS,
    Issue,
    Severity,
    validate,
)

FRONTMATTER = (
    "---\n"
    "name: fixture-skill\n"
    "description: Fixture skill. Use when testing the body-size gate.\n"
    "---\n"
)

DESCRIPTION = "Fixture skill. Use when testing frontmatter field rules."
BODY = "# Fixture\n\nOne paragraph of body text.\n"


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
    """Pins MAX_BODY_BYTES to its derivation of 5000 tokens x 3.5 bytes.

    The body budget comes from <https://agentskills.io/specification> and from
    make-skill's own SKILL.md under "Progressive Disclosure"; the bytes-per-token
    figure from Anthropic's glossary. Every other test here builds its fixture
    from the constant, so they stay green whatever it is changed to.
    """

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
                "budget and update the docstring above it; do not edit this "
                "number to match a new constant."
            ),
        )


class FrontmatterFixture(unittest.TestCase):
    """Writes a minimal valid skill and lets a test add frontmatter lines."""

    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.skill_dir = Path(self.tempdir.name) / "fixture-skill"
        self.skill_dir.mkdir()

    def _validate(self, *extra_lines: str) -> list[Issue]:
        frontmatter = "\n".join(
            ("---", "name: fixture-skill", f"description: {DESCRIPTION}")
            + extra_lines
            + ("---",)
        )
        skill_md = self.skill_dir / "SKILL.md"
        skill_md.write_text(f"{frontmatter}\n{BODY}", encoding="utf-8")
        return validate(self.skill_dir)

    def _errors(self, *extra_lines: str) -> list[str]:
        return [
            issue.message
            for issue in self._validate(*extra_lines)
            if issue.severity is Severity.ERROR
        ]

    def _infos(self, *extra_lines: str) -> list[str]:
        return [
            issue.message
            for issue in self._validate(*extra_lines)
            if issue.severity is Severity.INFO
        ]


class AllowedToolsTypeTest(FrontmatterFixture):
    # The spec types allowed-tools as "a space-separated string of tools that
    # are pre-approved to run" <https://agentskills.io/specification>, and the
    # reference validator declares it Optional[str]. Claude Code additionally
    # tolerates a YAML list, so the list form passes there and fails wherever
    # the spec is enforced.
    def test_space_separated_string_passes(self) -> None:
        self.assertEqual(self._errors("allowed-tools: Bash(git:*) Read"), [])

    def test_yaml_list_is_rejected(self) -> None:
        self.assertEqual(
            self._errors("allowed-tools:", "  - Read", "  - Grep"),
            ["allowed-tools must be a space-separated string, not a YAML list"],
        )

    def test_mapping_is_rejected(self) -> None:
        self.assertEqual(
            self._errors("allowed-tools:", "  bash: true"),
            ["allowed-tools must be a space-separated string (got dict)"],
        )


class MetadataShapeTest(FrontmatterFixture):
    # The spec defines metadata as "a map from string keys to string values".
    def test_string_values_pass(self) -> None:
        self.assertEqual(
            self._errors("metadata:", "  author: example-org", '  version: "1.0"'),
            [],
        )

    def test_scalar_metadata_is_rejected(self) -> None:
        self.assertEqual(
            self._errors("metadata: example-org"),
            ["metadata must be a map from string keys to string values"],
        )

    def test_non_string_value_is_rejected(self) -> None:
        self.assertEqual(
            self._errors("metadata:", "  tags:", "    - one", "    - two"),
            ["metadata.tags must be a string value (got list)"],
        )


class SpecFieldTest(FrontmatterFixture):
    # Claude Code accepts roughly twenty frontmatter fields; claude.ai uploads,
    # the Skills API and package_skill.py accept only the six the spec defines
    # and fail the whole file on anything else. The notice is informational
    # because a deliberate single-vendor skill is a supported choice.
    def test_the_six_spec_fields_are_silent(self) -> None:
        self.assertEqual(
            [message for message in self._infos() if "outside the spec" in message],
            [],
        )

    def test_a_vendor_field_is_reported(self) -> None:
        messages = [
            message
            for message in self._infos("disable-model-invocation: true")
            if "outside the spec" in message
        ]

        self.assertEqual(len(messages), 1)
        self.assertIn("Fields outside the spec: disable-model-invocation.", messages[0])

    def test_the_reported_field_list_is_sorted(self) -> None:
        messages = [
            message
            for message in self._infos("version: 1.0", "argument-hint: '[scope]'")
            if "outside the spec" in message
        ]

        self.assertEqual(len(messages), 1)
        self.assertIn("Fields outside the spec: argument-hint, version.", messages[0])


class SpecFieldSetTest(unittest.TestCase):
    # The set is copied from <https://agentskills.io/specification>, and both
    # reference implementations agree with it: skills-ref's ALLOWED_FIELDS and
    # Anthropic's quick_validate.py ALLOWED_PROPERTIES list the same six.
    # Pinning it keeps a later edit from quietly widening what counts as
    # portable frontmatter.
    def test_the_spec_defines_exactly_these_six_fields(self) -> None:
        self.assertEqual(
            SPEC_FIELDS,
            frozenset(
                {
                    "allowed-tools",
                    "compatibility",
                    "description",
                    "license",
                    "metadata",
                    "name",
                }
            ),
        )


if __name__ == "__main__":
    unittest.main()
