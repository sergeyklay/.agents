# Atlassian MCP Recipes for Ticket Operations

Reference catalog of Atlassian MCP tool calls for Search, Edit, Transition, and Linking. Critical rules (when to confirm, what fields to include, when to re-read state) live in SKILL.md; this file is the tool-call surface.

## Contents

- Search: list and view tickets by JQL, keyword, key
- Edit: modify summary, description, labels, custom fields
- Transition: move a ticket along the workflow, with state verification
- Linking: create typed relationships between tickets

## Search

### By JQL

Tool: `searchJiraIssuesUsingJql`

Inputs:

```
cloudId: <site cloudId from getAccessibleAtlassianResources>
jql:     <JQL query>
fields:  [summary, status, issuetype, parent, labels, assignee, priority, created]
maxResults: 50
```

Common JQL patterns:

| Intent                                | JQL                                                                                  |
|---------------------------------------|--------------------------------------------------------------------------------------|
| Keyword across all fields             | `project = {KEY} AND text ~ "<keywords>"`                                            |
| Open by type                          | `project = {KEY} AND issuetype = Bug AND statusCategory != Done`                     |
| Assigned to me                        | `project = {KEY} AND assignee = currentUser() AND statusCategory != Done`            |
| Children of an epic                   | `project = {KEY} AND parent = EPIC-KEY`                                              |
| Created in the last 30 days           | `project = {KEY} AND created >= -30d ORDER BY created DESC`                          |
| Recently updated by anyone            | `project = {KEY} AND updated >= -7d ORDER BY updated DESC`                           |
| Open epics, ranked                    | `project = {KEY} AND issuetype = Epic AND statusCategory != Done ORDER BY rank ASC`  |
| Duplicate-check window                | `project = {KEY} AND text ~ "<keywords>" AND statusCategory != Done ORDER BY created DESC` |

Quote the JQL value with double quotes; escape any inner double-quote with `\"`.

### Single ticket

Tool: `getJiraIssue`

Inputs:

```
cloudId:      <site cloudId>
issueIdOrKey: PROJ-123
fields:       [summary, description, status, issuetype, parent, labels, assignee, priority, comment]
```

Read the current state before any destructive edit. Re-read after a transition or destructive edit to verify.

## Edit

Tool: `editJiraIssue`

Inputs:

```
cloudId:       <site cloudId>
issueIdOrKey:  PROJ-123
fields:        { <only the fields that change> }
```

Common payloads:

| Change                           | `fields` payload                                                        |
|----------------------------------|-------------------------------------------------------------------------|
| Update title                     | `{"summary": "<new title>"}`                                            |
| Update description               | `{"description": "<wiki-markup body>"}`                                 |
| Replace labels                   | `{"labels": ["<label1>", "<label2>"]}`                                  |
| Add a single label               | `{"labels": [...existing, "<new label>"]}` (read existing first)        |
| Change priority                  | `{"priority": {"name": "<Priority Name>"}}`                             |
| Change assignee by account id    | `{"assignee": {"accountId": "<account id>"}}`                           |
| Set a custom field by id         | `{"customfield_NNNNN": "<value>"}`                                      |
| Add/remove a parent (non-subtask)| `{"customfield_10014": "<EPIC-KEY>"}` (epic-link field id varies)       |

Rules:

- Read the current ticket via `getJiraIssue` before any destructive edit (body replacement, label replacement, type change).
- Confirm destructive edits with the user before calling `editJiraIssue`.
- Pass only changing fields. Do not resend unchanged fields.
- After a destructive edit, re-read via `getJiraIssue` and include verified state in the report.

## Transition

Jira's equivalent of "close", "in progress", "in review" etc. is a workflow transition, not a status field write. Transition IDs vary per project workflow; always discover fresh.

### Discover available transitions

Tool: `getTransitionsForJiraIssue`

Inputs:

```
cloudId:      <site cloudId>
issueIdOrKey: PROJ-123
```

Returns: list of valid transitions for the ticket's current state, each with `id`, `name`, and target `to.name` status. Match the user's intent ("close", "done", "in progress", "in review", "blocked") to a `name` and use its `id`.

### Apply a transition

Tool: `transitionJiraIssue`

Inputs:

```
cloudId:      <site cloudId>
issueIdOrKey: PROJ-123
transition:   {"id": "<transition id>"}
fields:       { <optional fields the transition screen requires> }
```

Some transitions require fields (resolution, comment, fixVersion, etc.). When `transitionJiraIssue` rejects with "screen requires X", inspect the workflow via `getTransitionsForJiraIssue` for the screen schema, then retry with `fields` populated.

### Verify the new state

After transitioning, re-read the ticket via `getJiraIssue`. Include the new `status.name` in the report. If the new status does not match the user's intent, re-run `getTransitionsForJiraIssue` and propose the correct transition.

### Close reason / commentary

The Atlassian MCP surface in scope does not currently expose a comment-creation tool. When the user asks to close a ticket "with a reason":

- Put the reason in the body of the message reported back to the user, not into the ticket itself.
- If the project's close-transition has a resolution field on its screen, set it via the `fields` payload (e.g. `{"resolution": {"name": "Won't Do"}}`).
- If the deployment exposes a comment tool that this catalog does not list, the agent may use it - but only after discovering the tool via the session's tool list, never from memory.

## Linking related tickets

### Discover link types

Tool: `getIssueLinkTypes`

Inputs:

```
cloudId: <site cloudId>
```

Returns: site-wide link types. Each has a `name` (e.g. "Blocks", "Duplicate", "Clones", "Relates"), an `inward` label (e.g. "is blocked by"), and an `outward` label (e.g. "blocks").

### Create a link

Tool: `createIssueLink`

Inputs:

```
cloudId:       <site cloudId>
type:          <link type name from getIssueLinkTypes, e.g. "Blocks">
inwardIssue:   PROJ-A
outwardIssue:  PROJ-B
```

Direction rule:

| Link type | `inwardIssue` is the … | `outwardIssue` is the … |
|-----------|------------------------|--------------------------|
| Blocks    | blocker                | blocked                  |
| Clones    | original               | clone                    |
| Duplicate | original               | duplicate                |
| Relates   | (symmetric)            | (symmetric)              |

If `createIssueLink` rejects with "wrong direction", re-fetch `getIssueLinkTypes` and swap inward/outward. Retry once. Stop if it fails twice.

### Detect existing links before creating

When linking a freshly-created ticket back to a source (e.g. parent epic, related Bug), the freshly-created ticket carries no existing links. When linking two pre-existing tickets, read both via `getJiraIssue` first and check the `issuelinks` field - do not create a duplicate link of the same type and direction.

## Resolving display names to account ids

Tool: `lookupJiraAccountId`

Inputs:

```
cloudId:      <site cloudId>
searchString: <display name, partial name, or email>
```

Returns: list of matching users with `accountId`, `displayName`, `emailAddress`.

- Unique match: use the `accountId` in `assignee`, `reporter`, or other user fields.
- Multiple matches: ask the user to disambiguate by email or unique substring; do not guess.
- No match: report and ask the user for a different identifier.
