---
name: create-pr
description: "Use when asked to create a pull request, open a PR, or submit changes for review. Handles branch verification, change analysis, title and description generation, and gh pr create. Do NOT use for committing, pushing without PR, or reviewing existing PRs"
metadata:
  author: Serghei Iakovlev
  version: "1.1"
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

### Step 3: Generate title

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

### Step 4: Generate description

Use the template from `assets/pull_request_template.md`. Three sections:

1. **Scope & Context** - Type, Intent, Related Issues
2. **Reviewer Guide** - Complexity (Low/Medium/High), Entry Point, Sensitive Areas
3. **Risk Assessment** - Breaking Changes, Migrations/State

Formatting rules:

- No fluff intros ("This PR updates...")
- Filenames in backticks: \`path/to/file.ts\`
- Use " - " (hyphen), not "-" (em-dash)
- No hard-wrap in body prose: GitHub renders soft line breaks as `<br>` in PR descriptions, so wrapping at ~80 chars creates visible artificial breaks. Let paragraphs flow; break only for new paragraphs, list items, or code blocks
- All sections required, sub-sections only when relevant data exists

Do NOT reference specifications (`./specs/*.md`), plans (`./plans/*.md`), its section numbers, or `TODO.md` in pull request descriptions. These are internal artifacts for agent coordination and should not be exposed to human reviewers. If you need to explain a design decision, implementation detail, or rationale, do so in the description without citing internal documents. The description should be self-contained and understandable on its own.

Complexity guide:

| Level  | Criteria                                              |
| ------ | ----------------------------------------------------- |
| Low    | Single file, config, docs, simple fix                 |
| Medium | Multiple related files, new feature with tests        |
| High   | Cross-cutting, migrations, breaking changes, security |

### Step 5: Create PR

```bash
DEFAULT=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
gh pr create \
  --title '<title>' \
  --body '<description>' \
  --base "$DEFAULT"
```

For drafts, add `--draft`.

MANDATORY: Use single quotes for `--body` to avoid shell interpolation. **NEVER** use double quotes, which can cause variables or special characters in the description to be misinterpreted by the shell.

### Step 6: Verify

```bash
gh pr view --web
```

Report: PR number, URL, title, base/head branches.

## Error Recovery

| Error                         | Fix                                     |
| ----------------------------- | --------------------------------------- |
| "pull request already exists" | `gh pr view` to see existing            |
| "no commits between"          | Verify branch has commits ahead of base |
| Auth failure                  | `gh auth login --web`                   |
