#!/usr/bin/env python3
# Copyright 2026 Serghei Iakovlev
# SPDX-License-Identifier: Apache-2.0
"""Collect every reviewer comment for a GitHub pull request.

GitHub serves PR review feedback through three distinct endpoints:
    1. Inline line-anchored code comments      (/pulls/{N}/comments)
    2. Review bodies (approve/reject/comment)  (/pulls/{N}/reviews)
    3. Issue-level conversation comments       (`gh pr view --json comments`)

Missing any one of them silently drops a class of feedback and corrupts
Step 1 of the babysit-pr protocol. This script wraps all three calls so
the protocol cannot regress.

Usage:
    fetch_pr_comments.py [PR_NUMBER]

If PR_NUMBER is omitted, the script resolves the PR associated with the
current branch via `gh pr view --json number`.

Output (single JSON object on stdout):
    {
        "pr":      <number>,
        "inline":  [...],   # /pulls/{N}/comments
        "reviews": [...],   # /pulls/{N}/reviews
        "issue":   [...]    # issue-level conversation comments
    }

Exit codes:
    0  success
    1  prerequisite missing (gh CLI not found, not authenticated)
    2  no PR resolvable (no PR_NUMBER given and no PR on current branch)
    3  gh API call failed

Zero runtime dependencies. Works on Python 3.9+.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from typing import Any


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
        ["gh", "repo", "view",
         "--json", "nameWithOwner",
         "--jq", ".nameWithOwner"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"`gh repo view` failed: "
            f"{result.stderr.strip() or 'unknown error'}"
        )
    name = result.stdout.strip()
    if not name:
        raise RuntimeError("`gh repo view` returned an empty repo name")
    return name


def _gh_api_paginated(endpoint: str, label: str) -> list[Any]:
    """Fetch a paginated `gh api` endpoint and concatenate the pages.

    `gh api --paginate` for array-returning endpoints emits successive
    JSON arrays back-to-back on the same stream — not a single wrapping
    array. ``json.JSONDecoder.raw_decode`` lets us walk one value at a
    time and merge them.
    """
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
    items: list[Any] = []
    pos = 0
    n = len(text)
    while pos < n:
        # Skip whitespace between successive JSON values.
        while pos < n and text[pos].isspace():
            pos += 1
        if pos >= n:
            break
        try:
            value, end = decoder.raw_decode(text, pos)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"failed to parse {label} response near offset {pos}: {exc}"
            ) from exc
        if isinstance(value, list):
            items.extend(value)
        else:
            items.append(value)
        pos = end
    return items


def _gh_pr_issue_comments(pr: int) -> list[Any]:
    """Fetch issue-level conversation comments for a PR via `gh pr view`."""
    result = subprocess.run(
        ["gh", "pr", "view", str(pr),
         "--json", "comments",
         "--jq", ".comments"],
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
        parsed = json.loads(out)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"failed to parse issue-level comments for PR #{pr}: {exc}"
        ) from exc
    if not isinstance(parsed, list):
        raise RuntimeError(
            f"expected a JSON array of comments for PR #{pr}, "
            f"got {type(parsed).__name__}"
        )
    return parsed


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
                "Error: no PR on current branch. "
                "Pass PR_NUMBER explicitly.",
                file=sys.stderr,
            )
            return 2

    try:
        repo = _gh_repo()
        inline = _gh_api_paginated(
            f"repos/{repo}/pulls/{pr}/comments", "inline comments"
        )
        reviews = _gh_api_paginated(
            f"repos/{repo}/pulls/{pr}/reviews", "review bodies"
        )
        issue = _gh_pr_issue_comments(pr)
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 3

    payload = {
        "pr": pr,
        "inline": inline,
        "reviews": reviews,
        "issue": issue,
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
