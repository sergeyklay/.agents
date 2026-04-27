---
name: manage-adr
description: "Create, update, and validate Architecture Decision Records (ADRs) following MADR 4.0 format. Use when the user mentions ADR, architecture decision, decision record, or asks to document a technical decision. Also use when creating new files in docs/decisions/. Handles numbering, frontmatter, section structure, and README index updates. Do NOT use for general documentation or non-architectural decisions."
metadata:
  author: Serghei Iakovlev
  version: "1.0"
  category: documentation
---

# Managing Architecture Decision Records

This project stores ADRs in `docs/decisions/` following [MADR 4.0](https://adr.github.io/madr/) with project-specific conventions documented below.

## File Conventions

- Path: `docs/decisions/NNNN-kebab-case-title.md`
- Numbering: zero-padded four digits, sequential. See "Get Sequence Number" below.
- Index: `docs/decisions/README.md` contains a table of all ADRs. Update it after every create, rename, or status change.

## Running scripts bundled with this skill

Script paths in this document (e.g. `scripts/`) are resolved relative to **this** SKILL.md file, not to your current working directory. If a relative command fails to resolve, prefix it with the path your platform loaded this SKILL.md from.

**Fallback.** If `python3` is not installed or the script cannot be located, every procedure in this skill provides a manual alternative — follow those steps instead.

## Running scripts bundled with this skill

Script paths in this document (e.g. `scripts/`) are resolved relative to **this** SKILL.md file, not to your current working directory. If a relative command fails to resolve, prefix it with the path your platform loaded this SKILL.md from.

## ADR Template

Use [assets/adr-template.md](assets/adr-template.md) as the starting point. The template contains the exact frontmatter and section structure. Copy it, fill in the content, remove sections marked optional if unused.

Key rules:

- Frontmatter fields `status` and `date` are required. `decision-makers` is required for accepted decisions.
- `status` values: `proposed`, `accepted`, `deprecated`, `superseded by NNNN`
- `date` format: `YYYY-MM-DD` (date of last status change)
- The H1 title is a short imperative phrase: "Use X for Y", not "Decision about X"
- "Decision Outcome" must begin with `Chosen option: **X**, because Y`
- "Considered Options" is a bullet list. Detailed analysis goes under "### Considered Options in Detail" inside "Decision Outcome"
- Decision Drivers use numbered bold-label items: `1. **Label.** Description`

## Get Sequence Number

Two strategies depending on context:

**Pre-assigned number** (passed by caller or human): Use it directly. Do not call the script — this prevents duplicate numbers when multiple ADRs are created in parallel.

**No number assigned** (standalone use) `python3 scripts/next_adr_number.py` to get the next available number:

```bash
# Output: 0004
```

For batch allocation (multiple ADRs in one session) `python3 scripts/next_adr_number.py --count 3` to reserve a block of numbers:

```bash
# Output:
# 0004
# 0005
# 0006
```

Allocate all numbers upfront before creating any files. This avoids the script returning the same number twice when files haven't been written yet.

By default the script resolves `docs/decisions/` relative to its own location. If your ADRs live elsewhere — or the default path does not match the layout this skill was loaded from — pass `--decision-dir <path>` to override:

```bash
python3 scripts/next_adr_number.py --decision-dir docs/decisions
python3 scripts/next_adr_number.py --decision-dir docs/decisions --count 3
```

## Operations

### Create ADR

1. Get the next ADR number (see "Get Sequence Number" above).
2. Copy `assets/adr-template.md` to `docs/decisions/NNNN-kebab-case-title.md`.
3. Fill in frontmatter: `status: proposed`, `date: <today>`, `decision-makers: <name>`.
4. Write Context, Decision Drivers, Considered Options, and Decision Outcome.
5. Remove unused optional sections (Consequences, Confirmation).
6. Update `docs/decisions/README.md` — add a row to the table.

### Update ADR Status

1. Edit the `status` field in frontmatter.
2. Update `date` to today.
3. If superseded, set `status: superseded by NNNN` and link to the replacement ADR.
4. Update the Status column in `docs/decisions/README.md`.

### Validate ADRs

Check every file in `docs/decisions/` (excluding README.md):

- [ ] Filename matches `NNNN-kebab-case-title.md`
- [ ] YAML frontmatter has `status`, `date` fields
- [ ] `date` is valid `YYYY-MM-DD`
- [ ] `status` is one of: `proposed`, `accepted`, `deprecated`, `superseded by NNNN`
- [ ] `decision-makers` is present and non-empty when `status` is `accepted`
- [ ] H1 title exists and is an imperative phrase
- [ ] Sections present: "Context and Problem Statement", "Considered Options", "Decision Outcome"
- [ ] "Decision Outcome" contains `Chosen option: **` pattern
- [ ] "Considered Options" is a bullet list
- [ ] `docs/decisions/README.md` table has a row for this ADR with correct title and status

Report all violations. Do not auto-fix without confirmation.

### Update README Index

Regenerate the table in `docs/decisions/README.md` by scanning all ADR files:

```markdown
| ADR                              | Title         | Status |
| -------------------------------- | ------------- | ------ |
| [NNNN](NNNN-kebab-case-title.md) | H1 title text | Status |
```

- Sort by ADR number ascending.
- Title column uses the H1 text from the ADR file.
- Status column uses the `status` frontmatter value, capitalized.
- Preserve the introductory paragraph and heading above the table.
