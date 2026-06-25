---
name: writing-specs
description: "Write technical specifications from feature requests, prompts, or tracker references. Use when asked to specify, architect, design, write a spec, define requirements, create a technical specification, analyze a feature request, or produce a specification document. Also use when given a tracker reference (Jira, GitHub issue, Linear, Asana, etc.) and a specification is the expected output. Do NOT use for code review, implementation, implementation planning, or reviewing existing specs. Produces structured specification documents the implementer can build from without further clarification."
metadata:
  author: Serghei Iakovlev
  version: "1.1"
  category: planning
---

# Writing Specifications

Transform a feature request into a specification rigorous enough to implement without further clarification. Every section is a binding contract between architect and implementer. Ambiguity in a spec causes real engineering delay; design errors caught here are orders of magnitude cheaper than design errors caught in code review.

This skill is stack-agnostic and project-agnostic. Concrete rules (allowed libraries, forbidden patterns, budget thresholds, schema location, layering, naming) come from the project documents, not from this skill. Read those documents first; then design within them; then flag every deviation explicitly.

## Running scripts bundled with this skill

Script paths in this document (e.g. `scripts/`) are resolved relative to **this** SKILL.md file, not to your current working directory. If a relative command fails to resolve, prefix it with the path your platform loaded this SKILL.md from.

**Fallback.** If `python3` cannot be located, analyze the script's purpose and logic and execute its intent with available tools, but warn the user that python is not available and the logic was executed with a fallback approach that may not be perfect.

## Project context: reading order

These documents are the authority your specification must conform to. Do not start designing until you have read whichever of them the project ships. Stop reading once you have enough; do not load files that do not exist.

1. **Project-level agent instructions**, in this priority order: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`. Read every file that exists; do not assume any of them is canonical. When they disagree, treat the most recently modified one as authoritative and surface the conflict in your output.
2. **Documentation index**: if `docs/` exists, read `docs/README.md` (or the closest equivalent: `docs/index.md`, `docs/SUMMARY.md`, `docs/DIGEST.md`). Use it as a map. Open the individual documents it references only when they constrain the feature you are specifying.
3. **Architecture and product docs** named by the documentation index: `architecture.md`, `ARCHITECTURE.md`, `design.md`, `PRD.md`, `product.md`, or whatever name the project uses.
4. **Decision records**: `docs/decisions/`, `docs/adr/`, `adr/`, `ADR/`, or whatever path the project uses. Read the index file first; read individual records only when they constrain this feature. Treat accepted decisions as architectural law.
5. **Language and style rules** the project ships under `.agents/rules/`, `.github/instructions/`, `.copilot/instructions/`, `.claude/rules/`, or referenced from the agent-instruction file. These constrain spec prose (RFC 2119 keywords, banned vocabulary, comment style, etc.).

If the project ships none of the above, say so explicitly in the specification's opening section. Note that the spec is being written without project-context grounding and propose what context files the project should add.

When a digest and its full document disagree, the full document wins. Digests are lossy summaries; if you spot drift, flag it.

## Input types

The specification input is one of:

- **Feature request**: a natural-language description of desired behavior.
- **User prompt**: an informal description, question, or sketch.
- **Tracker reference**: a Jira ID/URL, GitHub issue, Linear/Asana/Notion link. Fetch the reference before designing: title, description, acceptance criteria, labels, components, linked tickets, linked design pages. Use whichever MCP server, CLI, or web fetch is available. If none is available, ask the user to paste the content rather than guessing.

## Workflow

Four phases, executed sequentially. Do not skip a phase, do not reorder phases, do not collapse two phases into one. Each phase has a defined gate; the gates exist because skipping any of them produces a defect class that surfaces later.

Copy this checklist into your reasoning trace and mark items as you complete them:

- [ ] Phase 1: Read project context (agent-instruction files, docs index, ADRs, rules)
- [ ] Phase 2: Run the nine-point analysis protocol and record one verdict per check
- [ ] Phase 3: Write the specification document
- [ ] Phase 4: Validate the specification against the quality checklist

### Phase 1: Read project context

Read the files listed in "Project context: reading order" above. Extract concrete, named constraints, not impressions:

- The agent-instruction files yield boundary rules (often "Always / Ask First / Never" or similar). Quote the exact rules that apply.
- The architecture document yields component names, module boundaries, layering rules, hard constraints. Quote the section anchors you will cite later.
- The product or PRD document yields feature scope, in-scope and out-of-scope boundaries, target users.
- The ADRs yield accepted decisions you must align with. Read the index; read records that touch this feature.
- The style rules yield prose requirements (RFC 2119 usage, banned vocabulary, em-dash policy, heading case).

If a tracker reference was provided, fetch it now and capture: acceptance criteria, linked design pages, labels, components, scope flags.

### Phase 2: Run the analysis protocol

Before designing anything, run all nine cross-cutting checks. Each one produces a `GO`, `STOP`, or `FLAG` decision. See [references/analysis-protocol.md](references/analysis-protocol.md) for the full protocol with concrete questions, evidence rules, and decision criteria.

Summary of the nine checks:

1. **Convention compliance**: does the design contradict any rule from the agent-instruction files, any accepted ADR, or the architecture document?
2. **Architectural layer**: which layer or module does this belong to per the project's documented architecture? Does the design cross layer boundaries?
3. **Interface boundary**: what is the public surface; what stays private; are visibility and module-boundary conventions respected?
4. **Security and trust boundary**: secrets, auth, input validation, external trust, data residency, encryption requirements per the project's documented rules.
5. **Resource budget**: cost, latency, throughput, memory, quota, dependency budget, whatever budget the project explicitly tracks. If the project tracks none, state so.
6. **Data model**: schema location and ownership, migration policy, scoping rules (per-tenant, per-user, per-account), deduplication, retention, indexing policy per project conventions.
7. **Runtime model**: caching strategy, rendering model, concurrency primitives, scheduling, deployment topology per project conventions. Where the project documents deprecated patterns, design against the current one.
8. **Requirements source**: has the tracker reference (if any) been fetched and incorporated? Are acceptance criteria captured?
9. **Prerequisites**: does the design depend on work that is not done? Is the feature scoped to a single implementation unit?

After running all nine checks, record one verdict per check using the template at the end of `references/analysis-protocol.md`. Copy the verdicts into both the agent's reasoning trace and the spec's opening "Compliance check" table. A check the agent did not run is not acceptable; either run it or state explicitly why it does not apply.

If any check produces a `STOP`, surface the conflict and halt. Do not proceed until the user resolves it. If any check produces a `FLAG`, document it explicitly in the spec as a deliberate extension requiring review. A specification that silently violates an accepted decision is worse than no specification.

### Phase 3: Write the specification

Determine the output path:

1. If the project's agent-instruction files document a spec directory, use it.
2. Otherwise if `.specs/` already exists in the repository, use it.
3. Otherwise if `docs/specs/` or `specs/` exists, use that.
4. Otherwise default to `.specs/` and create it.

File name: `Spec-{slug}.md`. Derive `{slug}` in this order:

1. If a tracker ID is present (e.g. `BP-138`, `SORT-42`, `#238`), use it: `Spec-BP-138.md`, `Spec-238-codex-agent-adapter.md`.
2. Otherwise, derive a concise kebab-case name from the feature title: `Spec-Email-Classification.md`.

Use the same slug across all related artifacts (spec, review, plan) so traceability is automatic.

Use the template in [assets/spec-template.md](assets/spec-template.md) as the structural foundation. Fill every section. Do not leave placeholders. Each section that genuinely cannot be filled MUST include a note explaining why and what information is needed to fill it.

#### Output rules

These rules are non-negotiable. Every rule reflects a class of defect that delays implementation.

1. **No implementation.** Do not write function bodies, hook bodies, or full component implementations. The specification defines `WHAT`, not `HOW`. Pseudo-code is allowed; runnable code is not.
2. **Interfaces over implementations.** Define the shape of data and the signatures of functions. Use the project's actual type language (TypeScript types, Go interfaces, Python type hints, OpenAPI schemas, Protobuf, Prisma model definitions, JSON Schema, whatever the project uses for shape definitions). The shape is the contract.
3. **Schemas are design.** Where the project defines storage via a schema file (Prisma, SQL DDL, Mongoose, SQLAlchemy, ORM-of-choice), define schema additions in that schema's syntax, not raw SQL. The schema is the specification.
4. **Pseudo-code for logic; tables for structure.** Describe algorithms as numbered steps or pseudo-code blocks following the project's documented style. Do not write runnable code. For state machines, use a transition table (columns: from-state, event, to-state, action). For cross-component interactions, use a numbered list of `actor -> actor: action` lines. Do not emit Mermaid or ASCII diagrams; the spec's downstream readers (validator, implementer agent) consume the same information from tables and pseudo-code without the rendering layer that makes diagrams useful to humans, and a duplicated format multiplies the surface where prose, pseudo-code, and diagram can drift.
5. **Cite project conventions inline.** When the spec relies on an architecture-document section, ADR, or agent-instruction rule, cite the source by anchor link, filename, or rule name. Form: `[Section 5.1](../docs/architecture.md#51-tier-0)`, `per ADR-0014`, `per CLAUDE.md "Never" boundary`. Every design decision that traces to project context gets a citation. Every decision that does not MUST be flagged as a spec extension requiring review.
6. **No banned patterns.** Where the project lists banned libraries, banned patterns, or deprecated APIs (in agent-instruction files, ADRs, or rules), do not specify them. If a banned pattern is the only feasible solution, that is a `STOP` from Phase 2 and the spec does not get written until resolved.
7. **No em-dashes.** Use commas, parentheses, periods, semicolons, or colons. Em-dashes are a strong LLM-generated-text signal and many projects ban them outright; assume they are banned unless the project explicitly permits them.
8. **Active voice; one term per concept.** Choose one name per concept, use it everywhere, do not alternate synonyms. Write in active voice unless the actor is irrelevant.

### Phase 4: Validate the specification

Load [references/quality-checklist.md](references/quality-checklist.md) and run every item in it against the drafted spec. The checklist combines IEEE 830 / ISO 29148 requirement-quality attributes (Correct, Unambiguous, Complete, Consistent, Ranked, Verifiable, Modifiable, Traceable) with a catalogue of the most frequent spec-quality defects (vague verbs, missing error paths, implicit ordering, unspecified defaults, orphaned references, oversized steps, quantifiers without thresholds, cross-references to unnamed components, banned vocabulary).

Apply the "two engineers test" to every numbered requirement: can two engineers read the requirement and reach the same implementation? If not, rewrite with concrete values, explicit types, or a worked example.

If `scripts/validate_spec.py` is bundled with this skill and `python3` is available, run it for mechanical structural checks (filename pattern, required sections present, risk-table data rows, no em-dashes, forward-slash paths). Treat its output as a complement to the manual checklist, not a replacement.

If validation fails, fix the issues and re-run the checklist. Do not report the spec complete until every item passes.

## Writing standards

The spec is prose with structure. Follow these rules, deriving project-specific overrides from the style rules read in Phase 1.

- **RFC 2119 keywords** (MUST, MUST NOT, SHOULD, SHOULD NOT, MAY) for binding requirements; capitalize them when normative. Do not use them in narrative prose.
- **Every requirement is testable.** If you cannot describe how a reviewer would verify a requirement, rewrite it until you can. "The system handles errors gracefully" is not testable. "On a 5xx response from service X, the client retries up to 3 times with exponential backoff starting at 100 ms" is.
- **No em-dashes.** Replace with commas, parentheses, periods, semicolons, or colons.
- **One term per concept.** Pick a name; use it everywhere; do not alternate with synonyms for variety.
- **Active voice by default.** Passive voice is acceptable when the actor is irrelevant or unknown.
- **Sentence-case headings** unless the project's style rules say otherwise.
- **No sycophantic openers** ("Great question!"), **no hedge stacking** ("might possibly potentially"), **no formulaic closers** ("Hope this helps!"). The spec is a contract, not a chat reply.
- **No marketing vocabulary.** Replace "leverage" with "use", "utilize" with "use", "robust" with the concrete property you mean, "seamless" with "automatic" or "transparent".

When the project's style rules conflict with the rules above, the project's style rules win for prose specific to that project. The rules above are the floor.
