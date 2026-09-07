# Setup and ingest

What must be in place before the protocol runs, how to read a review body as the container of findings it is, and the manual fallback for collecting a pull request's comments when the bundled script cannot run. Read this at the Prerequisites gate, and again at Step 1 if the fetch script is unavailable.

## Prerequisites

1. **`gh` CLI** is available and authenticated - required for Source B (fetching comments from a GitHub PR). Inline-input mode (Source A) does not need it.
2. **Context7** is available and you know its workflow (two calls: `resolve-library-id`, then `query-docs`). This skill defines *when* to use it; the project context defines *how*.
3. **Project verification commands** (formatter, linter, tests, type checker) are documented in the project's context files. You will read those at Step 4a and run only the subset relevant to what you change.
4. **Project architecture documentation** can be located. Common forms: a dedicated file (`docs/architecture.md`, `ARCHITECTURE.md`), an architecture section inside the primary context file (AGENTS.md/CLAUDE.md), a directory of design notes, or a set of accepted ADRs. If no dedicated doc exists, treat the most architecturally-detailed context file as the de facto record. Never guess what the architecture says - read it.
5. **Issue tracker discovery** happens in Step 4b. Do not assume GitHub Issues, Jira, GitLab, Linear, or any specific tool until you have evidence from project context.

## Reading a review body

GitHub scatters one reviewer's findings across three places, and the third one is inside the second. Treating a review object as a single finding is the miscount this section exists to prevent.

1. **Inline comments** (`/pulls/{N}/comments`) - the line-anchored comments the reviewer chose to post on the diff. One object is one finding.
2. **The review body** (`/pulls/{N}/reviews`, field `body`) - free-form Markdown. Its prose is a finding in its own right when it names a concern.
3. **Collapsed blocks inside that body** - a bot moves the findings it decided not to post inline into a `### Suppressed comments (N)` section, formatted as a `**path:line**` line followed by the finding text. Open every block and read every entry; nothing else surfaces them.

**Check your count against the reviewer's own.** The `N` in the block heading is the number the reviewer claims it suppressed. Compare it with the number of entries you extracted. The fetch script does this for you and reports both: `review_digest[].suppressed_blocks[]` carries `declared_count`, `extracted_count` and `counts_agree`. A `false` means the body's format has moved and the block must be read by hand before anything downstream trusts the list.

**The same finding can appear in more than one block.** A bot repeats a suppressed finding in every later review that still sees it, and rewords it between reviews, so deduplicate by `path:line` rather than by text. `totals.suppressed_distinct_locations` is that deduplicated count.

## Reading the verdict

The API `state` field carries the review action, and a reviewer bot submits every one of its reviews as `COMMENTED`. The verdict lives in the first line of the body instead, as a Markdown heading:

| First line of the body           | What it means                                  |
|----------------------------------|------------------------------------------------|
| `### 🟢 Approval recommended`    | The reviewer found nothing blocking             |
| `### 🟡 Changes recommended`     | The reviewer wants changes before approval      |
| `### 🔵 Needs a closer look`     | The reviewer defers to a human                  |

`review_digest[].verdict` carries that line with the heading marks stripped. Reading `state` instead cannot tell an approval from a request for a closer look, because both arrive as `COMMENTED`.

## Collecting comments without the script

Run the three commands the fetch script wraps. Missing any of them silently drops a class of comments.

If `python3` or the script is unavailable, run the three commands it wraps - missing any of them silently drops a class of comments:

```bash
PR=$(gh pr view --json number --jq '.number')
gh api "repos/{owner}/{repo}/pulls/${PR}/comments" --paginate
gh api "repos/{owner}/{repo}/pulls/${PR}/reviews"  --paginate
gh pr view "$PR" --json comments --jq '.comments'
```

These return the raw objects and nothing derived. Apply "Reading a review body" and "Reading the verdict" above to the `reviews` output by hand: open each collapsed block, count its entries against the declared `N`, and take each verdict from the body's first line.
