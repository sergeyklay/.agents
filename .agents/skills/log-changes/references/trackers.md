# Tracker-specific extraction and reference format

Read the section that matches the tracker detected in Step 1 of SKILL.md. Use the extraction commands to find issue/task IDs in PR bodies, and use the reference format when writing changelog bullets.

## GitHub Issues

**Extract issue references from a PR body** (case-insensitive; handles optional markdown bold, optional colon, cross-repo `owner/repo#N`, multiple per line):

```bash
gh pr view <NUMBER> --json body --jq '.body' | grep -ioE '\*{0,2}(close[ds]?|fix(e[ds])?|resolve[ds]?|related|part of)[^:#*]*:?\*{0,2}[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+'
```

Read each linked issue (`gh issue view <NUMBER>`) for the user-facing problem statement. Use the issue as the source of truth for what the change does - PR titles are implementation-focused, issues are user/operator-focused.

**Reference format**:

- Issue: `[#NNN](https://github.com/OWNER/REPO/issues/NNN)`
- PR (fallback when no issue): `[#NNN](https://github.com/OWNER/REPO/pull/NNN)`

## Jira

**Extract task IDs from a PR body** by project-key prefix (e.g. `BP-123`, `ABC-42`):

```bash
gh pr view <NUMBER> --json body --jq '.body' | grep -ioE '\b[A-Z]+-[0-9]+\b'
```

For each Jira task ID found, fetch full task details with the `getJiraIssue` MCP tool (or `fetch` for the Jira REST API) to get the task summary, type, and description. Use the Jira task as the source of truth for what the change does - PR titles are implementation-focused, tracker tasks are user/operator-focused.

**Fetch resolved tasks within a release window** with the `searchJiraIssuesUsingJql` MCP tool (substitute the project key and date detected in Step 1):

```
project = PROJECT_KEY AND status changed to (Done, Resolved, Closed) AFTER "YYYY-MM-DD" ORDER BY updated ASC
```

If the MCP tool is unavailable, open Jira in the browser and run the JQL manually, or ask the user to paste the task list.

**Reference format**:

- Task: `[KEY-NNN](https://example.atlassian.net/browse/KEY-NNN)` - substitute the tracker base URL and key prefix detected in Step 1.

## Linear

**Extract task IDs from a PR body** by project-key prefix (e.g. `ENG-123`):

```bash
gh pr view <NUMBER> --json body --jq '.body' | grep -ioE '\b[A-Z]+-[0-9]+\b'
```

Read each task in Linear (UI or API) for the user-facing problem statement.

**Fetch resolved tasks within a release window**: use Linear's search API or web UI to fetch items resolved within the same window as the git tag date.

**Reference format**:

- Task: `[KEY-NNN](https://linear.app/WORKSPACE/issue/KEY-NNN)` - substitute the workspace and key prefix detected in Step 1.

## Other trackers

For trackers not listed above (Asana, Shortcut, Pivotal, etc.):

- Extract IDs using the project's identifier scheme as detected in Step 1.
- Read each task in the tracker UI or via its API.
- Use the full URL of the task in the tracker UI as the reference.

## Multi-reference format (any tracker)

One reference per line inside the parens:

```
([KEY-42](https://example.atlassian.net/browse/KEY-42),
[KEY-43](https://example.atlassian.net/browse/KEY-43))
```

Single reference stays on the same line: `([KEY-42](https://example.atlassian.net/browse/KEY-42))`.
