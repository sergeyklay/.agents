#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from typing import cast

# Tests live outside .agents/skills so they never ship to a host; the
# module under test is imported from the skill it belongs to.
REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / ".agents/skills/babysit-pr/scripts"))

from fetch_pr_comments import (  # noqa: E402
    build_payload,
    digest_review,
    suppressed_blocks,
    verdict_from_body,
)

FIXTURE = Path(__file__).resolve().parent / "testdata" / "babysit-pr-pr57.json"


def _load_fixture() -> dict[str, object]:
    with FIXTURE.open(encoding="utf-8") as handle:
        return cast("dict[str, object]", json.load(handle))


def _as_list(value: object) -> list[object]:
    return cast("list[object]", value)


def _as_dict(value: object) -> dict[str, object]:
    return cast("dict[str, object]", value)


class Pr57PayloadTest(unittest.TestCase):
    """Assertions against a frozen capture of sergeyklay/.agents PR #57.

    Bodies are verbatim, so the real bot output is exercised offline."""

    def setUp(self) -> None:
        fixture = _load_fixture()
        self.payload = build_payload(
            cast("int", fixture["pr"]),
            _as_list(fixture["inline"]),
            _as_list(fixture["reviews"]),
            _as_list(fixture["issue"]),
        )
        self.digest = [
            _as_dict(item) for item in _as_list(self.payload["review_digest"])
        ]

    def test_the_api_state_cannot_tell_the_five_reviews_apart(self) -> None:
        self.assertEqual({entry["state"] for entry in self.digest}, {"COMMENTED"})

    def test_every_verdict_comes_from_the_body_first_line(self) -> None:
        self.assertEqual(
            [entry["verdict"] for entry in self.digest],
            [
                "\U0001f7e1 Changes recommended",
                "\U0001f535 Needs a closer look",
                "\U0001f535 Needs a closer look",
                "\U0001f7e1 Changes recommended",
                "\U0001f535 Needs a closer look",
            ],
        )

    def test_the_collapsed_blocks_give_up_their_findings(self) -> None:
        locations = [
            [
                _as_dict(finding)["location"]
                for block in _as_list(entry["suppressed_blocks"])
                for finding in _as_list(_as_dict(block)["findings"])
            ]
            for entry in self.digest
        ]

        self.assertEqual(
            locations,
            [
                [],
                ["scripts/install.sh:503", "scripts/install_test.sh:106"],
                [
                    "scripts/install.sh:561",
                    "scripts/install_test.sh:99",
                    "scripts/install_test.sh:106",
                ],
                [],
                [],
            ],
        )

    def test_each_block_reports_the_count_the_bot_declared(self) -> None:
        blocks = [
            _as_dict(block)
            for entry in self.digest
            for block in _as_list(entry["suppressed_blocks"])
        ]

        self.assertEqual(
            [
                (
                    block["declared_count"],
                    block["extracted_count"],
                    block["counts_agree"],
                )
                for block in blocks
            ],
            [(2, 2, True), (3, 3, True)],
        )

    def test_a_finding_keeps_its_path_line_and_text(self) -> None:
        first_block = _as_dict(_as_list(self.digest[1]["suppressed_blocks"])[0])
        finding = _as_dict(_as_list(first_block["findings"])[0])

        self.assertEqual(finding["path"], "scripts/install.sh")
        self.assertEqual(finding["line"], 503)
        self.assertIn("assert_prompt_safe", cast("str", finding["body"]))

    def test_totals_count_every_place_a_finding_can_live(self) -> None:
        self.assertEqual(
            self.payload["totals"],
            {
                "reviews": 5,
                "inline": 3,
                "issue": 0,
                "suppressed_declared": 5,
                "suppressed_extracted": 5,
                "suppressed_distinct_locations": 4,
                "suppressed_counts_agree": True,
                "findings_upper_bound": 7,
            },
        )

    def test_the_upper_bound_counts_a_shared_location_twice(self) -> None:
        inline = {
            f"{_as_dict(item)['path']}:{_as_dict(item)['line']}"
            for item in _as_list(self.payload["inline"])
        }
        suppressed = {
            _as_dict(finding)["location"]
            for entry in self.digest
            for block in _as_list(entry["suppressed_blocks"])
            for finding in _as_list(_as_dict(block)["findings"])
        }
        totals = _as_dict(self.payload["totals"])

        self.assertEqual(inline & suppressed, {"scripts/install.sh:503"})
        self.assertEqual(len(inline | suppressed), 6)
        self.assertEqual(totals["findings_upper_bound"], 7)

    def test_the_raw_endpoint_arrays_are_passed_through_unchanged(self) -> None:
        fixture = _load_fixture()

        self.assertEqual(self.payload["pr"], fixture["pr"])
        self.assertEqual(self.payload["inline"], fixture["inline"])
        self.assertEqual(self.payload["reviews"], fixture["reviews"])
        self.assertEqual(self.payload["issue"], fixture["issue"])


class VerdictTest(unittest.TestCase):
    def test_heading_marks_are_stripped(self) -> None:
        self.assertEqual(
            verdict_from_body("### Approval recommended\n\nLooks fine.\n"),
            "Approval recommended",
        )

    def test_leading_blank_lines_are_skipped(self) -> None:
        self.assertEqual(
            verdict_from_body("\n\n## Changes recommended\n"), "Changes recommended"
        )

    def test_an_empty_body_has_no_verdict(self) -> None:
        self.assertIsNone(verdict_from_body(""))

    def test_a_review_without_a_body_has_no_verdict(self) -> None:
        digest = digest_review({"id": 1, "state": "APPROVED", "body": None})

        self.assertIsNone(digest.verdict)
        self.assertEqual(digest.state, "APPROVED")


class SuppressedBlockTest(unittest.TestCase):
    # The bot's own count is the only independent check on the parser, so
    # a disagreement has to survive into the output rather than be healed.
    def test_a_declared_count_the_findings_contradict_is_reported(self) -> None:
        body = (
            "### Needs a closer look\n"
            "\n"
            "### Suppressed comments (3)\n"
            "\n"
            "**Previously missed (3)** - in code that hasn't changed.\n"
            "\n"
            "**src/a.py:10**\n"
            "* First finding.\n"
            "**src/b.py:20**\n"
            "* Second finding.\n"
            "\n"
            "- **Files reviewed:** 2/2 changed files\n"
        )

        blocks = suppressed_blocks(body)

        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0].declared_count, 3)
        self.assertEqual(len(blocks[0].findings), 2)

    def test_the_footer_bullets_are_not_read_as_findings(self) -> None:
        body = (
            "### Suppressed comments (1)\n"
            "\n"
            "**src/a.py:10**\n"
            "* Only finding.\n"
            "\n"
            "- **Files reviewed:** 2/2 changed files\n"
            "- **Review effort level:** Lite\n"
        )

        findings = suppressed_blocks(body)[0].findings

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].body, "Only finding.")

    def test_a_bullet_inside_a_finding_does_not_end_the_block(self) -> None:
        body = (
            "### Suppressed comments (2)\n"
            "\n"
            "**src/a.py:10**\n"
            "* First finding.\n"
            "```\n"
            "- [ ] a quoted checklist item\n"
            "- **Quoted bold bullet.** Still the first finding.\n"
            "```\n"
            "**src/b.py:20**\n"
            "* Second finding.\n"
            "\n"
            "- **Files reviewed:** 2/2 changed files\n"
            "- **Comments generated:** 2\n"
        )

        findings = suppressed_blocks(body)[0].findings

        self.assertEqual(
            [finding.location for finding in findings],
            ["src/a.py:10", "src/b.py:20"],
        )
        self.assertIn("- [ ] a quoted checklist item", findings[0].body)
        self.assertIn("- **Quoted bold bullet.**", findings[0].body)

    def test_a_blank_line_inside_a_finding_survives(self) -> None:
        body = (
            "### Suppressed comments (1)\n"
            "\n"
            "**src/a.py:10**\n"
            "\n"
            "* First paragraph.\n"
            "\n"
            "Second paragraph.\n"
            "\n"
            "\n"
            "- **Files reviewed:** 1/1 changed files\n"
        )

        finding = suppressed_blocks(body)[0].findings[0]

        self.assertEqual(finding.body, "First paragraph.\n\nSecond paragraph.")

    def test_a_body_without_a_block_yields_nothing(self) -> None:
        self.assertEqual(
            suppressed_blocks("### Approval recommended\n\nAll good.\n"), []
        )

    def test_a_bold_line_inside_a_finding_body_is_not_a_heading(self) -> None:
        body = (
            "### Suppressed comments (1)\n"
            "\n"
            "**src/a.py:10**\n"
            "* First finding.\n"
            "**Note:**\n"
            "Still the first finding.\n"
            "**Decode-folded configuration keys.**\n"
        )

        findings = suppressed_blocks(body)[0].findings

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].location, "src/a.py:10")
        self.assertEqual(findings[0].path, "src/a.py")
        self.assertEqual(findings[0].line, 10)
        self.assertIn("**Note:**", findings[0].body)

    def test_every_heading_form_the_corpus_carries_is_recognized(self) -> None:
        """Forms taken from every review body in sergeyklay/.agents.
        All 59 headings across 38 blocks are `path:line`, with the separator
        and the extension both optional."""
        locations = [
            "Makefile:52",
            "AGENTS.md:9",
            "scripts/install.sh:503",
            ".agents/skills/audit-agent/scripts/audit_usage.py:326",
            ".github/workflows/ci.yml:116",
        ]
        body = "### Suppressed comments (5)\n\n" + "".join(
            f"**{location}**\n* A finding.\n" for location in locations
        )

        findings = suppressed_blocks(body)[0].findings

        self.assertEqual([finding.location for finding in findings], locations)
        self.assertEqual(findings[0].path, "Makefile")
        self.assertEqual(findings[0].line, 52)

    def test_a_heading_without_a_line_number_leaves_the_counts_disagreeing(
        self,
    ) -> None:
        body = "### Suppressed comments (1)\n\n**README.md**\n* No line anchor.\n"

        block = suppressed_blocks(body)[0]

        self.assertEqual(block.findings, [])
        self.assertEqual(block.declared_count, 1)


class MismatchedCountPayloadTest(unittest.TestCase):
    """A block declaring three findings whose body carries only two.
    PR #57 cannot reach this state, so a parser reporting its own count in
    place of the reviewer's stays green against it."""

    def setUp(self) -> None:
        review = {
            "id": 7,
            "state": "COMMENTED",
            "user": {"login": "reviewer[bot]"},
            "body": (
                "### Needs a closer look\n"
                "\n"
                "### Suppressed comments (3)\n"
                "\n"
                "**Previously missed (3)** - in code that hasn't changed.\n"
                "\n"
                "**src/a.py:10**\n"
                "* First finding.\n"
                "**src/b.py:20**\n"
                "* Second finding.\n"
                "\n"
                "- **Files reviewed:** 2/2 changed files\n"
            ),
        }
        self.payload = build_payload(1, [], [review], [])

    def _only_block(self) -> dict[str, object]:
        digest = _as_dict(_as_list(self.payload["review_digest"])[0])
        return _as_dict(_as_list(digest["suppressed_blocks"])[0])

    def test_the_payload_block_keeps_the_declared_count_beside_its_own(self) -> None:
        block = self._only_block()

        self.assertEqual(block["declared_count"], 3)
        self.assertEqual(block["extracted_count"], 2)
        self.assertIs(block["counts_agree"], False)

    def test_the_payload_totals_carry_the_disagreement(self) -> None:
        self.assertEqual(
            self.payload["totals"],
            {
                "reviews": 1,
                "inline": 0,
                "issue": 0,
                "suppressed_declared": 3,
                "suppressed_extracted": 2,
                "suppressed_distinct_locations": 2,
                "suppressed_counts_agree": False,
                "findings_upper_bound": 2,
            },
        )


if __name__ == "__main__":
    unittest.main()
