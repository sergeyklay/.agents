---
description: "Commit staged changes, create or update a pull request"
---

Your task is to commit staged changes and manage pull requests (PR).

## Task

- Use `git-commit` Agent Skill to create commits, create a branch, and `create-pr` Agent Skill to open/change a PR with a meaningful title and description
- Incorporate provided details or context about the changes
- Detect whether you need to create a new PR or update an existing one based on context
- Stage only relevant files - never `git add -A` without reviewing what would be included
- When updating, verify the PR description still accurately reflects the changes
- Use Conventional Commits messages when appropriate

## Template Enforcement

**MANDATORY:** Before creating any PR:

1. **Check for the PR template:** Use PR template **provided by the `create-pr` Agent Skill**. You MUST follow it.
2. **Read the template completely:** Read the entire template file to understand its structure
3. **Follow the template exactly:** Structure the PR body to match the template's sections verbatim
   - Use the template headings as-is (including emojis if present)
   - Fill in each section following the guidance provided
   - Do not skip sections or reorder them
4. **DO NOT invent a custom format:** Deviation from it is a failure

**Process:**

- Load `create-pr` Agent Skill
- Read regarding PR template
- Read template described in Agent Skill
- Map changes to template sections
- Create PR body matching template structure
- Verify sections match before creating/updating PR

## PR Description Content Rules

- **DO NOT** reference `TODO.md`, `.specs/*.md` or `.plans/*.md` in the PR description. Those belong in specs and plans, not in the git history.
- **DO NOT** add an "Implementation Details" or "References" section beyond what the template defines.
- **ONLY** fill in the sections defined by the PR template - nothing more.

## Constraints

- Never force-push without explicit user confirmation.
- Never push directly to `main` - always use a feature branch.
- Never skip pre-commit hooks (`--no-verify`).
- If a hook fails, fix the underlying issue and create a new commit.
