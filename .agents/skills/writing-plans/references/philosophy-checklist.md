# Philosophy Checklist

Planner-internal pre-delivery self-check organized by concern. Run during Phase 5 of the workflow, in the planner's reasoning trace, before writing the plan file to disk. A failing item is a rewrite, not a note-to-self.

This checklist is NOT written into the plan artifact. The artifact is read by the coder and tester agents, which do not extract value from the checklist content; the structural conditions it verifies are independently enforced by `scripts/validate_plan.py`. Keeping the checklist in the artifact wastes tokens for the downstream agent reader.

Items are grouped by concern. If a group has no failures, move on. If any item fails, fix the plan and re-run the full checklist; a fix in one place often surfaces a defect elsewhere.

## Contents

- Traceability
- Layering and boundaries
- Atomicity and verification
- Sequencing and dependencies
- Security and trust boundaries
- Style compliance
- Simplicity
- Final delivery check

## Traceability

- [ ] Every non-trivial step cites a source: an architecture section by anchor link, an ADR by number, a spec section by anchor, an agent-instruction rule by name, or a tracker issue.
- [ ] Every cited target exists in the project. Verify by file existence and section-heading presence; broken citations actively misinform the implementer.
- [ ] Citations live in the plan, not in instructions to write source-code comments. The plan tells the implementer to write source comments that explain the code, not source comments that reference plan sections or ADR numbers.
- [ ] Decisions that do not trace are explicitly flagged in the plan's "Plan extensions" section with reasoning and review needed.

## Layering and boundaries

- [ ] Phase ordering matches the dependency direction documented for the project (or the universal downward default when the project documents no catalog).
- [ ] No step in phase N imports, extends, or otherwise depends on artifacts produced in phase N+M (M > 0). Reverse references are planning bugs, not annotation opportunities.
- [ ] Every productive phase ends with a Constraint Check bullet that names the specific boundary the phase honors. No `TBD` or single-word constraint checks.
- [ ] Integration-specific identifiers (vendor names, third-party identifiers, adapter-specific tokens) appear only inside their adapter-package steps. Core-layer steps use the project's documented generic vocabulary.
- [ ] When the project documents a layer that owns a particular responsibility (state mutation, transport, validation, persistence), no step in another layer claims that responsibility.

## Atomicity and verification

- [ ] Every step is atomic: sized for a single coder-agent session, roughly one file (or one tightly-coupled set) and one outcome.
- [ ] No step exceeds approximately 3 files or ~300 lines of implementation code; oversized steps are decomposed.
- [ ] Every productive step has a `Verify:` line carrying a specific runnable command with a named target. Generic verbs ("tests pass", "works correctly") are not verify gates.
- [ ] Compound steps (three independent actions under one checkbox) are split.
- [ ] Test additions are named with intent and coverage area; their bodies are left to the tester agent.

## Sequencing and dependencies

- [ ] The plan respects the project's documented build order (milestones, phases, releases, epics) where one is documented. Steps that depend on unbuilt foundations are flagged or removed.
- [ ] Every file path referenced in a step either exists in the current tree or is created by an earlier step in the same plan. No phantom files.
- [ ] Steps within a phase appear in execution order; the implementer works top-to-bottom.
- [ ] If phase N+1 depends on a specific artifact from phase N (interface, struct, migration file, type alias), the phase N step produces exactly that artifact and names it.
- [ ] Inline dependency annotations (`*depends on step N*`, `*parallel with step N*`) are present where the dependency is not the trivial previous-step one.

## Security and trust boundaries

If the feature touches secrets, authentication, input validation, filesystem operations, subprocess launch, network boundary, or any data that crosses a trust boundary, verify these invariants. They are security boundaries, not best-effort suggestions.

- [ ] Secrets (API keys, OAuth tokens, passwords, signing keys) follow the project's documented secret-handling pattern. Plaintext secrets MUST NOT appear in logs, source comments, response bodies, or application memory beyond the immediate decryption-and-use window.
- [ ] Every input that crosses a trust boundary (HTTP request, message queue payload, file upload, environment variable under user control) has an explicit validation step naming the validator (schema, regex, range check).
- [ ] SQL or query strings constructed dynamically use parameterized placeholders. No string concatenation of user input into query text.
- [ ] Filesystem operations name the containment check (workspace root prefix, sandbox root, configured base path) that prevents escape. Symlink-based escapes are explicitly rejected where the project documents this constraint.
- [ ] Subprocess launch plans confirm the launch context (working directory, environment subset, argument escaping) BEFORE the `exec`, not after.
- [ ] Authorization is checked at the documented authorization boundary; new code paths inherit the project's documented authorization pattern.

If any of these invariants are weakened by the plan, the plan is rejected. Restate the constraint, redesign the relevant phase, and re-run this checklist.

## Style compliance

- [ ] No function bodies, no full component implementations, no exact SQL strings, no test bodies.
- [ ] No fenced code blocks tagged with a language identifier. Inline signatures in prose; untagged pseudo-code for non-trivial logic.
- [ ] Every implementable step uses the `- [ ] **N.M**` checkbox format. Phase headers, tables, and rationale blocks use regular Markdown.
- [ ] No em-dashes anywhere in the plan. Use commas, parentheses, periods, semicolons, or colons.
- [ ] No banned vocabulary from the project's style rules (read in Phase 1).
- [ ] One name per concept; no alternating between synonyms.
- [ ] Forward-slash paths only; no backslashes.

## Simplicity

- [ ] The plan contains the minimum phases, steps, and artifacts needed to meet the spec. No speculative flexibility, no forward-looking abstractions, no "while we're at it" refactors.
- [ ] No step adds configuration knobs, feature flags, or compatibility shims the spec did not request.
- [ ] No step adds error handling for scenarios that cannot occur (framework-guaranteed invariants, internal-only call sites with documented preconditions).
- [ ] If the plan has 20+ steps or 6+ phases, reconsider whether it is one plan or several. Large plans become implementation-time guesswork as phases get skipped or reordered in practice.

The senior-engineer test: a senior engineer reading the plan says "this is the minimum to meet the spec." Not "this is clever," not "this is comprehensive." The minimum.

## Final delivery check

- [ ] Filename follows the convention: `.plans/Plan-{slug}.md` with `{slug}` matching the spec or tracker reference.
- [ ] Header lists `Created at`, tracker reference (or N/A), source spec path (or N/A), one-sentence feature summary.
- [ ] Summary section is present with a single sentence after the title and before the Phase coverage section.
- [ ] Phase coverage section is present, listing phases in execution order and naming omitted canonical phases with reasons.
- [ ] At least one productive phase plus a terminal verification phase exists.
- [ ] Files Affected table lists every new or modified file with change type (NEW/MOD/DEL) and one-line purpose.
- [ ] Decisions / Plan extensions / Further considerations sections are present (each may be "none" if there genuinely are none; a non-trivial plan with all three "none" is suspicious).
- [ ] The terminal verification phase covers end-to-end behavior, not just a recap of per-phase verify gates.
- [ ] The plan, in isolation, tells the coder agent everything needed to implement the feature without re-reading the spec. The coder may still consult the spec for context, but no single step requires reading it for execution.
- [ ] Re-read the first phase and the last phase. If either is under-specified or repetitive, fix it. The first and last phases are where drift starts.

When every item in every group passes, run [scripts/validate_plan.py](../scripts/validate_plan.py) for the mechanical checks (filename, section presence, code-fence rule, em-dashes, oversized blocks), fix any failures it reports, and write the plan to disk. Report the absolute file path to the caller.
