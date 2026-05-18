# Phase Structure

Universal dependency-graph principle, the phase template, common partial-scope shapes, and the per-phase constraint-check pattern. The actual phase catalog comes from the project's architecture document; this file gives the universal shape that every project's catalog satisfies.

## Contents

- The downward-flow principle
- Phase template
- Common partial-scope shapes
- Constraint-check pattern
- When the project documents its own phase catalog

## The downward-flow principle

Phases form a topological dependency graph. A step in phase N may reference artifacts produced in phases 1..N-1; it MUST NOT reference artifacts produced in N+1 or later. This is the non-negotiable invariant that lets the coder agent implement phases atomically and in order.

The universal downward direction, in execution order: data shapes / domain types, then services / business logic, then composition / orchestration / workflows, then request handling / actions / endpoints, then boundary / UI / interactive surface, then verification and cleanup. Each tier depends only on tiers earlier in the list. This is the default when the project's architecture document does not document a different layering; when it does, the project's catalog wins.

Phase N (the final phase) is always a verification phase. It does not introduce new code; it proves the cumulative output of the prior phases compiles, lints, tests, and meets the spec end-to-end.

## Phase template

Every phase header follows this shape:

```
## Phase N: <Name>

Contract: <one sentence stating what this phase produces.>

- [ ] N.1 <step title>
  - File: <path>
  - Change: NEW | MOD | DEL
  - Symbols: <function, type, method names>
  - Signature/Shape: <inline in prose or untagged block>
  - Logic: <numbered prose list when branching matters; omit otherwise>
  - Verify: <specific runnable command with named target>

- [ ] N.2 <step title>
  ...

- [ ] Constraint check: <layer-boundary assertion specific to this phase>
```

The `Contract:` line under the phase heading is not decoration; it is the phase's promise. If a step inside the phase does not contribute to producing what the contract promises, the step belongs in a different phase.

The closing `Constraint Check` is the layer-boundary assertion: which imports are forbidden, which state must not be mutated, which invariant must hold by the end of the phase. Constraint checks are not optional padding; they are the seam that keeps the architecture from drifting plan-by-plan.

## Common partial-scope shapes

Not every plan touches every phase. Below are the common shapes by intent; map your feature to the closest shape and add or remove phases as the work requires.

| Plan intent | Phases used (typical) |
|-------------|-----------------------|
| Single domain-type addition | Data shape, Verification |
| New persistence table + CRUD | Data shape, Services, Verification |
| Adding a service method | Services, Verification |
| New adapter implementing an existing interface | Adapter package, Verification |
| Request-handler change (no schema, no UI) | Services, Request handling, Verification |
| UI-only change (no server work) | Boundary/UI, Verification |
| Configuration field addition | Configuration, CLI/wiring (if exposed), Verification |
| End-to-end feature | All applicable phases in order |
| Pure refactor at one layer | The one layer, Verification |

Name phases by their **purpose**, not by their position in some canonical numbering. A small plan with two phases writes "Phase 1: Domain Types" and "Phase 2: Verification and Cleanup", regardless of where those would sit in the project's full catalog.

## Constraint-check pattern

Every productive phase ends with a Constraint Check bullet that names the boundary the phase honors. Examples (universal, adapt to the project's actual layer names):

- Domain or type-only phase: "No import of any package outside the domain package. No methods with side effects, no I/O handles, no transport types."
- Service phase: "No import from boundary, UI, or transport layers. No transport-specific types reach service signatures. Logger from the project's documented logger, never `print`/`console.*`/`fmt.Println`."
- Adapter phase: "No import of core orchestration packages. Adapter-specific identifiers stay inside the adapter package; do not leak into core."
- Composition or workflow phase: "Side effects flow through documented effect channels (event emitter, command bus, dispatcher); no direct service-to-service calls that bypass the documented coordination point."
- Boundary or UI phase: "No direct import of data-access or services from the interactive leaf. Mutations flow through the documented request-handling layer."

A constraint check named "TBD" or a single word is not a constraint check; it is a missing one. Every constraint check states the specific invariant the phase protects.

## When the project documents its own phase catalog

If the project's agent-instruction files or architecture document lists a canonical phase catalog (e.g. five named phases, eight named layers, three concentric rings), use that catalog verbatim:

- Phase names come from the project's documents.
- Phase ordering comes from the project's documented layering.
- Constraint checks per phase come from the project's documented boundary rules.
- The universal downward-flow principle still applies as the meta-rule that the project's catalog must obey.

If the project documents a catalog and this skill's defaults disagree with it, the project wins. Cite the project document in the plan opening so the reviewer can audit the choice.

If the project documents no catalog, this skill's universal shape is the default. State that in the plan's Summary section so the next agent knows which catalog the plan is using.

## Anti-patterns specific to phase ordering

- **Reverse dependency.** Phase 2 references a file Phase 5 creates. Fix: restructure so the dependency flows downward, or split the Phase 2 step into a contract-only step (now) and a use-the-concrete-file step (Phase 5+).
- **Phase numbering with gaps for missing layers.** Confusing for the reader. Renumber phases sequentially 1..N based on what actually appears in the plan.
- **Phase ordering by author preference.** "I will write the UI first because I have context." The dependency graph dictates order; author preference does not.
- **Compound phases.** "Phase 3: Services and Workflows." Two concerns, two phases. Split.
- **Verification phase with no end-to-end check.** Phase N is the only place where the cumulative behavior is observed. Without an end-to-end check, Phase N is just a recap of per-phase verify gates; that is not its job.
