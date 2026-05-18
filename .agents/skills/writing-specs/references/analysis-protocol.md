# Analysis Protocol

Eight cross-cutting checks every specification MUST pass before the spec is written. Run them in order; each one produces a `GO`, `STOP`, or `FLAG` decision.

- `GO`: no issue found; proceed.
- `STOP`: a documented project rule, ADR, or boundary is violated. Halt. Surface the conflict to the user. Do not resume designing until the user resolves it.
- `FLAG`: the design enters territory the project does not document, or extends an existing rule. Note it explicitly in the spec as a deliberate extension requiring review.

Every check is project-aware: its concrete criteria come from the documents read in Phase 1, not from this protocol. If the project documents none of the concern, record that and treat any related design choice as a `FLAG`.

## Contents

- Check 1: Convention compliance
- Check 2: Architectural layer
- Check 3: Interface boundary
- Check 4: Security and trust boundary
- Check 5: Resource budget
- Check 6: Data model
- Check 7: Runtime model
- Check 8: Requirements source
- Check 9: Prerequisites
- Recording findings

## Check 1: Convention compliance

Verify that the design does not contradict any rule the project explicitly documents.

**Questions to answer:**

1. Does the agent-instruction file (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, etc.) list rules under "Always", "Never", "Ask First", "Boundaries", "Constraints", or similar?
   - The design violates a "Never" rule, "MUST NOT" rule, or equivalent absolute prohibition: `STOP`.
   - The design triggers an "Ask First" rule, "SHOULD ask", or equivalent gate: `FLAG` and require explicit user approval before proceeding.
2. Does the architecture document describe behavior or invariants that this feature must comply with?
   - The design redefines a behavior the architecture already specifies: do not redesign it. Reference the existing definition; `GO`.
   - The design extends behavior the architecture covers only partially: `FLAG` the extension.
3. Does any accepted ADR (decision record with status `accepted`) constrain this feature?
   - The design contradicts an accepted ADR: `STOP`.
   - The design extends an accepted ADR: `FLAG`.
4. Does the product or PRD document mark this feature for a later version, or out of scope for the current target?
   - `FLAG` the version dependency or scope question.

## Check 2: Architectural layer

Determine the layer or module the feature belongs to and verify layering discipline.

**Questions to answer:**

1. Which layer or module does this design belong to? Name it explicitly using the project's own taxonomy (read from the architecture document or the source-tree layout). Examples a project might use: presentation, request handling, business logic, data access, infrastructure; or interface, application, domain, persistence; or controller, service, repository; or any other taxonomy the project documents.
2. Does the design cross documented layer boundaries?
   - Crosses a boundary without justification: restructure to respect layering.
   - Crosses intentionally and the project allows it: `FLAG` and state the justification.
3. Does the design introduce a new top-level component (route, endpoint, worker, service, module) that the architecture does not name?
   - New component without justification: `STOP`. Justify or restructure.
   - New component with justification: `FLAG`. State why the existing extension points are insufficient.
4. Does the design place logic in a layer the project documents as restricted (for example, business logic inside a UI component, or data-access inside a controller)?
   - `FLAG` or `STOP` depending on whether the project lists it as discouraged or prohibited.

## Check 3: Interface boundary

Verify that public surfaces and private internals respect the project's visibility conventions.

**Questions to answer:**

1. What is the public surface this feature introduces (exported functions, public methods, REST endpoints, RPC methods, CLI commands, event topics)?
2. What is the private surface (internal helpers, package-local types, unexported state)?
3. Does the design honor the project's visibility conventions?
   - Languages with explicit visibility (Go's lowercase-private, Java's `private`, Python's leading underscore, Rust's `pub`) MUST follow them.
   - Module-boundary rules (no barrel files, no cross-module imports without going through a public API, no internal package access) MUST be respected as the project documents them.
   - Violation: `FLAG` or `STOP` depending on whether the project lists it as discouraged or prohibited.
4. Is the public surface minimal? Every additional public symbol is a future maintenance commitment.
   - Surface area exceeds what the feature requires: `FLAG` and propose narrowing.
5. Are stability guarantees stated? If the project distinguishes between stable and experimental APIs, the spec MUST state which category the new surface falls into.

## Check 4: Security and trust boundary

Verify security invariants the project documents.

**Questions to answer:**

1. Does the design handle secrets (API keys, OAuth tokens, passwords, encryption keys, signing keys)?
   - Plaintext secrets in logs, responses, application memory, or version control: `STOP`.
   - Secrets stored outside the project's documented secret store: `FLAG`.
2. Does the design accept user input or input from any external source (HTTP requests, message queues, file uploads, environment variables under user control)?
   - Missing validation at the trust boundary: `FLAG`. Specify the validation rule (schema, regex, length, range).
   - SQL or query strings built with string concatenation: `STOP`. Use parameterized queries.
3. Does the design cross a network or process boundary?
   - Identify the trust assumption: is the other side trusted, partially trusted, or untrusted?
   - Identify the authentication mechanism. If the project documents one (mTLS, OAuth, signed tokens, IAM), the design MUST use it.
4. Does the design store, process, or transmit personal data, payment data, health data, or any other regulated category?
   - The project documents regulated-data handling rules (encryption at rest, encryption in transit, retention, deletion, audit logging): the design MUST follow them or `STOP`.
   - The project does not document them but the feature handles regulated data: `FLAG`.
5. Does the design expand any existing trust boundary (broader OAuth scope, additional permission, wider IAM policy)?
   - `FLAG` and require explicit approval.

## Check 5: Resource budget

Verify the design respects whatever resource budget the project tracks.

**Questions to answer:**

1. Does the project document a budget for any of: monetary cost per user or per request, latency targets (p50, p99), throughput, memory, CPU, external API quotas, build size, bundle size?
   - The design exceeds a documented budget: `STOP`. Reduce or justify.
   - The design changes a budget without authorization: `FLAG`.
2. Does the feature introduce a new external dependency (third-party API, paid service, model invocation, data store)?
   - Estimate the cost per invocation and per user.
   - Identify the failure mode if the dependency is unavailable.
3. Does the feature introduce a new performance-sensitive path (synchronous user-facing request, real-time event handler, batch job over large data)?
   - State the expected p99 latency and the load assumption.
   - If the project tracks performance budgets: stay within them or `STOP`.
4. Does the feature increase dependency footprint (new library, new runtime, new service)?
   - The project documents a dependency policy: comply or `STOP`.
   - No policy documented: `FLAG` and state the new dependency.

If the project does not track any of these budgets, state that explicitly in the spec and treat related design choices as `FLAG`.

## Check 6: Data model

Verify schema additions and data-integrity rules.

**Questions to answer:**

1. Where does the project store data shapes? Examples: a single Prisma `schema.prisma`, a Django `models.py`, SQL migration files, Mongoose schemas, Protobuf `.proto` files, OpenAPI components, hand-written DDL.
   - New data shapes added in the wrong location: `STOP`.
2. Does the new schema carry the scoping fields the project requires (`userId`, `tenantId`, `accountId`, or whatever the project uses for multi-tenancy or ownership)?
   - Missing scoping: `FLAG` (or `STOP` if the project documents scoping as mandatory).
3. Does the schema use the project's documented types and conventions (vector columns, JSON columns, enums, foreign-key naming)?
   - Wrong type or convention: `FLAG`.
4. Is deduplication addressed? Many projects rely on a global key (`messageId`, `externalId`, `idempotencyKey`) to prevent duplicate work.
   - Missing deduplication for a feature that processes external data: `FLAG`.
5. Does the schema change require a migration?
   - State the migration strategy (additive, with backfill, with downtime).
   - Schema migration with downtime when the project documents zero-downtime as a constraint: `STOP`.

## Check 7: Runtime model

Verify caching, rendering, concurrency, and scheduling decisions.

**Questions to answer:**

1. Does the project document a caching strategy (cache directives, revalidation tags, TTLs, CDN policy)?
   - The design caches data without naming the invalidation path: `FLAG`.
   - The design uses a caching pattern the project documents as deprecated: `FLAG` and propose the current pattern.
2. Does the project document a rendering or execution model (server-rendered vs client-rendered, sync vs async, sync vs streaming, single-process vs distributed)?
   - The design violates the documented model without justification: `FLAG` or `STOP`.
3. Does the feature require concurrency primitives (mutex, channel, queue, worker, scheduler, lock)?
   - Concurrent design without documented coordination strategy: `FLAG`.
   - Use of a concurrency primitive the project documents as discouraged (raw goroutines without a supervisor, plain `setTimeout` for scheduled work, direct `Thread.start`): `FLAG`.
4. Does the feature require real-time updates (push, streaming, websocket, server-sent events)?
   - The project documents a default transport (polling, server-sent events, websockets): use it.
   - Introducing a new transport: `FLAG` and justify.
5. Does the feature require background processing (cron, scheduled job, queue worker)?
   - State which scheduler or queue the project uses.
   - Inventing a new scheduler when the project ships one: `FLAG`.

## Check 8: Requirements source

Verify external requirements have been fetched and incorporated.

**Questions to answer:**

1. If a tracker reference (Jira ID/URL, GitHub issue, Linear/Asana/Notion link) was provided:
   - Fetch the reference using whichever tool is available (MCP server, CLI, web fetch).
   - Extract: title, description, acceptance criteria, labels, components, parent and child links, attached design pages.
   - Tracker reference not fetched: `STOP`. Do not proceed.
2. Check linked design pages (Confluence, Notion, Google Docs) for:
   - Architectural context the agent-instruction files do not cover.
   - API contracts with external systems.
   - Domain definitions.
3. Verify the spec reflects every acceptance criterion the tracker lists. A spec that ignores acceptance criteria is incomplete.
4. If no tracker reference is provided and the user did not paste requirements:
   - Verify the user prompt itself contains enough detail to specify a feature.
   - Insufficient detail: ask the user for specific missing inputs (target users, success criteria, scope boundaries). Do not invent them.

If no tracker tool is available and no tracker reference was provided, skip this check and `GO`.

## Check 9: Prerequisites

Verify the feature does not depend on work that has not been done yet.

**Questions to answer:**

1. Does the design assume a component, schema, interface, library, or capability that the current codebase does not have?
   - Identify the assumed prerequisite by name.
   - Verify whether the prerequisite is documented as planned (in roadmap, milestone tracker, PRD, or architecture document).
2. Does the project organize work in milestones, phases, releases, or epics?
   - Identify which milestone or phase this feature belongs to.
   - Verify all prerequisite milestones are complete. Look for completion markers in the tracker, in the project's roadmap document, or in ADRs.
3. Does the feature exceed the scope of a single implementation session, story, or ticket?
   - State the rough scope estimate (number of files, modules, layers touched).
   - If the feature is genuinely too large, propose a decomposition before continuing.

**Decisions:**

- All prerequisites complete and feature scoped to a single implementation unit: `GO`.
- Prerequisite missing and not planned: `STOP`. Surface the gap. Do not design features that depend on unbuilt foundations.
- Prerequisite missing but planned: `FLAG` the dependency and state which milestone or ticket must complete first.
- Feature exceeds scope of a single unit: `FLAG` and propose decomposition.

If the project does not organize work in milestones or phases, skip the milestone sub-question and answer 1 and 3 only.

## Recording findings

After completing all nine checks, write a one-line verdict for each check before proceeding to Phase 3. The verdicts make the analysis traceable in the spec and prevent the agent from silently skipping a check.

Copy this template into the reasoning trace and into the spec's opening "Compliance check" table:

```
Analysis findings:
1. Convention compliance: [GO | STOP | FLAG] - [one-sentence cite or note]
2. Architectural layer: [GO | STOP | FLAG] - [layer name; crosses boundaries: yes/no]
3. Interface boundary: [GO | STOP | FLAG] - [public surface summary; visibility OK]
4. Security and trust boundary: [GO | STOP | FLAG] - [boundary crossed: yes/no; rule cited]
5. Resource budget: [GO | STOP | FLAG] - [budget tracked: yes/no; within limits: yes/no]
6. Data model: [GO | STOP | FLAG] - [schema location; scoping fields present: yes/no]
7. Runtime model: [GO | STOP | FLAG] - [caching/rendering/concurrency notes]
8. Requirements source: [GO | STOP | FLAG] - [tracker fetched: yes/no/N/A]
9. Prerequisites: [GO | STOP | FLAG] - [prerequisites complete: yes/no]
```

A check answered "GO - N/A" is acceptable when the concern does not apply to the feature (for example, a docs-only feature is `GO - N/A` for Check 6). A check the agent did not run is not acceptable; either run it or state explicitly why it was skipped.

If any check is `STOP`, halt and surface the conflict to the user. Do not proceed to Phase 3. If any check is `FLAG`, the spec MUST document the flagged item in either the appropriate technical-architecture subsection or the open-questions section.
