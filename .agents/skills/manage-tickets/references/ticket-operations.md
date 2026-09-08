# Ticket operations beyond create

Discovery branching, the policy that binds search, edit, transition and linking, the actualize procedure, and the error-recovery table. SKILL.md carries the create path and the constraints that bind everywhere; a task reaches into this file for one operation at a time.

## Contents

- Discovery branching: what to do with what `getAccessibleAtlassianResources`, `getVisibleJiraProjects`, `getJiraProjectIssueTypesMetadata` and `getJiraIssueTypeMetaWithFields` report
- Search, Edit, Transition: policy for the three operations, plus issue linking
- Actualize: reconciling tickets that predate shipped work
- Error recovery: every expected failure and its recovery

## Discovery branching

Branching on what discovery reports:

| Discovery reports                                          | Behavior                                                                              |
|------------------------------------------------------------|---------------------------------------------------------------------------------------|
| `getAccessibleAtlassianResources` returns empty            | Stop. The MCP is not connected to any Jira site for this account.                     |
| `getVisibleJiraProjects` returns multiple                  | The user must name a project key. List keys and short names; ask.                     |
| Chosen type missing from `getJiraProjectIssueTypesMetadata`| List accepted types; ask which fits. Never silently substitute a different type.      |
| `getJiraIssueTypeMetaWithFields` reports required custom   | Ask one question per required field before drafting.                                  |

## Search, Edit, Transition

MCP invocations for these three operations are catalogued in `references/jira-recipes.md`. Load that file when the user asks to find, modify, or transition a ticket. For broad searches over a populated project, follow the "Querying large projects without overflowing tool output" recipe in that file: pass narrow `fields`, cap `maxResults`, and avoid whole-project `ORDER BY` dumps. The rules below are policy and bind regardless of which recipe is used:

- **Search.** A JQL predicate that names an issue key which does not exist is not an error - it silently matches nothing. A bound like `key <= {KEY}-400` on a project whose highest key is `{KEY}-398` returns zero rows, and a positive control over a range that does exist still passes, so the query looks healthy. Never bound a search by a key you have not confirmed exists, and when a result set is split into buckets, reconcile the bucket totals against a `searchResultMode: "count"` call over the unbucketed query before reporting any of them.
- **Edit.** Read current state via `getJiraIssue` before destructive edits (body replacement, label replacement, type change). Confirm destructive edits with the user before executing. Pass only the changing fields - do not resend unchanged fields.
- **Transition.** Match the user's intent ("close", "done", "in progress", "in review") to a transition name returned by `getTransitionsForJiraIssue`; transition IDs vary per project workflow. After transitioning, verify the new status via `getJiraIssue`.
- **Linking.** Use `getIssueLinkTypes` to confirm the type name and read its `inward`/`outward` labels. For "Blocks", `inwardIssue` is the blocker and `outwardIssue` is the blocked: a link created with `inwardIssue` = X and `outwardIssue` = Y renders in the UI as "Y is blocked by X". The `inward`/`outward` field names are not self-evident, so do not reason direction out from them - confirm against the type's own labels, and after creating any directional link verify orientation by re-reading one endpoint via `getJiraIssue` and inspecting `issuelinks`, or by checking the rendered relationship in the UI. This MCP exposes no delete-issue-link tool: a wrong-direction link succeeds silently and cannot be removed programmatically, so get direction right before the call and flag any stray link id for the user to delete manually. If the link fails, report the ticket as created and the link as pending - do not delete the ticket to retry from scratch.

## Actualize

When existing tickets predate work that has since shipped, reconcile them against reality. Treat the ticket as untrusted and the current code as ground truth: a ticket's age is not evidence of its accuracy.

1. **Establish ground truth first.** Read the current code and docs for the feature area before editing any ticket. A ticket marked "to do" may already be shipped, and what a ticket describes may no longer match the code. Code and docs are not co-equal ground truth: where they disagree, the code wins and the docs are stated intent that has drifted. Confirm every claim against the code before it survives into a rewritten ticket, and report the disagreement instead of silently resolving it. Do not rewrite from the ticket's own claims.
2. **Classify each ticket** against what shipped: shipped-as-described, shipped-differently, partially-built, unbuilt-but-still-valid, or obsolete/superseded.
3. **Re-resolve dependency links.** Blockers recorded on a stale ticket may already be resolved or themselves obsolete. Re-read `issuelinks` via `getJiraIssue` and update or remove links so the graph reflects the current state, using the direction-verification rule in "Search, Edit, Transition".
4. **Apply per classification.** Rewrite survivors to the "Body shape", scoped to the residual work only and dropping what already shipped. Close an obsolete or superseded ticket by matching intent to a transition name from `getTransitionsForJiraIssue` (never a memorized ID), and record what superseded it, as a closing comment when the MCP supports one, otherwise appended to the body.
5. **Confirm before destructive changes.** Body replacement and closures are destructive: confirm with the user first, then verify each result by re-reading via `getJiraIssue`, per "Search, Edit, Transition".

## Error recovery

| Error                                                              | Recovery                                                                                       |
|--------------------------------------------------------------------|------------------------------------------------------------------------------------------------|
| Atlassian MCP unavailable                                          | Stop. Report that Jira requires MCP; ask user to enable it.                                    |
| `getVisibleJiraProjects` returns multiple                          | List keys and short names; ask which to use.                                                   |
| Classified type missing from `getJiraProjectIssueTypesMetadata`    | List accepted types; ask which fits the request.                                               |
| `createJiraIssue` rejects a required field                         | Re-read `getJiraIssueTypeMetaWithFields`; ask user for the value; retry.                       |
| `createJiraIssue` rejects an unknown field                         | Drop the field; retry; report omission so the user can backfill.                               |
| Sub-task created without parent (parent silently ignored)          | Set parent via `editJiraIssue` immediately; report in the post-create summary.                 |
| `createIssueLink` creates a reversed link (succeeds silently, or rejects with "wrong direction") | For "Blocks", `inwardIssue` = blocker, `outwardIssue` = blocked; verify by re-reading `issuelinks` via `getJiraIssue` or checking the rendered UI. A silently-reversed link cannot be deleted via this MCP - flag its link id for the user to delete and create the correct link. |
| Ticket body names a key that was predicted rather than read from a create report | Fix the body via `editJiraIssue`, reading the real key off the report. Resolve the predicted key with `getJiraIssue` first: it is often a live sibling from the same batch rather than absent, so the wrong link renders correctly and reads as intentional. |
| `lookupJiraAccountId` returns multiple users                       | Ask the user to disambiguate by email or unique substring.                                     |
| `transitionJiraIssue` rejects the transition ID                    | Re-run `getTransitionsForJiraIssue` (workflow may have changed); pick from the fresh list.     |
| User-named issue key not found by `getJiraIssue`                   | Verify project key prefix; if still missing, ask whether the key was typed correctly.          |
