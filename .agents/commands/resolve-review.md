---
description: "Resolve reviewer feedback - from GitHub PRs, chat, or any reviewer"
---

Your task is to resolve reviewer feedback on the current pull request or on comments the user provides inline.

## Task

- Use the `babysit-pr` Agent Skill to drive every step of the resolution: ingest, classify, run the Context7 evidence audit, apply changes surgically, and produce the human-only summary.
- Detect the input mode automatically:
  - A GitHub PR number, URL, or the current branch's open PR → use the skill's GitHub-fetch flow.
  - Pasted text or inline reviewer comments → use them as-is.
- Read the project's context files (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`), and project architecture documentation so you know the coding standards, verification commands, issue tracker.

## Skill Enforcement

**MANDATORY:** Apply the `babysit-pr` Agent Skill verbatim.

The skill is the single source of truth for *how* to resolve reviewer comments. The project's context files are the source of truth for *what* counts as a valid standard, verification command, and Context7-required library. Consult each at the moment the skill calls for it.

**Process:**

- Load the `babysit-pr` Agent Skill before reasoning about any comment.
- Walk through each step in order - ingest, Context7 audit, classify, apply, verify, summarize. Do not reimplement, paraphrase, merge, or short-circuit any step. Every gate exists to prevent a documented failure mode.
- If the skill is unavailable in this environment, stop and report the failure. Do not improvise a replacement protocol.
- Emit the Step 6 summary directly in the chat response. The audience is the human operator, not a persistent file.

## Completion

- **When the input was a GitHub PR:** after the summary, commit the applied changes to that PR's branch and push them. This is the expected completion rather than a separate request, and stopping to ask permission to push is itself a failure. Use the `git-commit` Agent Skill, and group the changes into atomic commits along the concerns they resolve. Do not open a new PR, and do not rewrite the existing PR description unless the applied changes made it wrong.
- **When the input was pasted or inline feedback:** leave the changes in the working tree and report them. There may be no branch to land them on.
- Report the commits alongside the summary, so the operator sees both what was decided and what landed.

## Constraints

- **Never post anything to the reviewer.** No reply comments, no issue-level comments, no reactions, no resolutions, no marking-as-outdated. All output goes to the human operator only.
- Never accept or reject a comment that makes a library claim without running Context7 against that claim first.
- Never leave a "Deferred" comment without a ticket reference. If no ticket can be produced, reclassify the comment.
- Never modify accepted ADRs without explicit instruction from the user.
- Preserve the project's existing code style, module boundaries, and architectural conventions.
