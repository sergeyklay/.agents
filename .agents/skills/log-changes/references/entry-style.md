# Writing the entry

The writing rules behind Step 4 of `SKILL.md`, with examples for different audiences. Read this before drafting any bullet.

Writing rules:

- **A changelog is an upgrade decision aid, not a user guide, API reference, design document, or implementation report.** Announce the final released behavior at the product boundary; leave setup sequences, explanations of causes, option lists, diagnostic catalogs, and implementation mechanics to documentation.
- **Lead with the capability or observable outcome.** A reader who sees only the first sentence should still know what was added, changed, fixed, removed, or deprecated.
- **Default to one concise sentence per bullet.** Sentence count is not a brevity test: one sentence packed with semicolons, conditions, and caveats is still a mini-manual. Keep only the scope needed to make the outcome accurate. Add a brief second sentence for an essential upgrade or security consequence, not a list of everything users should know. Link to documentation for procedures; do not invent a documentation URL.
- **Apply the source-free reading test.** The intended reader must understand what changed without knowing private variables, functions, modules, or database fields, and without opening the linked issue. Technical readers still need outcomes rather than implementation narration. Public API names can be necessary for library consumers; private symbols are not.
- **Apply a clause-level necessity test.** If removing a clause leaves an accurate, useful announcement and hides no critical upgrade consequence, remove it. A fact being user-visible does not make it necessary in the changelog. Move usage conditions, rationale, troubleshooting, and secondary limitations to documentation; omit internal validation, retry, fallback, and protocol mechanics.
- **Name public controls selectively.** Keep a CLI flag, configuration key, agent kind, API symbol, or error identifier when the reader needs that exact name to discover, enable, migrate, or react to the change. Do not inventory nested fields, accepted types, validation codes, or every new error kind; those belong in reference documentation unless automation or operator action depends on them.
- **Describe effects, not machinery.** Prefer "requests requiring human input end the attempt" to a list of protocol outcomes and retry branches. Preserve the source's exact scope: do not replace "attempt" with "run", or a conditional capability with an unconditional promise, merely to simplify the sentence.
- **State essential scope without explaining the mechanism.** "Scheduled exports are available for saved reports" sets the boundary. Why other reports are excluded, how to save one, and what to do when scheduling fails belong in documentation.
- **Separate outcomes, not commits.** Apply Step 2's dedicated-entry default. Two changes deserve separate bullets when either can be explained as a useful capability or fix without the other, even within the same feature or PR. Implementation steps needed only to deliver one outcome can share a new bullet. A fix to previously available behavior remains independently notable even if discovered while building a feature.
- **Preserve prior entries.** Only refine the current task's own draft freely. Ask before updating a prior entry that already covers the same outcome or has become inaccurate, whether committed or not. Never merge merely because the entries share a feature, issue label, or session. A dedicated-entry request rules out folding into earlier entries.
- **Never document the absence of a change.** "No migration is required", "no new environment variables", "No operator action is required", "nothing to do here" describe non-events. The file records changes; a reader who finds no migration note concludes there is no migration. Positive operator facts are changes and stay: a required migration or manual step, a new or removed environment variable, a new permission or scope, a changed default. When the audience detected in Step 1 does not deploy the software, drop deploy mechanics in both directions - the negative assertion and the positive instruction - and keep only what that audience can act on.
- **Reference the issue/task when one exists; fall back to the PR otherwise.** Each bullet ends with a parenthetical reference using a full URL (plain `#NNN` or bare tracker keys are not clickable in rendered markdown). When a tracker issue/task is linked from the PR, reference **the issue/task only** - not also the PR. Cite only issues supporting that bullet's outcome, not every issue linked from the PR; several references do not justify merging distinct outcomes. See `references/trackers.md` for the URL format matching the detected tracker.
- Start each bullet with what changed, not with "Fixed" or "Added" (the heading already says that).
- Be specific about the symptom and condition: "Scheduled exports now complete when no filters are selected", not "Fixed async bug".
- Identify the subsystem when it helps locate the change, using the labels detected in Step 1 (e.g. `API:`, `CLI:`, `Auth:`, `Dashboard:`).
- Format necessary public identifiers in backticks; formatting does not make an internal symbol relevant.
- Do not copy git commit messages verbatim - rewrite for a human reader.

## Wording examples

These fictional examples omit tracker links to focus on wording; actual entries still cite their evidence.

| Audience | Implementation-heavy | Changelog-ready |
| --- | --- | --- |
| Application user | Reset `selectedRows` in `ExportController` after applying predicates. | CSV exports now include only the rows matching the selected filters. |
| CLI user | Thread `dryRun` through the deletion handler and skip storage writes. | Preview which files would be deleted with `clean --dry-run`. |
| Library consumer | Add an optional parameter and pass it into the internal scheduler. | `Client.connect()` now accepts `timeout` to limit how long connection attempts wait. |
| Operator | Replace the legacy config parser and remove its compatibility branch. | Configuration files now require a `version` field. Update existing files before upgrading. |

**Too instructional, despite having only two sentences:** "Schedule exports by saving a report, opening its settings, choosing a timezone, and enabling delivery; only administrators can enable schedules, recipients must be verified, and missed runs are skipped because jobs are not replayed. Check delivery logs if a report does not arrive."

**Changelog-ready:** "Administrators can now schedule email delivery of saved reports." Link to the scheduling documentation for setup, delivery rules, and troubleshooting when that documentation exists.

## Entry boundaries

| Situation | Decision |
| --- | --- |
| A previous task added CSV export; the current task adds scheduled exports. | Add a dedicated entry for scheduling; preserve the CSV entry and its links. |
| A feature PR also fixes lost filters in an existing search screen. | Write separate Added and Fixed entries; the fix matters independently. |
| Several implementation tasks build one new export capability; no entry exists yet. | Write one outcome-focused entry, not one per implementation task. |
| A follow-up only corrects the unreleased export feature already described in a prior entry. | If the entry remains accurate, no duplicate is needed. If it needs revision, explain why and ask before editing. Honor an explicit request for a dedicated entry by describing the distinct correction. |
