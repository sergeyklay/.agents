# Output Style Rules

Detailed expansion of the 13 output rules from SKILL.md, with Good and Bad examples for each. Read during Phase 4 (Draft atomic steps).

## Contents

- The 13 rules at a glance
- Rule 1: Location and slug derivation
- Rule 2: TL;DR first
- Rule 3: WHAT, not HOW
- Rule 4: Reference symbols, not just files
- Rule 5: One step, one file, one outcome
- Rule 6: Verify gates are specific
- Rule 7: Dependencies flow downward; annotate non-trivial
- Rule 8: Atomicity
- Rule 9: Cite project sources
- Rule 10: Tests are separate steps
- Rule 11: No banned patterns
- Rule 12: No em-dashes
- Rule 13: One term per concept
- Anti-patterns to reject on self-review

## The 13 rules at a glance

| # | Rule | Why |
|---|------|-----|
| 1 | Location and slug derivation | Predictable file paths let other agents and reviewers find the plan |
| 2 | TL;DR first | Implementer confirms scope in 15 seconds before reading the step list |
| 3 | WHAT, not HOW | The plan is a contract; bodies belong to the implementer |
| 4 | Reference symbols, not just files | Implementer can grep; reduces variance across runs |
| 5 | One step, one file, one outcome | Atomic steps are independently verifiable |
| 6 | Verify gates are specific | "Tests pass" is unverifiable; "run X test in Y package" is |
| 7 | Dependencies flow downward; annotate non-trivial | Topological order is the planning invariant |
| 8 | Atomicity | Compound steps hide failure modes |
| 9 | Cite project sources | Untraced decisions are scope creep waiting to happen |
| 10 | Tests are separate steps for the tester agent | Implementer writes code; tester writes tests |
| 11 | No banned patterns | Project conventions are binding, not advisory |
| 12 | No em-dashes | LLM-generated-text signal; many projects ban outright |
| 13 | One term per concept | Synonyms create ambiguity for the reader |

## Rule 1: Location and slug derivation

Write to `.plans/Plan-{slug}.md`. Derive `{slug}` in this order:

- If the spec filename starts with `Spec-`, strip the prefix: `Spec-238-payments-webhook.md` -> `Plan-238-payments-webhook.md`.
- If a tracker ID is present, use it: `Plan-PROJ-42.md`, `Plan-TASK-138.md`, `Plan-238-payments-webhook.md` (for GitHub issue `#238`).
- Otherwise derive kebab-case from the feature title: `Plan-rate-limiter-token-bucket.md`.

Reuse the same slug across spec, plan, and review for traceability.

## Rule 2: TL;DR first

Open the plan with a 2 to 3 sentence TL;DR immediately after the title and before the dependency graph. State what is being built, why, and the high-level approach.

**Good:**

> ## TL;DR
> Add a contact-listing operation to the contact service so the directory page can paginate. The current page fetches the entire table; this introduces cursor-based pagination matching the architecture's pagination contract. Two phases: service method, then UI consumption.

**Bad (no TL;DR; reader has to read the step list to learn what's being built):**

> ## Phase 1: Service
> - [ ] 1.1 Add `listContacts` method ...

## Rule 3: WHAT, not HOW

Define file paths, function and method signatures, type or schema shapes, ordered steps, and verify gates. Do NOT write function bodies, full implementations, exact SQL, exact algorithms, test bodies, or full component code.

Do NOT use fenced code blocks tagged with a language identifier (`go`, `ts`, `tsx`, `python`, `sql`, `rust`, `java`, `kotlin`, `swift`, `php`, `ruby`, `csharp`, `cpp`, etc.). The tag signals runnable code and lets implementation creep into the plan.

Inline signatures in prose are correct. Untagged pseudo-code is acceptable for non-trivial logic when prose alone is unclear.

**Good (untagged signature block):**

> - Signature:
> ```
> listContacts(userId, cursor?, limit?) -> Promise<ContactPage>
> ```

**Good (inline in prose):**

> - Add `listContacts(userId, cursor?, limit?) -> Promise<ContactPage>` to `src/services/contact-service`.

**Bad (language-tagged code block with a body):**

> ```ts
> export async function listContacts(userId: string, cursor?: string, limit?: number): Promise<ContactPage> {
>   const rows = await db.contact.findMany({ where: { userId } });
>   return paginate(rows, cursor, limit);
> }
> ```

The first form survives any refactoring the implementer chooses; the second form ages the moment the implementer picks a different cursor strategy.

## Rule 4: Reference symbols, not just files

When a step reuses, extends, or interacts with existing code, name the concrete symbol (function, method, type, constant, package, module path) so the implementer can grep for it.

**Good:**

> - Extend `ContactService.list` to accept a `cursor` argument. Reuse the existing `paginateByCursor` helper from the `query-utils` module.

**Bad:**

> - Modify the contact service in `src/services/` to support pagination. Use existing helpers.

Plain file paths force the implementer to re-discover what to touch and may pick a different abstraction across runs.

## Rule 5: One step, one file, one outcome

Every step modifies or creates one file (or one tightly-coupled set), describes the intended change, and ends with a verify gate. A step that touches more than approximately 3 files or ~300 lines of code MUST be decomposed.

**Good:**

> - [ ] **2.1** Add `listContacts` to the contact service. File: `src/services/contact-service.{ext}`. Verify: typecheck passes targeting `src/services/`.
> - [ ] **2.2** Add cursor-pagination helper used by `listContacts`. File: `src/services/query-utils/cursor.{ext}`. Verify: unit test for the helper named `paginateByCursor` is listed in the test plan.

**Bad (compound, multi-file, no verify):**

> - [ ] Add the listing endpoint, the cursor helper, the unit tests, and update the documentation.

## Rule 6: Verify gates are specific

Every productive step terminates with a `Verify:` line carrying a specific, runnable command with the actual target (package path, test name, file path, named check).

**Good:**

> - Verify: run the project's typecheck command targeting `src/services/`; confirm zero new errors.
> - Verify: run the project's test command targeting `src/services/contact-service.test.{ext}`; confirm the new `lists contacts paginated` test passes.
> - Verify: open `src/services/contact-service.{ext}`; confirm the new export `listContacts` is named, exported, and matches the documented signature.

**Bad:**

> - Verify: tests pass.
> - Verify: works correctly.
> - Verify: it compiles.

Discover the actual commands from the project (Makefile, Taskfile.yml, package.json scripts, `scripts/`, CI configuration). Do not hardcode `make test` or `go test ./...` unless the project documents them as the canonical commands.

## Rule 7: Dependencies flow downward; annotate non-trivial

Phase ordering matches dependency direction. A step in phase N must not depend on artifacts produced in phase N+M (M > 0). Reverse references are planning bugs; restructure, do not annotate around them.

Within a phase, when a step depends on a specific earlier step beyond the previous one, annotate inline:

> - [ ] **2.4** Wire `listContacts` into the directory page composition. *depends on step 2.1*

When two steps in the same phase share no file and no data dependency, annotate both:

> - [ ] **2.2** Add cursor helper. *parallel with step 2.3*
> - [ ] **2.3** Add the response normalizer. *parallel with step 2.2*

Steps without annotations execute in plan order with sequential dependency.

## Rule 8: Atomicity

Each step has a single outcome the reviewer can confirm. "Implement and test the feature" is two steps (one for the coder, one for the tester). "Add validation and refactor the parser" is two steps. "Update the service and its consumers" is one step only when the consumer change is a single-file mechanical follow-on; otherwise it is two or more steps.

## Rule 9: Cite project sources

Every design decision in the plan that traces to the spec, an ADR, an architecture-document section, or an agent-instruction rule MUST cite the source. Use the form the project's documents use:

- Anchor link: `[Section 5.3](../docs/architecture.md#53-pagination)`
- ADR reference: `per ADR-0014`
- Spec section: `[Section 3.2 of the source spec](../.specs/Spec-PROJ-42.md#32-...)`
- Rule name: `per CLAUDE.md "Never" rule on raw SQL`

Decisions that do not trace MUST be flagged in the plan's "Plan extensions" section with the reasoning and the review needed to ratify them. Untraced decisions are scope creep waiting to happen.

## Rule 10: Tests are separate steps for the tester agent

The plan mentions tests in two ways:

1. **Verify gates** name test commands or test names that must pass; they do not contain the test body.
2. **Test plan listings** name new tests to add (test name, intent, coverage area, expected behavior) without writing the test bodies.

Do not write assertion code, table-driven test skeletons, or fixture construction in the plan. The test body is the tester agent's output.

## Rule 11: No banned patterns

Where the project's agent-instruction files or ADRs list banned libraries, banned patterns, or deprecated APIs, do not propose them. If a banned pattern appears to be the only feasible solution, halt and ask for clarification before drafting.

The banned-pattern list comes from the project (read in Phase 1), not from this skill.

## Rule 12: No em-dashes

Use commas, parentheses, periods, semicolons, or colons. Em-dashes are a strong LLM-generated-text signal and many projects ban them outright; assume they are banned unless the project explicitly permits them.

## Rule 13: One term per concept

Pick one name; use it everywhere; do not alternate synonyms for variety. If the spec calls something a "workspace key", never call it a "directory name" or "folder identifier" in the same plan.

## Anti-patterns to reject on self-review

Scan the drafted plan for each of these before delivering. A plan exhibiting any of them is not ready.

1. **Phantom files.** A step modifies a file that does not exist and is not created in an earlier step. Fix: either confirm the file exists by grepping the codebase, or add an earlier step that creates it.
2. **Implementation leak.** A step contains a function body, exact SQL, or runnable code in a language-tagged fence. Fix: replace with signature inline in prose, untagged pseudo-code, or a logic-description list.
3. **Missing verify.** A step has no `Verify:` line, or its verify line is a generic verb. Fix: name a specific runnable command with a target.
4. **Compound steps.** A single checkbox contains three independent actions. Fix: split into one checkbox per outcome.
5. **Unscoped steps.** "Add error handling." Fix: name which function, which error categories, which recovery behavior.
6. **Reverse dependency.** A Phase 2 step references a file Phase 5 creates. Fix: restructure phase ordering, or split the Phase 2 step into a contract-now / use-later pair.
7. **Hallucinated dependencies.** A step references a symbol the spec did not establish and no earlier step creates. Fix: confirm the symbol exists by grepping the spec or the codebase, or add an earlier step that creates it.
8. **Test body smuggling.** A step lists assertions or table-driven test skeletons. Fix: name the test and its intent; leave the body to the tester agent.
9. **Empty Constraint Check.** A phase ends in `Constraint Check: TBD` or a one-word assertion. Fix: name the specific boundary the phase honors.
10. **Plan-as-spec.** The plan restates the architecture section verbatim instead of citing and pointing to concrete work. Fix: cite the section, summarize the binding part in one sentence, and write the step that implements it.
