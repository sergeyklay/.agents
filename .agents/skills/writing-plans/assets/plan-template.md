# Plan: {Short title under approximately 60 characters}

**Created at:** {ISO timestamp} \
**Tracker ref:** {ID or URL, or `N/A`} \
**Source spec:** `.specs/Spec-{slug}.md` (or `N/A` when no spec exists) \
**Feature:** {One-sentence summary of the feature or change.}

## TL;DR

{2 to 3 sentences. State what is being built, why, and the high-level approach (single layer, multi-layer end-to-end, refactor only, evaluation only). A reader decides in fifteen seconds whether this is the right plan to open. Omit flavor; this is an index entry, not a preamble.}

## Dependency graph

{ASCII or arrow-list diagram of the phases that apply. The graph MUST flow downward only: a later phase may depend on an earlier one, never the reverse. State explicitly which canonical phases are omitted and why.}

```
Phase 1: {Name}
    -> Phase 2: {Name}
        -> Phase 3: {Name}
            -> Phase N: Verification and Cleanup
```

{Explicit omissions, e.g. "No persistence changes. No request-handler changes. No interactive UI changes."}

## Phase 1: {Phase Name}

*{One-sentence contract: what this phase produces.}*

- [ ] **1.1** {Step title, imperative verb + object}
  - **File:** `{path/to/file.{ext}}`
  - **Change:** NEW | MOD | DEL
  - **Symbols:** {function, type, method, constant names this step creates or touches}
  - **Signature/Shape:** {inline in prose, e.g. `add Operation(ctx, id) -> Result to ContactService`. For non-trivial shapes, use an untagged block. Never a language-tagged code fence.}
  - **Logic:** {numbered prose list when branching matters; omit otherwise}
    1. {First validation or transition.}
    2. {Second validation or transition.}
    3. If {condition}, return `{error_category}` without attempting {side effect}.
  - **Verify:** {specific runnable command with named target, e.g. "run the project's typecheck command targeting `src/services/`; confirm zero new errors"}

- [ ] **1.2** {Step title}
  - **File:** `{path}`
  - **Change:** NEW | MOD | DEL
  - **Symbols:** {symbol names}
  - **Logic:** {numbered prose list, or "trivial" with one-line justification}
  - **Verify:** {specific runnable command with named target}

- [ ] **Constraint Check (Phase 1):** {layer-boundary assertion specific to this phase: what must not be imported, what state must not be mutated, what invariant must hold by phase end}

## Phase 2: {Phase Name}

*{One-sentence contract.}*

- [ ] **2.1** {Step title}
  - **File:** `{path}`
  - **Change:** NEW | MOD | DEL
  - **Symbols:** {symbols}
  - **Logic:** {...}
  - **Verify:** {...}

- [ ] **2.2** {Step title} *parallel with step 2.1*
  - **File:** `{path}`
  - **Change:** NEW | MOD | DEL
  - **Symbols:** {symbols}
  - **Logic:** {...}
  - **Verify:** {...}

- [ ] **Constraint Check (Phase 2):** {layer-boundary assertion specific to this phase}

## Phase N: Verification and Cleanup

*Per-phase Verify gates already prove the code compiles, lints, and tests. This phase covers only what earlier phases cannot: end-to-end behavior, environment hygiene, and the final cumulative checks.*

- [ ] **N.1** End-to-end manual or scripted check: {describe the minimal invocation that exercises the new behavior end-to-end. Name the user flow, the specific page or command, the expected observable outcome.}
- [ ] **N.2** Confirm env-gated integration tests (if the project uses them) skip cleanly without their guard variables.
- [ ] **N.3** Confirm the diff contains no banned patterns from the project's documented constraints (read in Phase 1 of the workflow).

## Files Affected

{One table row per file the plan creates, modifies, or deletes. Group by phase or layer when the plan spans multiple. List only files the plan directly changes; do not list files the implementer might touch incidentally.}

| File | Change | Purpose |
|------|--------|---------|
| `path/to/file.{ext}` | NEW/MOD/DEL | {one-line purpose} |

## Decisions

{Design choices the planner committed to on its own authority. For each item: (a) the decision; (b) the assumption it rests on; (c) what is in-scope and what is out-of-scope under it. These are not open questions; they are the planner's commitments, recorded so the implementer and reviewer can audit them. Use "none" only when the spec or project documents dictated every choice.}

- **{Decision}:** {assumption + in-scope / out-of-scope boundary}

## Plan extensions

{Design decisions that do not trace to the spec, an ADR, an architecture section, or an agent-instruction rule. For each item: (a) the decision; (b) why it is required despite the absence of a source; (c) what review is needed to ratify it. Use "none" when every decision in the plan traces to a project source.}

- **{Decision}:** {reasoning + review needed}

## Further considerations

{Open questions the planner could not resolve from the inputs. For each item: (a) the question; (b) why it blocks or shapes the plan; (c) at least two named alternatives in `Option A: ... / Option B: ...` form; (d) the planner's recommendation and reasoning. A question without alternatives is not acceptable; a list of alternatives without a recommendation is not acceptable. Use "none" only when the inputs resolved every question.}

1. **{Question}**
   - **Why it blocks:** {reasoning}
   - **Option A:** {alternative} {trade-off}
   - **Option B:** {alternative} {trade-off}
   - **Recommendation:** {planner's pick and reasoning}

## Philosophy checklist

{Retained as evidence of pre-delivery verification. Convert `- [ ]` to `- [x]` as each item passes during Phase 5 of the workflow. If an item cannot be checked, either the plan is incomplete or the item does not apply. If it does not apply, strike it out (`~~item~~`) and briefly say why. Do not delete items.}

- [ ] Every step traces to an architecture section, ADR, spec section, agent-instruction rule, or tracker issue.
- [ ] The plan respects the project's documented build order; no step depends on unbuilt foundations.
- [ ] Security and trust-boundary invariants (input validation, secret handling, filesystem containment, subprocess launch context) are explicit where applicable.
- [ ] No fenced code blocks tagged with a language identifier; no function bodies; no exact SQL strings; no test bodies.
- [ ] Every productive step has a specific `Verify:` gate with a named target.
- [ ] Tests are listed by name and intent; the tester agent writes their bodies.
- [ ] The plan is the minimum viable work that meets the spec.
- [ ] No em-dashes appear in the plan.
