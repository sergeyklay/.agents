# Plan: {Short title under approximately 60 characters}

Created at: {ISO timestamp}
Tracker ref: {ID or URL, or `N/A`}
Source spec: `.specs/Spec-{slug}.md` (or `N/A` when no spec exists)
Feature: {One-sentence summary of the feature or change.}

## Summary

{One sentence stating what is being built, why, and the high-level approach. Format: "Builds X by Y; touches Z layer(s)." Primes the downstream coder agent before it reads the steps. Omit elaboration; this is an index entry, not a preamble.}

## Phase coverage

Includes: {comma-separated phase names that apply, in execution order}. Omits: {comma-separated names of canonical phases NOT included, each with a one-clause reason in parentheses, e.g. "Persistence (no schema changes), Request handlers (no new endpoints), Interactive UI (no client-side changes)"}.

## Phase 1: {Phase Name}

Contract: {one sentence stating what this phase produces.}

- [ ] 1.1 {Step title, imperative verb + object}
  - File: `{path/to/file.{ext}}`
  - Change: NEW | MOD | DEL
  - Symbols: {function, type, method, constant names this step creates or touches, or any atom names this step's logic depends on. For trivial steps, omit.}
  - Signature/Shape: {inline in prose, e.g. `add Operation(ctx, id) -> Result to ContactService`. For non-trivial shapes, use an untagged block. Never a language-tagged code fence.}
  - Logic: {numbered prose list when branching matters; omit otherwise}
    1. {First validation or transition.}
    2. {Second validation or transition.}
    3. If {condition}, return `{error_category}` without attempting {side effect}.
  - Verify: {specific runnable command with named target, e.g. "run the project's typecheck command targeting `src/services/`; confirm zero new errors"}

- [ ] 1.2 {Step title}
  - File: `{path}`
  - Change: NEW | MOD | DEL
  - Symbols: {symbol names}
  - Logic: {numbered prose list, or "trivial" with one-line justification}
  - Verify: {specific runnable command with named target}

- [ ] Constraint check: {layer-boundary assertion specific to this phase: what must not be imported, what state must not be mutated, what invariant must hold by phase end}

## Phase 2: {Phase Name}

Contract: {one sentence stating what this phase produces.}

- [ ] 2.1 {Step title}
  - File: `{path}`
  - Change: NEW | MOD | DEL
  - Symbols: {symbols}
  - Logic: {...}
  - Verify: {...}

- [ ] 2.2 {Step title} (parallel with step 2.1)
  - File: `{path}`
  - Change: NEW | MOD | DEL
  - Symbols: {symbols}
  - Logic: {...}
  - Verify: {...}

- [ ] Constraint check: {layer-boundary assertion specific to this phase}

## Phase N: Verification and Cleanup

Contract: confirm end-to-end behavior and environment hygiene. Per-phase Verify gates already prove the code compiles, lints, and tests; this phase covers only what earlier phases cannot.

- [ ] N.1 End-to-end manual or scripted check: {describe the minimal invocation that exercises the new behavior end-to-end. Name the user flow, the specific page or command, the expected observable outcome.}
- [ ] N.2 Confirm env-gated integration tests (if the project uses them) skip cleanly without their guard variables.
- [ ] N.3 Confirm the diff contains no banned patterns from the project's documented constraints (read in Phase 1 of the workflow).

## Files Affected

{One table row per file the plan creates, modifies, or deletes. Group by phase or layer when the plan spans multiple. List only files the plan directly changes; do not list files the implementer might touch incidentally.}

| File | Change | Purpose |
|------|--------|---------|
| `path/to/file.{ext}` | NEW/MOD/DEL | {one-line purpose} |

## Decisions

{Design choices the planner committed to on its own authority. For each item: (a) the decision; (b) the assumption it rests on; (c) what is in-scope and what is out-of-scope under it. These are not open questions; they are the planner's commitments, recorded so the implementer and reviewer can audit them. Use "none" only when the spec or project documents dictated every choice.}

- Decision: {assumption + in-scope / out-of-scope boundary}

## Plan extensions

{Design decisions that do not trace to the spec, an ADR, an architecture section, or an agent-instruction rule. For each item: (a) the decision; (b) why it is required despite the absence of a source; (c) what review is needed to ratify it. Use "none" when every decision in the plan traces to a project source.}

- Decision: {reasoning + review needed}

## Further considerations

{Open questions the planner could not resolve from the inputs. For each item: (a) the question; (b) why it blocks or shapes the plan; (c) at least two named alternatives in `Option A: ... / Option B: ...` form; (d) the planner's recommendation and reasoning. A question without alternatives is not acceptable; a list of alternatives without a recommendation is not acceptable. Use "none" only when the inputs resolved every question.}

1. Question: {question text}
   - Why it blocks: {reasoning}
   - Option A: {alternative} {trade-off}
   - Option B: {alternative} {trade-off}
   - Recommendation: {planner's pick and reasoning}
