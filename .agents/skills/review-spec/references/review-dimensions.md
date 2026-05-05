# Review Dimensions

Use this reference at Phase 4 of `review-spec` whenever evaluating a spec along the six dimensions. Each dimension has a focusing question, an evidence-gathering checklist, and the typical failure modes that map to severity levels.

## Contents

- Dimension 1: Alignment
- Dimension 2: Feasibility
- Dimension 3: Risks
- Dimension 4: Completeness
- Dimension 5: Tradeoffs
- Dimension 6: Recommendations

## Dimension 1: Alignment

**Focusing question.** Does the spec align with the existing architecture, patterns, and conventions identified in Phase 2? Where it deviates, is the deviation justified?

**Evidence to gather.**

- Cross-reference each architectural choice in the spec against ADRs, project context-file rules, and existing patterns from Phase 2.
- Flag every "we will introduce X" where X has already been considered and rejected (visible in ADRs or context files).
- Flag every implicit choice that conflicts with a project convention even if the spec does not explicitly mention the convention.

**Severity mapping.**

- **Critical** — spec violates an explicit "Never" rule from project context files (e.g. a forbidden library, a banned pattern, a layer-boundary breach).
- **Significant** — spec deviates from an established pattern without justification, creating divergence cost for future implementers.
- **Observation** — spec uses a different but equivalent expression of an existing pattern.

## Dimension 2: Feasibility

**Focusing question.** Given the current codebase structure, tech stack, and existing abstractions, is the spec implementable as written? Are there hidden complexities or dependencies the spec does not account for?

**Evidence to gather.**

- For each integration point the spec mentions, verify the integration surface exists in the codebase as the spec assumes.
- For each new component the spec introduces, identify what existing infrastructure it depends on (config, secrets, observability, deployment).
- Identify dependencies the spec assumes but does not state (e.g. "this requires a Redis instance" never declared).

**Severity mapping.**

- **Critical** — spec depends on infrastructure or APIs that do not exist in the project, with no plan to introduce them.
- **Significant** — spec underestimates the work; a "simple addition" that actually requires refactoring multiple existing modules.
- **Observation** — spec could be more explicit about an assumed dependency.

## Dimension 3: Risks

**Focusing question.** What architectural risks does this spec introduce? Consider coupling, data consistency, failure modes, scalability, security boundaries, and operational impact.

**Evidence to gather.**

- For each new boundary the spec creates, identify what crosses it (data, control, trust). Each crossing is a potential risk.
- Identify failure modes the spec does not address: what happens on partial failure, network partition, retry storm, schema migration?
- Identify security-boundary changes: new ingress points, new trust assumptions, new data flows.

**Severity mapping.**

- **Critical** — risk would cause data loss, security breach, or service-wide outage if the spec is implemented as-is.
- **Significant** — risk would degrade quality (latency, reliability, maintainability) but not break the system.
- **Observation** — risk is small or already mitigated by existing project mechanisms (logging, alerting, retry middleware).

## Dimension 4: Completeness

**Focusing question.** What does the spec leave unspecified that an implementer would need to decide? Are there ambiguities that could lead to divergent implementations?

**Evidence to gather.**

- For every behavior the spec mentions, identify whether it specifies inputs, outputs, error cases, and edge cases.
- Identify quantifiers the spec uses without defining: "usually", "typically", "should", "may". These almost always become defects.
- Identify cross-references to "other systems" or "existing infrastructure" without naming the specific component.

**Severity mapping.**

- **Critical** — a core behavior is left undefined; two implementers would build incompatible systems from the same spec.
- **Significant** — an edge case is left unspecified; the implementer would have to make an undocumented call that should have been the architect's.
- **Observation** — a trivial detail (logging format, a method name) is unspecified but inconsequential.

## Dimension 5: Tradeoffs

**Focusing question.** What quality attributes does this spec prioritize? What does it sacrifice? Are those tradeoffs appropriate for the project context?

**Evidence to gather.**

- Identify the implicit ordering of quality attributes: throughput vs latency, consistency vs availability, simplicity vs flexibility, security vs usability.
- Compare against project priorities (from Phase 2). A spec optimizing for latency in a project that prioritizes durability is a misalignment.
- Identify tradeoffs the spec does not acknowledge — every architectural choice involves a tradeoff, even when the spec presents it as obvious.

**Severity mapping.**

- **Critical** — spec optimizes for an attribute the project explicitly de-prioritizes (e.g. chasing performance in a project that demands operational simplicity).
- **Significant** — spec is silent on a tradeoff that affects multiple downstream decisions.
- **Observation** — tradeoff is acceptable given project context; flag for awareness only.

## Dimension 6: Recommendations

**Focusing question.** What concrete, actionable improvements should the spec author make before implementation begins?

**Evidence to gather.** Recommendations are derived from findings in Dimensions 1–5 above. For each `Critical` or `Significant` finding, formulate a recommendation that:

- **Names the change** — "Replace §3.2's caching strategy with X" not "consider caching".
- **References existing project patterns** — "Use the existing `ClientFactory` from `internal/client/`" not "use a factory pattern".
- **Avoids new abstractions** the project does not already use, unless solving a critical gap.
- **States the tradeoff** — every recommendation introduces its own cost; name it.

**Anti-patterns in recommendations.**

- "Consider improving X" — vague, ignorable.
- "Add tests" — every spec needs tests; not actionable as a recommendation.
- "Use a microservice" / "use Kafka" / "use Redis" — introducing new infrastructure without justification.
- "Add documentation" — specs always need this; not specific enough to act on.
