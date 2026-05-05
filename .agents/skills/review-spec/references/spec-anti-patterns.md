# Specification Anti-Patterns

Use this reference at Phase 4 of `review-spec` to recognize common failure modes in specs. Each anti-pattern below has a recognition signal, examples, the impact on implementation, and the dimension it most often surfaces under. The catalogue is organized by category; the severity rubric at the end maps every instance to `Critical` / `Significant` / `Observation`.

The patterns below are grounded in IEEE 830 / ISO/IEC 29148 requirement-quality attributes (correct, unambiguous, complete, consistent, ranked, verifiable, modifiable, traceable) and in defects observed in real spec-writing skills. They are the patterns reviewers actually catch in practice.

## Contents

- Writing-quality defects: vague language, untestable requirements, over-specification
- Structural-completeness defects: missing error paths, implicit ordering, unspecified defaults, unstated assumptions and hidden coupling
- Traceability defects: traceability gaps
- Architectural-integrity defects: implementation in spec, architectural-decision contradiction
- Decomposition defects: oversized steps
- Severity rubric

---

## Writing-quality defects

### Vague language

**Signal.** The spec describes a behavior at a level too abstract to implement. Includes vague verbs ("handle errors appropriately"), ambiguous quantifiers ("usually", "typically", "should"), and architectural namedropping (invoking a pattern name like "Saga" or "CQRS" without specifying its semantics in this project).

**Examples.**

- "The system handles concurrent requests appropriately."
- "Usually returns within 100ms."
- "Use a Saga pattern for the multi-step transaction." (Choreography or orchestration? Compensation guarantees?)
- "Apply DDD principles." (Which patterns? Aggregate boundaries?)

**Impact.** Two implementers reading the same spec produce incompatible systems. Review uncovers the divergence only after code exists.

**Surfaces under.** Completeness (Dimension 4); for namedropping, also Alignment (Dimension 1).

### Untestable requirements

**Signal.** The requirement looks definitive but cannot be verified by a test. Often paired with vague language but can also occur with concrete-sounding but unfalsifiable claims.

**Examples.**

- "The service is highly available." (What SLA? Measured how? Over what window?)
- "The cache invalidates when needed." (What test would prove this?)
- "Performance is acceptable under normal load." (Define normal. Define acceptable.)

**Impact.** No way to confirm the implementation meets the requirement. Implementer ships, defect appears in production, dispute follows over whether the spec was met.

**Surfaces under.** Completeness (Dimension 4).

### Over-specification

**Signal.** The spec mandates implementation details that should be left to the implementer. Locks in suboptimal choices and makes the spec brittle.

**Examples.**

- "Use a hashmap with initial capacity 16 to store sessions." (Why this number? Why hashmap?)
- "Loop over the items in reverse order." (Implementation choice, not a requirement.)
- "Allocate a buffer of exactly 4096 bytes." (Magic number with no justification.)

**Impact.** Forces choices that may conflict with the project's actual constraints (different runtime, different scale, different testing tools). Implementer either ships suboptimal code or deviates and creates spec drift.

**Surfaces under.** Feasibility (Dimension 2), Tradeoffs (Dimension 5).

---

## Structural-completeness defects

### Missing error paths

**Signal.** Every operation that can fail must have an explicit error category and behavior (retry, abort, skip, log-and-continue, propagate, terminate). The spec describes the happy path but is silent on failure modes.

**Examples.**

- "Fetch the user's profile." (What if the user does not exist? What if the upstream is down?)
- "Persist the record to the database." (Constraint violation? Connection lost mid-write? Retry policy?)
- "Call the third-party API." (Rate limit response? 5xx? Timeout? Network partition?)

**Impact.** Implementer invents an error policy. Different implementers invent different policies. Operations fail silently in production, or fail loudly in places the spec did not anticipate.

**Surfaces under.** Completeness (Dimension 4), Risks (Dimension 3).

### Implicit ordering

**Signal.** The spec describes multiple operations without stating whether they execute in order, concurrently, or independently. Sequencing is left to the implementer.

**Examples.**

- "The system writes the audit record and sends the notification." (Write first, then notify? Best-effort notify? Both atomic?)
- "Validate the input and persist the record." (Validate-then-persist is obvious, but what about cross-row validation that requires reading other records first?)
- "Refresh the cache and reindex the search store." (Independent? Ordered? Either operation a hard dependency for the other?)

**Impact.** Implementer chooses an ordering. Production hits a race condition or partial-failure scenario the spec did not consider. The "correct" behavior under the failure becomes the next argument.

**Surfaces under.** Completeness (Dimension 4), Risks (Dimension 3).

### Unspecified defaults

**Signal.** The spec introduces a configuration field, a parameter, or an environment variable without stating its default value or the rationale for that default.

**Examples.**

- "The retry count is configurable via `MAX_RETRIES`." (What is the default? Why?)
- "Workers can be scaled horizontally with `WORKER_COUNT`." (Default? Behavior at zero? At negative?)
- "Set `FEATURE_X_ENABLED=true` to enable the feature." (Default off or default on? What's the rollout strategy?)

**Impact.** Implementer picks a default. Reviewer disagrees. Operators run with the wrong default in production.

**Surfaces under.** Completeness (Dimension 4).

### Unstated assumptions and hidden coupling

**Signal.** The spec assumes something about the environment, project state, scale, or external dependencies without saying so. Includes unstated assumptions about runtime ("we'll be on a single instance") and hidden coupling to unnamed components ("publish an event" — to which broker?).

**Examples.**

- "Read the user's session." (Where do sessions live? Cookie? Redis? JWT?)
- "Publish an event for downstream consumers." (Which broker? What schema? What retry semantics?)
- The spec assumes a single instance — no concurrent execution defined for a service that will be horizontally scaled.
- The spec assumes data is small — no pagination defined for what becomes a large list.

**Impact.** Implementation works in development, breaks in production. Implementer either guesses the coupling (fragile) or has to ask, which forces ad-hoc design decisions outside the spec.

**Surfaces under.** Completeness (Dimension 4), Risks (Dimension 3), Feasibility (Dimension 2).

---

## Traceability defects

### Traceability gaps

**Signal.** Design decisions in the spec do not anchor to a section of the architecture document or to an accepted ADR — OR the anchor is broken (the section the spec cites does not exist).

**Examples.**

- "Per the architecture, we serialize via Avro." (No section reference; reviewer must search the architecture doc to verify.)
- "Following [Section 9.6](../docs/architecture.md#96-workspace-safety)..." (Reference looks valid, but `architecture.md` has no §9.6, or §9.6 is about a different topic.)
- A fundamental design decision (e.g., "we will introduce a new database") with no citation at all — meaning the architect has not justified it against the existing project.

**Impact.** Reviewer cannot verify that the spec aligns with the project's architecture. Implementer cannot find the source of truth. Future revisions of the architecture doc do not propagate to the spec because the link does not exist.

**Surfaces under.** Alignment (Dimension 1).

---

## Architectural-integrity defects

### Implementation in spec

**Signal.** The spec contains function bodies, runnable code, full class implementations, or executable scripts. The spec is meant to define WHAT, not HOW.

**Acceptable.** Interface signatures, type definitions, schema declarations, pseudo-code for algorithms, configuration examples (with annotations), CREATE TABLE DDL.

**Not acceptable.**

- Full method bodies with control flow.
- Complete React components with hooks and event handlers.
- Goroutine logic, channel coordination, full async pipelines.
- Working SQL queries beyond the schema definition.

**Impact.** The spec becomes a draft of the implementation. Changes in implementation force changes in the spec, breaking the contract direction (spec → code, not code → spec). Reviewers spend time reviewing code in a document meant for design review.

**Surfaces under.** Tradeoffs (Dimension 5), Recommendations (Dimension 6).

### Architectural-decision contradiction

**Signal.** The spec contradicts an established architectural decision: an accepted ADR, an explicit "Never" rule in `AGENTS.md` / `CLAUDE.md`, a layer-boundary rule, or an adapter-boundary rule.

**Examples.**

- ADR-0042 declared the project will not adopt Kafka; the spec proposes a Kafka-based event bus.
- Project context files mandate `agent_*` / `tracker_*` naming in the core; the spec introduces `jira_*` types in a non-adapter package.
- The architecture defines a strict `domain → application → infrastructure` layering; the spec routes infrastructure imports through the domain layer.

**Impact.** Implementing the spec violates a decision the project has already made and documented. The implementation either gets blocked at code review, or worse, slips through and creates inconsistency with the rest of the codebase.

**Surfaces under.** Alignment (Dimension 1).

---

## Decomposition defects

### Oversized steps

**Signal.** A single implementation step in the spec is too large to be reviewed or implemented atomically. Common thresholds: more than ~300 lines of production code, or touching more than ~3 files in unrelated areas.

**Examples.**

- "Step 1: Implement the new orchestrator." (Touches scheduling, state management, retry, and observability all at once — should be ≥4 separate steps.)
- "Refactor the persistence layer to support multi-tenancy." (Affects every model, every query, every migration; needs decomposition into bounded sub-steps.)

**Impact.** PRs become un-reviewable. Implementation is brittle: errors in one part block the whole step. Migration paths and partial rollouts become impossible.

**Surfaces under.** Feasibility (Dimension 2).

A related but distinct defect is **missing migration path**: when an interface or schema change has implementations that depend on the old shape, the spec must enumerate the migration steps for every dependent. Without it, the spec is implementable in isolation but breaks every existing consumer.

---

## Severity rubric

These anti-patterns map to severity levels in your review:

| Severity | Definition | Impact on implementation |
|---|---|---|
| `Critical` | The spec is not implementable as written, OR implementing it would violate a documented project invariant. | Implementation cannot start, or would cause harm if started. |
| `Significant` | The spec leaves a non-trivial decision to the implementer that the architect should have made, OR introduces measurable quality degradation. | Implementation succeeds, but with avoidable defects, divergent decisions, or quality regressions. |
| `Observation` | The spec could be clearer or more aligned, but the gap is small. | No material impact; documented for awareness. |

### Anti-inflation rules

These rules counteract the well-documented tendency of reviewers to over-grade for thoroughness. Inflation makes the severity classification useless because every finding becomes "critical."

1. **Stylistic disagreement is `Observation`.** If you would have written it differently but the spec is correct as written, it is not `Significant`.
2. **Naming-only divergence is `Observation`** unless the spec violates an explicit naming convention from the project context files.
3. **Missing error paths and implicit ordering are `Significant` at minimum.** They almost always become defects in production.
4. **Architectural-decision contradiction is `Critical`.** Implementing the spec would violate a documented decision; the spec must be revised before implementation begins.
5. **Implementation-in-spec is `Significant`** when it merely bloats the document; **`Critical`** when it locks in a specific implementation that conflicts with project constraints.
6. **Architectural namedropping is `Significant`** at minimum, because it conceals decisions that need to be surfaced — even if you suspect the author had specific semantics in mind.
7. **Untraceable decisions are `Significant`** for non-trivial design choices; **`Critical`** for choices that contradict the architecture doc.
