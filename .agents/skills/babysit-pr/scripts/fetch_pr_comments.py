#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""Collect every reviewer comment for a GitHub pull request.
Feedback splits across three endpoints plus folded `Suppressed comments` blocks;
`state` is always COMMENTED, so the verdict is the body's first line."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from typing import NamedTuple, cast

SUPPRESSED_HEADING = re.compile(r"^#{1,6}\s+Suppressed comments\s*\((\d+)\)\s*$")
FINDING_HEADING = re.compile(r"^\*\*(?P<path>\S+):(?P<line>\d+)\*\*$")


def _have_gh() -> bool:
    return shutil.which("gh") is not None


def _gh_authenticated() -> bool:
    """Return True when `gh auth status` exits with 0."""
    result = subprocess.run(
        ["gh", "auth", "status"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def _resolve_pr() -> int | None:
    """Return the PR number associated with the current branch, or None."""
    result = subprocess.run(
        ["gh", "pr", "view", "--json", "number", "--jq", ".number"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    out = result.stdout.strip()
    if not out:
        return None
    try:
        return int(out)
    except ValueError:
        return None


def _gh_repo() -> str:
    """Return the current repo as 'owner/name'."""
    result = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"`gh repo view` failed: {result.stderr.strip() or 'unknown error'}"
        )
    name = result.stdout.strip()
    if not name:
        raise RuntimeError("`gh repo view` returned an empty repo name")
    return name


def _gh_api_paginated(endpoint: str, label: str) -> list[object]:
    """Fetch a paginated `gh api` endpoint and concatenate the pages.
    For array endpoints `--paginate` emits back-to-back JSON arrays rather than
    one wrapping array, so pages are walked with ``raw_decode``."""
    result = subprocess.run(
        ["gh", "api", endpoint, "--paginate"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"failed to fetch {label} ({endpoint}): "
            f"{result.stderr.strip() or 'unknown error'}"
        )

    text = result.stdout
    decoder = json.JSONDecoder()
    items: list[object] = []
    pos = 0
    n = len(text)
    while pos < n:
        # Skip whitespace between successive JSON values.
        while pos < n and text[pos].isspace():
            pos += 1
        if pos >= n:
            break
        try:
            decoded: tuple[object, int] = decoder.raw_decode(text, pos)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"failed to parse {label} response near offset {pos}: {exc}"
            ) from exc
        value, end = decoded
        if isinstance(value, list):
            items.extend(cast(list[object], value))
        else:
            items.append(value)
        pos = end
    return items


def _gh_pr_issue_comments(pr: int) -> list[object]:
    """Fetch issue-level conversation comments for a PR via `gh pr view`."""
    result = subprocess.run(
        ["gh", "pr", "view", str(pr), "--json", "comments", "--jq", ".comments"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"failed to fetch issue-level comments for PR #{pr}: "
            f"{result.stderr.strip() or 'unknown error'}"
        )
    out = result.stdout.strip()
    if not out:
        return []
    try:
        parsed: object = json.loads(out)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"failed to parse issue-level comments for PR #{pr}: {exc}"
        ) from exc
    if not isinstance(parsed, list):
        raise RuntimeError(
            f"expected a JSON array of comments for PR #{pr}, "
            f"got {type(parsed).__name__}"
        )
    return cast(list[object], parsed)


class Finding(NamedTuple):
    """One entry parsed out of a collapsed `Suppressed comments` block."""

    location: str
    path: str
    line: int
    body: str


class SuppressedBlock(NamedTuple):
    """One collapsed block, with the count the bot declared for itself."""

    declared_count: int
    findings: list[Finding]


class ReviewDigest(NamedTuple):
    """What a review body carries beyond its API fields."""

    review_id: int | None
    author: str | None
    state: str | None
    verdict: str | None
    suppressed_blocks: list[SuppressedBlock]


def _as_dict(value: object) -> dict[str, object]:
    if isinstance(value, dict):
        return cast("dict[str, object]", value)
    return {}


def _as_str(value: object) -> str | None:
    return value if isinstance(value, str) else None


def _as_int(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def verdict_from_body(body: str) -> str | None:
    """Return the reviewer's verdict: the body's first non-empty line.
    A bot submits every review under the same API `state` and puts the verdict in
    the body's opening heading, so `state` cannot tell approval from doubt."""
    for line in body.splitlines():
        stripped = line.strip()
        if stripped:
            return stripped.lstrip("#").strip()
    return None


def _block_end(lines: list[str], start: int) -> int:
    """Return the index at which the findings of a block stop.
    The bot closes a block with a `- **Files reviewed:**` footer wrapped in
    `<details>`; either boundary, or the next heading, ends it."""
    for index in range(start, len(lines)):
        stripped = lines[index].strip()
        if stripped.startswith(("#", "- **Files reviewed", "<details", "</details")):
            return index
    return len(lines)


def _parse_findings(lines: list[str]) -> list[Finding]:
    places: list[tuple[str, int]] = []
    bodies: list[list[str]] = []
    for line in lines:
        stripped = line.strip()
        heading = FINDING_HEADING.match(stripped)
        if heading:
            places.append((heading.group("path"), int(heading.group("line"))))
            bodies.append([])
        elif bodies:
            bullet = stripped[2:].strip() if stripped.startswith("* ") else stripped
            bodies[-1].append(bullet)
    return [
        Finding(
            location=f"{path}:{line}",
            path=path,
            line=line,
            body="\n".join(body).strip(),
        )
        for (path, line), body in zip(places, bodies)
    ]


def suppressed_blocks(body: str) -> list[SuppressedBlock]:
    """Parse every `### Suppressed comments (N)` block out of a review body.
    N is kept as the bot wrote it, so a caller can compare it against the
    findings that actually parsed."""
    lines = body.splitlines()
    blocks: list[SuppressedBlock] = []
    for index, line in enumerate(lines):
        heading = SUPPRESSED_HEADING.match(line.strip())
        if heading is None:
            continue
        region = lines[index + 1 : _block_end(lines, index + 1)]
        blocks.append(
            SuppressedBlock(
                declared_count=int(heading.group(1)),
                findings=_parse_findings(region),
            )
        )
    return blocks


def digest_review(review: object) -> ReviewDigest:
    """Derive verdict and suppressed findings from one review object."""
    entry = _as_dict(review)
    body = _as_str(entry.get("body")) or ""
    return ReviewDigest(
        review_id=_as_int(entry.get("id")),
        author=_as_str(_as_dict(entry.get("user")).get("login")),
        state=_as_str(entry.get("state")),
        verdict=verdict_from_body(body),
        suppressed_blocks=suppressed_blocks(body),
    )


def _block_payload(block: SuppressedBlock) -> dict[str, object]:
    extracted = len(block.findings)
    return {
        "declared_count": block.declared_count,
        "extracted_count": extracted,
        "counts_agree": block.declared_count == extracted,
        "findings": [
            {
                "location": finding.location,
                "path": finding.path,
                "line": finding.line,
                "body": finding.body,
            }
            for finding in block.findings
        ],
    }


def _digest_payload(digest: ReviewDigest) -> dict[str, object]:
    return {
        "review_id": digest.review_id,
        "author": digest.author,
        "state": digest.state,
        "verdict": digest.verdict,
        "suppressed_blocks": [
            _block_payload(block) for block in digest.suppressed_blocks
        ],
    }


def build_payload(
    pr: int,
    inline: list[object],
    reviews: list[object],
    issue: list[object],
) -> dict[str, object]:
    """Assemble the JSON object the protocol's Step 1 consumes."""
    digests = [digest_review(review) for review in reviews]
    blocks = [block for digest in digests for block in digest.suppressed_blocks]
    declared = sum(block.declared_count for block in blocks)
    extracted = sum(len(block.findings) for block in blocks)
    # A finding repeated across two blocks is one finding, and the bot
    # rewords it between reviews, so the location is the only stable key.
    locations = {finding.location for block in blocks for finding in block.findings}
    return {
        "pr": pr,
        "inline": inline,
        "reviews": reviews,
        "issue": issue,
        "review_digest": [_digest_payload(digest) for digest in digests],
        "totals": {
            "reviews": len(reviews),
            "inline": len(inline),
            "issue": len(issue),
            "suppressed_declared": declared,
            "suppressed_extracted": extracted,
            "suppressed_distinct_locations": len(locations),
            "suppressed_counts_agree": declared == extracted,
            "findings_upper_bound": len(inline) + len(issue) + len(locations),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="fetch_pr_comments.py",
        description="Collect every reviewer comment for a GitHub PR.",
    )
    parser.add_argument(
        "pr_number",
        nargs="?",
        type=int,
        default=None,
        help="PR number (default: PR associated with the current branch).",
    )
    args = parser.parse_args()

    if not _have_gh():
        print("Error: gh CLI not found on PATH.", file=sys.stderr)
        return 1

    if not _gh_authenticated():
        print(
            "Error: gh is not authenticated. Run 'gh auth login'.",
            file=sys.stderr,
        )
        return 1

    pr = args.pr_number
    if pr is None:
        pr = _resolve_pr()
        if pr is None:
            print(
                "Error: no PR on current branch. Pass PR_NUMBER explicitly.",
                file=sys.stderr,
            )
            return 2

    try:
        repo = _gh_repo()
        inline = _gh_api_paginated(
            f"repos/{repo}/pulls/{pr}/comments", "inline comments"
        )
        reviews = _gh_api_paginated(f"repos/{repo}/pulls/{pr}/reviews", "review bodies")
        issue = _gh_pr_issue_comments(pr)
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 3

    payload = build_payload(pr, inline, reviews, issue)
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
