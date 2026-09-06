# Setup and ingest

What must be in place before the protocol runs, and the manual fallback for collecting a pull request's comments when the bundled script cannot run. Read this at the Prerequisites gate, and again at Step 1 if the fetch script is unavailable.

## Prerequisites

1. **`gh` CLI** is available and authenticated - required for Source B (fetching comments from a GitHub PR). Inline-input mode (Source A) does not need it.
2. **Context7** is available and you know its workflow (two calls: `resolve-library-id`, then `query-docs`). This skill defines *when* to use it; the project context defines *how*.
3. **Project verification commands** (formatter, linter, tests, type checker) are documented in the project's context files. You will read those at Step 4a and run only the subset relevant to what you change.
4. **Project architecture documentation** can be located. Common forms: a dedicated file (`docs/architecture.md`, `ARCHITECTURE.md`), an architecture section inside the primary context file (AGENTS.md/CLAUDE.md), a directory of design notes, or a set of accepted ADRs. If no dedicated doc exists, treat the most architecturally-detailed context file as the de facto record. Never guess what the architecture says - read it.
5. **Issue tracker discovery** happens in Step 4b. Do not assume GitHub Issues, Jira, GitLab, Linear, or any specific tool until you have evidence from project context.

## Collecting comments without the script

Run the three commands the fetch script wraps. Missing any of them silently drops a class of comments.

If `python3` or the script is unavailable, run the three commands it wraps - missing any of them silently drops a class of comments:

```bash
PR=$(gh pr view --json number --jq '.number')
gh api "repos/{owner}/{repo}/pulls/${PR}/comments" --paginate
gh api "repos/{owner}/{repo}/pulls/${PR}/reviews"  --paginate
gh pr view "$PR" --json comments --jq '.comments'
```
