---
description: "Architectural review of a specification before implementation begins"
---

Your task is to evaluate whether a specification is ready to be implemented: aligned with the project, feasible given the codebase, free of structural risk, complete enough to be implemented without divergent interpretation, with appropriate quality-attribute tradeoffs.

## Task

- Use the `review-spec` Agent Skill to drive every phase: resolve the task reference, build project context, read the specification thoroughly, evaluate it against the six dimensions (alignment, feasibility, risks, completeness, tradeoffs, recommendations), then compose the review.
- The command receives **two arguments**:
  1. **Task name** - a brief description of the feature OR a GitHub issue reference (`https://github.com/owner/repo/issues/123`, `owner/repo#123`, `#123`).
  2. **Spec path** - the path to the specification markdown file.
- If the task argument is a GitHub issue reference, the skill's Phase 1 fetches context with `gh issue view <ref> --json title,body` and uses the issue title as the task name and the body as additional context. If the argument is plain text, the skill treats it as the task name verbatim.
- Read the spec file in its entirety before evaluating - it is the primary subject of this review.
- Discover project context by searching the conventional locations - project context files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CONTRIBUTING.md`, `README.md`), architecture documentation, ADR sets, build manifests, and schema files. Do not assume specific filenames or paths; the skill's discovery rules apply.

## Skill Enforcement

**MANDATORY:** Apply the `review-spec` Agent Skill verbatim.

The skill is the single source of truth for *how* to evaluate the spec, classify findings, and structure the report. The project's context files are the source of truth for *what* the architecture, layering, naming conventions, and review standards are. Consult each at the moment the skill calls for it.

**Process:**

- Load the `review-spec` Agent Skill before reading the specification.
- Walk through every phase in order. Do not skip, merge, or abbreviate any phase. Each gate prevents a documented failure mode (ungrounded reviews, missed conventions, ambiguity blindness, severity inflation).
- If the skill is unavailable in this environment, stop and report the failure. Do not improvise a replacement protocol.
- Write the final review to `.reviews/Review-{spec-name}.md` per the skill's output rules. Print the path of the file written.

## Constraints

- **Review only.** Do not write, modify, refactor, or restructure any source code or the spec itself. A finding proposes a change; the spec author applies it later. Do not commit, branch, or open pull requests.
- **Spec-first, code-second.** This command reviews a specification, not an implementation. If an implementation already exists and the question is whether the code matches the spec, that is a different command - `audit-spec`.
- **Ground every finding in evidence.** A section of the spec, a file in the codebase, a named pattern, an ADR. Findings without anchors are opinions.
- **Honor existing decisions.** If the project has decided not to use library X (visible in ADRs or context files), do not recommend X. The spec must align with the project, not the reviewer's preferences.
- **No severity inflation.** Reserve `Critical` for issues that block implementation. Reserve `Significant` for issues that degrade quality. Reserve `Observation` for naming and minor style. The skill's severity rubric is authoritative.
