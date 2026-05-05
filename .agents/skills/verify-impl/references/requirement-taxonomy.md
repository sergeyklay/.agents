# Requirement Taxonomy

Use this reference at Phase 2 of `verify-impl` for two purposes: (1) categorizing each extracted requirement, and (2) ensuring no class of requirement is overlooked. The categories are not interchangeable - a `state-transition` requirement has different verification semantics than a `naming` requirement.

## Contents

- The eleven categories
- What counts as a requirement (extraction heuristics)
- Edge cases - what looks like filler but is load-bearing

## The eleven categories

| Category | Definition | Typical phrasing in specs |
|---|---|---|
| `interface-contract` | Function/method signatures, parameter types, return types, public API surface | "must accept", "returns", "exposes" |
| `struct-layout` | Data structure fields, types, annotations, zero-value semantics, optionality | "field X must be of type Y", "MUST contain" |
| `algorithm` | Specific procedural steps, ordering, decision logic | "compute", "iterate", "first ... then" |
| `state-transition` | State-machine transitions, guard conditions, terminal states | "transitions from X to Y when", "may not enter Z if" |
| `error-handling` | Error categories, retry semantics, propagation policy | "must retry", "must terminate", "propagate as" |
| `safety-invariant` | Validation, sanitization, containment, bounds | "must validate", "must reject", "may not exceed" |
| `concurrency` | Thread safety, context propagation, lifecycle, ordering guarantees | "thread-safe", "must propagate context", "happens-before" |
| `persistence` | Schema definitions, query patterns, transaction boundaries, durability | "stored as", "atomically", "indexed by" |
| `configuration` | Settings, defaults, environment variables, feature flags | "default to", "configurable via", "off by default" |
| `naming` | Identifier conventions, public-vs-private rules, visibility | "must be named", "exported as" |
| `boundary` | Module boundaries, layer rules, dependency direction | "must not depend on", "owns", "internal to" |

If a requirement plausibly fits two categories, pick the one that drives the strongest verification gate. Example: a "must validate input X" requirement is `safety-invariant`, not `interface-contract`, because the verification check is "is the validation present" rather than "does the signature accept X."

## What counts as a requirement

Treat each of the following as one or more requirements during extraction:

- Interface/function signatures, parameter types, return types
- Data structure fields, types, annotations, zero-value semantics
- Algorithm steps - especially numbered/ordered steps; **each step is a separate requirement**
- State machine transitions and their guard conditions
- Error categories and how they must be handled (retry vs terminal vs propagate)
- Concurrency contracts (thread safety, context propagation, lifecycle management)
- Safety invariants (validation, sanitization, containment rules)
- Schema definitions, query patterns, transaction boundaries
- Naming conventions and module boundary rules
- Diagrams encode behavioral flow - **each arrow and decision node is a requirement**
- Risk mitigations - each mitigation implies a requirement on the implementation
- "Verify" or "ensure" conditions - each is a testable obligation
- Comments, notes, and parenthetical remarks - these are often critical edge cases

## Edge cases - what looks like filler but is load-bearing

These commonly look like prose but encode requirements:

- **Examples.** A spec example showing input/output is a requirement: the implementation must reproduce the exact mapping shown.
- **Footnotes.** Footnotes typically capture corner cases the architect saw but didn't elevate to body text. Still requirements.
- **Risk-mitigation notes.** "To avoid X, the implementation must Y" - Y is a requirement.
- **Backward-compat notes.** "Older clients send X; the new code must Y" - Y is a requirement, often missed.
- **Default values in tables.** When a spec table has a "default" column, every default is an interface-contract requirement.
- **"For future use" / "reserved" markers.** A reserved field marked "for future use" is a struct-layout requirement: the field must exist, even if unused now.
- **Numbered diagrams.** Sequence diagrams and state diagrams encode ordering requirements that prose may not state explicitly.
- **Words like "should" or "may".** Still requirements - at the `should` or `note` criticality level. Extract them, don't drop them.
