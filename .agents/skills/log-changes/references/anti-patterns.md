# Anti-patterns and recovery

The catalog of changelog anti-patterns with their corrections, and the recovery table for a file that is already in a bad state. Read the first when a bullet feels wrong to write, the second when the changelog itself is wrong.

## Anti-patterns

| Anti-pattern | Why it's wrong | Correct approach |
| --- | --- | --- |
| One entry per commit | Commits are implementation steps, not user outcomes. | Inspect the task or PR as a whole; write one bullet per independently meaningful outcome. |
| Mechanical PR-to-entry mapping | One PR may contain independent changes, while several PRs may only implement one outcome. | Use PRs as evidence, not as entry boundaries; apply Step 2 without rewriting prior entries. |
| Merging related issues into an old bullet | A shared feature, component, or epic does not make independently useful changes one outcome; extending an old entry hides the new task. | Add a dedicated entry for the new outcome and preserve earlier text and references. |
| Using `git log --oneline` as the primary source | Produces commit-level noise: test commits, review feedback, merge commits, formatting fixes. | Inspect the current task and diff for a single entry; query merged PRs by milestone or release window for a release-wide update. |
| Mini user guide | Setup steps, reasons, conditions, and caveats obscure the change even when packed into one or two sentences. | Announce the outcome and essential scope; briefly flag upgrade consequences and link to documentation for procedures. |
| Implementation report | Protocol mappings, retry branches, fallback algorithms, internal error kinds, and diagnostic notices describe how the feature was built rather than what shipped. | Translate internals into observable behavior or omit them when they do not affect user action or expectations. |
| Vague minimalism | "Added protocol support" is short but does not tell readers what they can now do. | Name the concrete capability and its essential scope; brevity must not erase the outcome. |
| Diagnostic catalog | Listing every validation or error code turns the changelog into reference documentation. | Include an identifier only when users or automation must recognize it and respond differently after upgrading. |
| Plain `#NNN` references | Not clickable in rendered markdown - readers must manually construct the URL to navigate to the change. | Use full URLs (see `references/trackers.md`). |
| Including both the issue/task and the PR in one bullet | Doubles the noise and misleads the reader: the issue/task already describes the user-visible problem, the PR is its implementation. | Reference the issue/task only when one exists; fall back to the PR only when no issue/task is available. |
| Bare tracker keys (e.g. `BP-123`, `ENG-42`) | Not clickable; readers cannot navigate to the task without knowing the tracker URL. | Use the full tracker URL (see `references/trackers.md`). |
| Stating that nothing is required (`No migration or new configuration is required.`) | Documents a non-event, and it degrades: once such sentences accumulate, their absence from one entry reads as an oversight rather than as "no migration". | State only what changed. Silence already means nothing changed. |
| Anchoring an edit on a bare `### Added` / `### Fixed` heading | Those headings repeat once per version, and the first match in the file usually sits inside the newest release - so the insert mutates shipped history. | Anchor on text unique to the `[Unreleased]` window, then confirm with `git diff` that no dated section moved. |
| Silently rewriting a prior entry | A silent rewrite can drop a caveat or absorb a separate task; uncommitted entries may also belong to earlier work. | Add a dedicated bullet for a distinct outcome. If prior wording is stale or already covers exactly the same outcome, ask before revising it rather than duplicating it. |
| GitHub Issue links in changelog **when the project's tracker is not GitHub Issues** | The detected tracker is the authoritative source for task references. Adding `/issues/NNN` links is misleading and breaks over time as the GitHub Issues tab is unused. | Use tracker links for all task references; GitHub links remain only for PRs. |
| Reading a CHANGELOG hunk header as proof of the section | The header names the category (`### Fixed`), never the enclosing version, so a bullet inserted into a shipped release reviews as clean. | Resolve each added hunk's line number to the nearest preceding `## [` heading and require `[Unreleased]`. |

## Error recovery

| Problem                    | Fix                                                        |
| -------------------------- | ---------------------------------------------------------- |
| Missing comparison links   | Reconstruct from `git tag --sort=-version:refname`         |
| Duplicate entries          | Deduplicate drafts from the current task; ask before changing prior entries |
| Entry under wrong category | Move it; if ambiguous, prefer Changed over Added           |
| No tags in repository      | Use commit SHAs in comparison links as a temporary measure |
| Edited a dated release section by mistake | Restore that section from `git show HEAD:CHANGELOG.md`, then re-anchor the insert inside `[Unreleased]` |
| Bullet order mixed across sections | Reorder the outlier section to the file's dominant convention. Verify by diffing the sorted, whitespace-stripped, non-empty lines of the file before and after: the only differences allowed are ones you made deliberately, which proves no bullet was lost or silently reworded |
| Dangling clause left by a removed sentence | Re-read the whole bullet and close the sentence; grep the file for the same artifact in sibling entries |
| Noise entry slipped in     | Remove it - a leaner changelog is more trustworthy         |
