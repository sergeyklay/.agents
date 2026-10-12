---
name: create-pr
description: "Use when asked to create a pull request, open a PR, or submit changes for review. Handles branch verification, change analysis, title and description generation, and gh pr create. Do NOT use for committing, pushing without PR, or reviewing existing PRs"
metadata:
  author: Serghei Iakovlev
  version: "1.4"
  category: vcs
---

# Creating a Pull Request

## Workflow

### Step 1: Verify branch state

```bash
CURRENT=$(git branch --show-current)
DEFAULT=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
```

- If `$CURRENT` equals `$DEFAULT` or is `develop`/`release/*`/`hotfix/*`: inform user they are on a protected branch, cannot create PR from here
- If uncommitted changes exist: commit first (use git-commit skill)
- If branch not pushed: `git push -u origin $CURRENT`

### Step 2: Analyze changes

```bash
DEFAULT=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
git log --format="%s%n%b" "$DEFAULT..HEAD"
git diff --name-only "$DEFAULT..HEAD"
git diff --stat "$DEFAULT..HEAD"
```

From the diff and commits, identify:

- **Type**: primary change type (feat, fix, refactor, chore, perf)
- **Intent**: business/technical goal (1-2 sentences)
- **Entry point**: most critical changed file for reviewer
- **Sensitive areas**: files needing extra scrutiny (auth, payments, data)
- **Breaking changes**: `!` in commits or BREAKING CHANGE footer
- **Migrations**: database or schema changes

### Step 3: Resolve the linked issue

Two separate questions decide what the PR takes from an issue:

| Question | When yes |
| -------- | -------- |
| **Belongs**: does every change in the PR serve this one issue, and nothing else? | Copy the issue's labels, milestone and projects to the PR |
| **Completes**: once merged, is nothing left to do on the issue? | Link it under Development with a closing keyword |

A PR can belong to an issue without completing it: one step of a larger task. A PR that serves several issues, or mixes in unrelated changes, belongs to none of them and gets neither.

Take the first candidate found:

1. An issue named in the arguments: `#123`, `owner/repo#123`, or its URL.
2. A closing footer in the branch's commits: `Closes #123`, `Fixes #123`, `Resolves #123`.
3. An issue number in the branch name, as in `fix/123-null-user`.

```bash
gh issue view <number> --json number,title,state,body,labels,milestone,projectItems
```

Answer both questions from the issue body and the change from Step 2. Ask the user when there are several candidates, the issue is closed, or either answer is unclear. A wrong "completes" closes the issue on merge. A non-GitHub key such as `PROJ-456` carries no metadata; write it under Related Issues as plain text.

When the PR belongs to the issue:

- Copy labels and the milestone only from an issue in the same repository. Both are repository-scoped.
- Trust an empty `projectItems` only after checking the token: it comes back empty, without an error, when the token lacks the `project` scope.

  ```bash
  gh auth status --active --json hosts --jq '.hosts[][].scopes'
  ```

  Without `project`, skip projects and tell the user to run `gh auth refresh -s project`.

Under Related Issues:

- Completes: `Closes #123`, or `Closes owner/repo#123` for another repository. The keyword is the only way to fill Development from the CLI, since no API links a PR manually, and GitHub honours it only when the base is the default branch.
- Belongs but does not complete: `Part of #123`. No closing keyword, so merging leaves the issue open and Development stays empty.
- Otherwise: plain `#123`.

### Step 4: Generate title

Conventional Commits format: `<type>[scope]: <description>`

- Imperative mood, under 72 chars, no period, English only
- Match the project's commit style (check `git log --format="%s" -20`)

NEVER add task ID, issue number, or other metadata to the title:

**❌ Wrong:**
```
feat(messages): add server-only synthetic mailbox archive parser (BP-1234)
```

**✅ Correct:**
```
feat(messages): add server-only synthetic mailbox archive parser
```

### Step 5: Generate description

Open `assets/pull_request_template.md` and read it before writing a line of the body. That file is the only definition of the shape: reproduce every heading it carries verbatim, at the level and with the emoji it gives them, and fill each one. Add no section the template does not define.

Formatting rules:

- No fluff intros ("This PR updates...")
- Filenames in backticks: \`path/to/file.ts\`
- Use " - " (hyphen), not "-" (em-dash)
- No hard-wrap in body prose: GitHub renders soft line breaks as `<br>` in PR descriptions, so wrapping at ~80 chars creates visible artificial breaks. Let paragraphs flow; break only for new paragraphs, list items, or code blocks
- All sections required, sub-sections only when relevant data exists

Do NOT reference specifications (`./specs/*.md`), plans (`./plans/*.md`), its section numbers, or `TODO.md` in pull request descriptions. These are internal artifacts for agent coordination and should not be exposed to human reviewers. If you need to explain a design decision, implementation detail, or rationale, do so in the description without citing internal documents. The description should be self-contained and understandable on its own.

**Verify every claim about repository state before writing it.** A diff supports claims about the *change*; it supports nothing about the *environment* the change lands in. The diff shows a workflow referencing `CICDBOT_TOKEN` - it says nothing about whether that secret exists. Writing "requires `CICDBOT_TOKEN` to be configured" silently promotes a reference into a missing prerequisite, and the reviewer goes chasing a risk that is not there.

Confirm with a command, or do not assert. When a check is unavailable, address the reviewer instead: "Confirm `CICDBOT_TOKEN` is set for this repo" is useful; "requires `CICDBOT_TOKEN`" is a guess wearing a warning's clothes.

| Claim | Check before writing it |
| ----- | ----------------------- |
| A secret or variable exists | `gh secret list`, `gh variable list` |
| A branch rule or required status check is in force | `gh api repos/{owner}/{repo}/rulesets` |
| A person, bot, or team has access | `gh api repos/{owner}/{repo}/collaborators` |
| A repository setting or feature is enabled | `gh api repos/{owner}/{repo} --jq '.<field>'` |
| An external action, workflow, or tag is reachable | `gh api repos/{owner}/{repo}` |
| A CI job or workflow with a given name exists | Read `.github/workflows/*.yml`: `jobs.<id>.name` is the displayed job name. A step name is not a job name |
| A workflow runs on a given branch or event | Read the workflow's `on:` block. `pull_request`-only means the default branch is never checked |

This governs every section, not only Risk Assessment. An unverified line under "Sensitive Areas" costs the reviewer the same time.

Complexity guide:

| Level  | Criteria                                              |
| ------ | ----------------------------------------------------- |
| Low    | Single file, config, docs, simple fix                 |
| Medium | Multiple related files, new feature with tests        |
| High   | Cross-cutting, migrations, breaking changes, security |

### Step 6: Create PR

```bash
DEFAULT=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
gh pr create \
  --title '<title>' \
  --body '<description>' \
  --base "$DEFAULT"
```

For drafts, add `--draft`.

When the PR belongs to an issue (Step 3), add one `--label '<name>'` per label and `--milestone '<title>'`, omitting any that are empty. Add projects after creation, so that a project failure cannot block the PR:

```bash
gh pr edit <number> --add-project '<project title>'
```

When updating an existing PR, apply the same metadata with `gh pr edit --add-label`, `--milestone` and `--add-project`.

MANDATORY: Use single quotes for `--body` to avoid shell interpolation. **NEVER** use double quotes, which can cause variables or special characters in the description to be misinterpreted by the shell.

### Step 7: Verify

```bash
gh pr view --web
```

```bash
gh pr view --json labels,milestone,projectItems,closingIssuesReferences
```

Report: PR number, URL, title, base/head branches, and the issue metadata that was set. Name every field that could not be set, and why.

## Error Recovery

| Error                         | Fix                                     |
| ----------------------------- | --------------------------------------- |
| "pull request already exists" | `gh pr view` to see existing            |
| "no commits between"          | Verify branch has commits ahead of base |
| Auth failure                  | `gh auth login --web`                   |
