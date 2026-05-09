# Writing Patterns for Skill Instructions

Concrete patterns for structuring skill instructions. Each pattern includes when to use it and a complete example.

## Contents

- Density: write for the agent, not the reader
- Degrees of freedom
- Template pattern
- Examples (multishot) pattern
- Workflow with checklists
- Conditional workflow pattern
- Feedback loop pattern
- Progressive disclosure patterns
- Script integration patterns
- Cross-references without force-loading
- MCP tool references

## Density: Write for the Agent, Not the Reader

Skills are read by an LLM ingesting tokens, not by a person browsing a wiki page. Every line stays in context for the rest of the turn. Optimize for density and clarity, not visual aesthetics.

**Decoration that costs tokens and earns nothing:**

- Hard wraps inside a single logical paragraph that imply meaningful line breaks where there are none.
- Blockquote framing (`> ...`) around examples — use a code fence; the agent does not benefit from a `>` border.
- "Why this works" / "Why X here" paragraphs after every example. State the rule once with its reason, then trust the agent.
- Three-deep ladders of indented bullets where a tight sentence does the job.
- Restating a rule in prose immediately after a code block already showing it.
- `Tip:` / `Note:` / `Important:` wrappers around single sentences — just write the sentence.
- Decorative section dividers, repeated bold-headers-followed-by-the-same-text-as-prose, or "Step 1: …" preambles when the steps are already a numbered list.

**Decorative (~85 tokens):**

~~~markdown
## Database migrations

> **Important:** database migrations are fragile.

Run exactly this script:

```
python scripts/migrate.py --verify --backup
```

Why this works: `--verify` prevents destructive changes without confirmation,
and `--backup` creates a rollback point. These are critical safety flags
that exist for important safety reasons.
~~~

**Dense (~35 tokens), same information:**

~~~markdown
## Database migrations

```
python scripts/migrate.py --verify --backup
```

`--verify` blocks destructive changes; `--backup` creates a rollback point. Do not drop these flags.
~~~

Density is not cryptic. Use headings, tables, code fences, and short paragraphs to give the agent navigation. Cut visual fluff that exists only because the page would feel "empty" without it.

When you must explain *why* a rule exists (the reasoning helps the agent generalize to cases the skill did not anticipate), inline it in the same sentence as the rule. One sentence with reasoning beats a separate "rationale" paragraph that the model has to stitch back to the rule it justifies.

## Degrees of Freedom

Match specificity to how fragile and variable the task is.

**High freedom** — multiple valid approaches, context-dependent. Use when context drives the right answer (code review, creative writing, exploratory analysis):

```markdown
## Code review process

1. Analyze code structure and organization
2. Check for potential bugs or edge cases
3. Suggest improvements for readability
4. Verify adherence to project conventions
```

**Medium freedom** — a preferred pattern exists, some variation acceptable:

```markdown
## Generate report

Use this template, adapt sections to the data:

# [Analysis Title]
## Executive summary
[One-paragraph overview]
## Key findings
[Adapt sections based on what you discover]
## Recommendations
[Tailor to context]
```

**Low freedom** — fragile operations, consistency critical (migrations, format ops, anything where wrong = data loss):

```markdown
## Database migration

python scripts/migrate.py --verify --backup

Do not modify the command. `--verify` blocks destructive changes without confirmation; `--backup` creates a rollback point.
```

If wrong = data loss or broken output, use low freedom. If creativity improves the result, use high freedom. Default to medium.

## Template Pattern

Provide output format templates. Match strictness to requirements.

**Strict** (API responses, data formats, compliance documents):

```markdown
## Report structure

ALWAYS use this exact template structure:

# [Analysis Title]

## Executive summary

[One-paragraph overview of key findings]

## Key findings

- Finding 1 with supporting data
- Finding 2 with supporting data

## Recommendations

1. Specific actionable recommendation
2. Specific actionable recommendation
```

**Flexible** (when adaptation improves quality):

```markdown
## Report structure

Sensible default format - adapt based on what you discover:

# [Analysis Title]

## Executive summary

## Key findings (adapt sections based on analysis)

## Recommendations (tailor to context)

Adjust sections as needed. Add "Risks" if significant concerns emerge.
Drop "Recommendations" if the task is purely analytical.
```

## Examples (Multishot) Pattern

Input/output pairs communicate style and expectations more effectively than descriptions alone. Include 3-5 diverse examples covering edge cases.

```markdown
## Commit message format

**Example 1** (new feature):
Input: Added user authentication with JWT tokens
Output:
feat(auth): implement JWT-based authentication
Add login endpoint and token validation middleware

**Example 2** (bug fix):
Input: Fixed bug where dates displayed incorrectly
Output:
fix(reports): correct date formatting in timezone conversion
Use UTC timestamps consistently across report generation

**Example 3** (multiple changes):
Input: Updated dependencies and refactored error handling
Output:
chore: update dependencies and refactor error handling

- Upgrade lodash to 4.17.21
- Standardize error response format across endpoints

Follow this pattern: type(scope): brief description, then detailed explanation.
```

Include at least one edge-case example. Skills that handle "normal" cases well still fail on edges; show one explicitly.

## Workflow Pattern with Checklists

For complex multi-step processes, provide a checklist the agent can copy into its response and track. This prevents skipped steps and gives the user visibility into progress.

```markdown
## PDF form filling workflow

Copy this checklist and check off items as you complete them:
Task Progress:

- [ ] Step 1: Analyze the form (run analyze_form.py)
- [ ] Step 2: Create field mapping (edit fields.json)
- [ ] Step 3: Validate mapping (run validate_fields.py)
- [ ] Step 4: Fill the form (run fill_form.py)
- [ ] Step 5: Verify output (run verify_output.py)

**Step 1: Analyze the form**
Run: python scripts/analyze_form.py input.pdf
This extracts form fields, their types, and coordinates.
Expected output: fields.json with field definitions.

**Step 2: Create field mapping**
Edit fields.json to add values for each field.
Match field names to the data source provided by the user.

**Step 3: Validate mapping**
Run: python scripts/validate_fields.py fields.json
Fix any validation errors before continuing.
Common issues: missing required fields, type mismatches.

**Step 4: Fill the form**
Run: python scripts/fill_form.py input.pdf fields.json output.pdf

**Step 5: Verify output**
Run: python scripts/verify_output.py output.pdf
If verification fails, return to Step 2.
```

## Conditional Workflow Pattern

Guide the agent through decision points. Keep branches concise in SKILL.md; push large branches into reference files.

**Inline branches** (when branches are short):

```markdown
## Document modification workflow

1. Determine the modification type:
   **Creating new content?** -> Follow "Creation workflow" below
   **Editing existing content?** -> Follow "Editing workflow" below

2. Creation workflow:
   - Use docx-js library
   - Build document from scratch
   - Export to .docx format

3. Editing workflow:
   - Unpack existing document
   - Modify XML directly
   - Validate after each change
   - Repack when complete
```

**Reference branches** (when branches are large):

```markdown
## Cloud deployment

Detect target platform, then load the appropriate guide:
**AWS?** -> See [references/aws.md](references/aws.md)
**GCP?** -> See [references/gcp.md](references/gcp.md)
**Azure?** -> See [references/azure.md](references/azure.md)

Each guide covers authentication, resource provisioning,
deployment commands, and rollback procedures.
```

The agent reads only the relevant reference file.

## Feedback Loop Pattern

Validate-fix-repeat cycle for quality-critical operations.

```markdown
## Document editing process

1. Make edits to word/document.xml
2. Validate immediately: python scripts/validate.py unpacked_dir/
3. If validation fails:
   - Review the error message carefully
   - Fix the issue in the XML
   - Run validation again
4. Only proceed when validation passes
5. Rebuild: python scripts/pack.py unpacked_dir/ output.docx
6. Open and test the output document
```

**When to use feedback loops**: Any time the output format is strict (XML, JSON schemas, binary formats), when errors compound (each step builds on the previous), or when the cost of failure is high (data loss, broken documents).

## Progressive Disclosure Patterns

### Pattern 1: High-level guide with on-demand references

```markdown
# PDF Processing

## Quick start

Extract text with pdfplumber:
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
text = pdf.pages[0].extract_text()

## Advanced features

**Form filling**: See [FORMS.md](FORMS.md) for complete guide
**API reference**: See [REFERENCE.md](REFERENCE.md) for all methods
```

### Pattern 2: Domain-specific organization

```plaintext
bigquery-skill/
├── SKILL.md (overview + navigation)
└── references/
    ├── finance.md (revenue, billing)
    ├── sales.md (pipeline, accounts)
    └── product.md (API usage, features)
```

SKILL.md points to domain files. Agent reads only the relevant one based on the user's query. Include a quick-search command for discoverability:

```markdown
## Quick search

grep -i "revenue" references/finance.md
grep -i "pipeline" references/sales.md
```

### Pattern 3: Conditional details

```markdown
# DOCX Processing

## Creating documents

Use docx-js for new documents. See [DOCX-JS.md](DOCX-JS.md).

## Editing documents

For simple edits, modify XML directly.
**For tracked changes**: See [REDLINING.md](REDLINING.md)
```

**Key rule**: Keep references one level deep from SKILL.md. Avoid chains like SKILL.md -> advanced.md -> details.md. Agents may only partially read deeply nested files (using commands like `head -100`), resulting in incomplete information.

## Script Integration Patterns

Scripts run via bash without loading into context. Only their output enters the context window. This makes them ideal for deterministic operations.

### Making script commands portable across agents

Agents run Bash from the user's working directory — typically the project root — not from the skill directory. A bare `python scripts/foo.py` in a SKILL.md stored at `.claude/skills/my-skill/` fails to resolve for Copilot, Codex, Cursor, or Gemini users, because each platform stores the same skill at a different path (`.github/skills/...`, `.agents/skills/...`, `.cursor/skills/...`, `.gemini/skills/...`).

For **cross-platform** skills, two rules:

1. Declare the path convention once near the top of SKILL.md (`## Running scripts bundled with this skill`): paths are relative to SKILL.md, list the common storage locations.
2. Pair every script command with a manual fallback at the same site. Fallbacks at the top of the file alone are missed when the agent jumps directly to a section.

For **single-vendor** skills, prefer the platform's own absolute-path variable. Claude Code substitutes `${CLAUDE_SKILL_DIR}` to the skill's directory; use `python3 ${CLAUDE_SKILL_DIR}/scripts/foo.py` and stop worrying about CWD. Other platforms have analogues; check their docs before assuming the cross-platform rules apply.

### Execute pattern (most common)

```markdown
Run `scripts/analyze_form.py` to extract fields:
python3 scripts/analyze_form.py input.pdf > fields.json

**Fallback.** If the script is unavailable or `python3` is missing,
[manual steps or a checklist the agent can follow by hand].
```

### Execute with clear I/O documentation

```markdown
## scripts/validate_boxes.py

Check for overlapping bounding boxes in form fields.
Input: python3 scripts/validate_boxes.py fields.json
Output: "OK" if no overlaps, or lists specific conflicts with coordinates
Exit code: 0 = pass, 1 = conflicts found

**Fallback.** If the script is unavailable, scan `fields.json` manually
for fields whose x/y ranges intersect.
```

### Read as reference (rare - only when the agent needs to understand the algorithm)

```markdown
See scripts/scoring.py for the ranking algorithm.
The scoring weights are: recency (0.4), relevance (0.3), authority (0.3).
```

## Cross-References Without Force-Loading

When skills relate to each other, avoid `@` syntax that force-loads referenced files and burns tokens before they are needed. Use plain text references with explicit markers:

```markdown
## Prerequisites

Before deploying, ensure all tests pass. If tests fail,
follow the procedures in the `test-runner` skill (REQUIRED).

For performance-critical deployments, also consult the
`load-testing` skill (OPTIONAL) for pre-deployment benchmarks.
```

The REQUIRED/OPTIONAL markers tell the agent how to prioritize without forcing immediate loading. The agent loads referenced skills only when it reaches the step that needs them.

**When to use markers:**
- REQUIRED: Agent must load this skill before proceeding
- OPTIONAL: Agent loads only if the specific condition applies
- RECOMMENDED: Agent should consider loading but can proceed without

## MCP Tool References

When referencing MCP tools in skill instructions, use fully qualified names to prevent "tool not found" errors:

```markdown
Use the BigQuery:bigquery_schema tool to retrieve table schemas.
Use the GitHub:create_issue tool to create issues.
Use the Jira:search_issues tool to find related tickets.
```

Format: `ServerName:tool_name`. The server name must match the MCP server configuration name exactly.
