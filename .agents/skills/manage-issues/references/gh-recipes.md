# `gh` Recipes for Issue Operations

Reference catalog of `gh` invocations for Search, Edit, and Close. Critical rules (when to confirm, what flags to require) live in SKILL.md; this file is the command surface.

## Contents

- Search: list and view issues by keyword, label, milestone, or combination
- Edit: modify title, labels, milestone, body, project membership
- Close: completed vs not planned, with mandatory `--comment`

## Search

```bash
# By keyword
gh issue list --search "<query>" --state all --limit 30

# By label
gh issue list --label "<label>" --state open

# By milestone (full title from taxonomy)
gh issue list --milestone "<full title>" --state open

# Combined filters
gh issue list --label "<label>" --milestone "<full title>"

# Single-issue detail
gh issue view <number>

# Machine-readable output (when piping to other tools)
gh issue list --search "<query>" --state all --limit 30 \
  --json number,title,state,labels,milestone \
  --jq '.[] | "#\(.number) [\(.state)] \(.title)"'
```

## Edit

```bash
gh issue edit <number> --title '<new title>'
gh issue edit <number> --add-label '<label>'
gh issue edit <number> --remove-label '<label>'
gh issue edit <number> --milestone '<full milestone title>'
gh issue edit <number> --body '<new body>'
gh issue edit <number> --add-project '<project name>'
gh issue edit <number> --remove-project '<project name>'
```

Single quotes around values prevent shell interpolation. Escape literal single quotes in `--body` with `'\''`.

## Close

```bash
# Completed work
gh issue close <number> --reason completed --comment 'Resolved in #<PR>'

# Decided not to do
gh issue close <number> --reason "not planned" --comment '<reason>'

# Reopen if closed in error
gh issue reopen <number> --comment '<reason for reopening>'
```
