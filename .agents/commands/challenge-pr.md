---
description: "Challenge a pull request with an independent second opinion from another model"
---

Your task is to obtain an independent review of a pull request from a second model and arbitrate where that review and your own diverge.

## Task

- Use the `challenge-pr` Agent Skill to drive every step: resolve the target, capture the diff, launch the second opinion, review independently, arbitrate, report.
- Resolve the target from the argument: a PR number, URL, or `owner/repo#123`. With no argument, use the current branch's open PR.
- Read the project's context files (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`) and architecture documentation, so your own pass judges the diff against this project's standards rather than generic ones.

## Skill Enforcement

**MANDATORY:** Apply the `challenge-pr` Agent Skill verbatim.

The skill is the single source of truth for *how* the two reviews are obtained and reconciled. The project's context files are the source of truth for *what* counts as a defect worth reporting.

**Process:**

- Load the `challenge-pr` Agent Skill before reading any part of the diff.
- Start the second opinion in the background before your own review begins, and do not open its output until your own findings are written down. The step order is what makes "Agreed" mean anything; reordering it produces a review that merely confirms another model.
- If the skill is unavailable in this environment, stop and report the failure. Do not improvise a replacement protocol and do not call any model provider directly.
- Emit the report in the chat response. The audience is the human operator, not a file.

## Constraints

- **Never modify code.** No fixes, no commits, no pushes. The output is an opinion.
- **Never post to GitHub.** No review, no comment, no approval, no request-for-changes.
- Never report a finding from the second model without first checking it against the code yourself.
- Never treat the second model's severity or confidence as the verdict, and never let its unavailability stop the review.
- Name the model that actually served the request, taken from the script's output rather than from what was requested.
