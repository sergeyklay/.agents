## Spec Review: {Title}

**Created at:** {ISO timestamp} \
**Issue ID:** {#NNN or ABC-NNN or N/A} \
**Feature:** {One-sentence summary of the feature or change.} \
**Source spec:** `.specs/Spec-{TASK_NAME}.md`

### Context Summary

{2–4 sentences: the reviewer's understanding of what the spec proposes. This surfaces misunderstandings before the rest of the review is acted upon. If the author reads this and says "that is not what I meant", the rest of the review needs revisiting.}

### Recommendation: {READY | NEEDS REVISION | NOT READY}

- **READY** — no `Critical` issues; any `Significant` concerns are scoped and resolvable during implementation rather than blocking it.
- **NEEDS REVISION** — one or more `Significant` concerns must be addressed in the spec before implementation begins; no `Critical` issues.
- **NOT READY** — one or more `Critical` issues block implementation; the spec must be substantively revised.

### Critical Issues

Issues that block implementation. Each must be resolved in the spec before coding begins.

#### {SHORT_TITLE}

- **Dimension:** {Alignment | Feasibility | Risks | Completeness | Tradeoffs}
- **Spec location:** §{section} (line {N})
- **Finding:** {what the spec does or fails to do, in one or two sentences}
- **Evidence:** {citation — `file:line` in the codebase, ADR identifier, project context-file rule, named pattern}
- **Recommendation:** {what the spec author must change; reference existing project patterns where possible; name the tradeoff the recommendation introduces}

(Repeat per `Critical` finding. If none: write `_None._`)

### Significant Concerns

Issues that should be addressed before implementation. Will degrade quality if left unresolved.

(Same structure as Critical Issues. If none: `_None._`)

### Observations

Minor items worth noting. Do not block implementation; documented for awareness.

(Same structure, abbreviated. If none: `_None._`)

### Strengths

What the spec gets right. Calibrates the review and documents decisions worth preserving in future revisions.

- {short bullet — name the specific strength and why it matters in this project's context}
- {short bullet}

### Open Questions

Items the reviewer could not decide from the spec or the project context. Each must be answered before implementation begins.

- {question — name who can answer it if known}
- {question}

(If none: `_None._`)
