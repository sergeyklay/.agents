# Quality Checklist

Post-draft verification. Load and run this checklist during Phase 4 of `writing-specs`. Every failing item MUST be fixed before delivering the spec.

This checklist combines IEEE 830 / ISO 29148 requirement-quality attributes with a catalogue of the most frequent spec-quality defects. Both are stack-agnostic.

## Contents

- Requirement quality attributes (IEEE 830)
- Common defects to catch
- Structural completeness
- Citation discipline

## Requirement quality attributes (IEEE 830)

Each functional requirement in the spec MUST satisfy all eight attributes below. Apply the table to every numbered or bulleted requirement in the spec; do not apply it to narrative paragraphs that are not requirements.

| Attribute | Test question |
|-----------|---------------|
| **Correct** | Does this match the project's architecture document, accepted ADRs, and tracker reference (if any)? |
| **Unambiguous** | The "two engineers test": can two engineers read this and reach the same implementation? If not, rewrite with concrete values, explicit types, or a worked example. |
| **Complete** | Are all inputs, outputs, error conditions, and edge cases defined? Is the behavior on every relevant precondition specified? |
| **Consistent** | Does this contradict any other requirement in this spec, or any project document the spec cites? |
| **Ranked** | Is the priority clear (must-have vs. nice-to-have, MUST vs. SHOULD vs. MAY)? |
| **Verifiable** | Can a reviewer write a test or run a procedure that proves this requirement is met? |
| **Modifiable** | Can this requirement change without rewriting unrelated parts of the spec? |
| **Traceable** | Does this trace to a specific source: an architecture-document section, an ADR, a tracker reference, an agent-instruction rule, or an acceptance criterion? |

A requirement that fails any attribute is a defect. The "two engineers test" is the most reliable single check; apply it whenever a requirement reads as a natural-language statement rather than a contract.

## Common defects to catch

Scan the drafted spec for each of these patterns. Each one is a class of dispute that surfaces during implementation if left in the spec.

1. **Vague verbs.** "Handle errors appropriately", "manage resources gracefully", "process input correctly", "perform validation". A spec verb MUST name the concrete action, the input class it applies to, and the resulting state. Replace with: "On a 5xx response from service X, retry up to 3 times with exponential backoff starting at 100 ms; after the third failure, surface error of kind `TransportError` to the caller".
2. **Missing error paths.** Every operation that can fail MUST have an explicit error category, observability behavior (log, metric, alert), and recovery path (retry, abort, skip, dead-letter, log-and-continue). A spec that only describes the happy path is incomplete.
3. **Implicit ordering.** If steps MUST execute in a specific order, state it. If steps MAY execute concurrently, state that too. "First the system validates input, then it writes to the database" is order-dependent; "The system validates input and writes to the database" leaves ordering undefined.
4. **Unspecified defaults.** Configuration fields, optional parameters, and feature flags without stated defaults are ambiguous. Every optional input gets a default value AND the rationale for that default.
5. **Orphaned references.** If the spec cites an architecture section (e.g. `[Section X.Y](../docs/architecture.md#xy-...)`), an ADR (`ADR-0014`), or a tracker reference, the target MUST exist. Verify every citation before delivering. Broken citations indicate the spec drifted from its sources.
6. **Oversized steps.** If an implementation step requires more than approximately 300 lines of code (excluding tests and documentation) or touches more than 3 files, decompose it. Oversized steps hide complexity and prevent the implementer from reasoning about correctness.
7. **Quantifiers without thresholds.** "Usually", "typically", "should be fast", "high availability", "low latency". Replace with measured values (p50, p99, throughput, error budget) or remove.
8. **Cross-references to unnamed components.** "The other system", "the existing service", "the legacy module". Every cross-reference MUST name the specific component, repository path, or document.
9. **Banned vocabulary from project style rules.** Where the project's style rules ship a banned-words list (read in Phase 1), grep the spec for those words and replace them. A spec that violates project style rules signals lack of grounding in the project.

## Structural completeness

Run this list against the drafted spec.

- [ ] Every section from `assets/spec-template.md` is present, or has a note explaining why it cannot be filled and what information is needed.
- [ ] Risk-assessment table has at least one data row. Severity is one of the values the project documents (typically: Critical, High, Medium, Low; or Critical, Major, Minor). Every Critical and High row has a concrete mitigation, not "TBD".
- [ ] File-structure summary lists every new file and every modified file. Each entry is annotated with its role (using the project's own taxonomy).
- [ ] Open-questions section is present. If the spec genuinely has no open questions, state that explicitly; an empty section is suspicious.
- [ ] Acceptance-criteria section maps every criterion from the tracker reference (if any) to the section of the spec that addresses it.

## Citation discipline

A spec is only as trustworthy as its citations.

- [ ] Every architectural decision either cites a project source (architecture document, ADR, agent-instruction file rule) or is explicitly flagged in the spec as a deliberate extension requiring review.
- [ ] Every cited target exists. No broken anchor links, no ADR numbers that the project does not have, no architecture sections that have been renamed or removed.
- [ ] No bare URL citations to external content the implementer is not expected to read. Cite by section or filename, not URL, when the source is inside the project.
- [ ] No "as is well known", "per common knowledge", or unattributed factual claims. Cite or remove.

## Output style compliance

- [ ] No function bodies, no goroutine bodies, no full component implementations. The spec defines WHAT, not HOW.
- [ ] Public interface and data-shape blocks use the project's actual type language (TypeScript, Go, Python type hints, OpenAPI, Protobuf, Prisma, JSON Schema). Signatures only.
- [ ] Algorithms are pseudo-code or numbered steps in the project's documented style. No runnable code.
- [ ] No em-dashes anywhere in the spec. Use commas, parentheses, periods, semicolons, or colons.
- [ ] No banned vocabulary from the project's style rules (read in Phase 1).
- [ ] RFC 2119 keywords (MUST, MUST NOT, SHOULD, SHOULD NOT, MAY) are capitalized when used to express binding requirements; they do not appear in narrative prose.
- [ ] Forward-slash paths only. No backslashes.

If any item fails, fix the spec and re-run the checklist. Do not report the spec complete until every item passes.
