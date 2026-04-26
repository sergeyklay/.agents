# Step 6 Summary — Template

This is the template for the final summary the skill produces for the human operator. All reasoning, all evidence, all decisions belong in this document. Nothing goes to the reviewer.

## Template

Copy this block verbatim. Fill every section. Write `_(none)_` as the body of any section with zero comments so the human operator can see the category was considered.

```markdown
## Review Resolution Summary

### Source
{GitHub PR #N / Inline feedback / Mixed}

### Tracker
{discovered tracker — e.g., "GitHub Issues (repo `owner/name`)" / "Jira (project ABC)" / "GitLab Issues (project owner/name)" / "n/a — no items deferred"}

### Context7 Evidence Log

| # | Comment | Library | Finding | Verdict |
|---|---|---|---|---|
| … | … | … | … | REVIEWER CORRECT / REVIEWER INCORRECT / AMBIGUOUS / FALLBACK: web / N/A |

### Applied (N comments)

- **[@reviewer, file:line]** — What was changed and why. C7 validation: {row # or N/A}.

### Deferred to Backlog (N comments)

- **[@reviewer, file:line]** — Why deferred. Tracker outcome: {ticket reference} (created via {discovered skill / manual fallback}) / {ticket reference} (existing) / not added ({reason}).

### Skipped — Already Addressed (N comments)

- **[@reviewer, file:line]** — Why it no longer applies (commit, PR, or branch that resolved it).

### Skipped — Subjective (N comments)

- **[@reviewer, file:line]** — The stylistic trade-off. C7 validation: N/A — no library API claim.

### Rejected (N comments)

- **[@reviewer, file:line]** — Technical rationale. C7 evidence: {finding, library, version} — or architectural / context-file citation ({the constraint or invariant the suggestion would violate}).

### Needs Discussion (N comments)

- **[@reviewer, file:line]** — The open question and both sides. C7 status: {ambiguous / not indexed / version conflict / spec-undetermined}.

### Stale / Outdated (N comments)

- **[@reviewer, file:line]** — What changed and where the referenced entity went.
```

## Section rules

- **All seven category sections MUST appear** in every summary, even those with zero comments. An empty section uses `_(none)_` as its body so the human operator can see the category was evaluated.
- **File:line citations are mandatory** for every entry except comments explicitly classified as "general feedback" in Step 3.
- **Internal tags like `[C7-REQUIRED]` MUST NOT appear.** They are working annotations for Steps 2 and 3 only. A tag leaked into the summary is a protocol violation.
- **No reviewer-facing language.** Write as a maintainer reporting to themselves. Avoid phrasing like "we should tell the reviewer that…" — the reviewer never reads this.
- **Tracker outcomes must be specific.** Use the exact form `{ticket reference} (created)`, `{ticket reference} (existing)`, or `not added ({architecture conflict / out of roadmap horizon / duplicate of …})`. Never just "ticket created." The ticket reference is whatever the project's tracker uses — `#42`, `ABC-123`, a Linear `ENG-1234` URL slug, etc.
- **Deferred entries note the creation path.** When a sibling skill handled the create operation, name the discovery ("via discovered skill"); when manual fallback was used, name that ("manual fallback — no managing skill found"). The human operator needs to know which path was taken to verify against project conventions.
- **Evidence log is complete.** Every `[C7-REQUIRED]` comment from Step 2a must have a row. Use N/A in the Verdict column only for comments that turned out not to make a library claim after all.
- **Rejected entries carry specific evidence.** "Context7 disagreed" is insufficient. State the finding, the library, and the version the finding applies to — or name the architectural invariant or context-file rule the suggestion would violate.
