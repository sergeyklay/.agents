# Classification Categories — Full Rubric

This reference expands the seven-category classification table in SKILL.md with detailed criteria, decision rubrics, worked examples, and boundary rules. Read this file at Step 3 whenever the one-line description in SKILL.md is insufficient — typically when two categories both seem to apply, when a comment straddles a boundary, or when the Context7 verdict is not one of the clean cases.

## Contents

- Category 1 — Valid & Actionable
- Category 2 — Valid — Deferred to Backlog
- Category 3 — Valid but Already Addressed
- Category 4 — Subjective / Stylistic
- Category 5 — Incorrect or Counterproductive
- Category 6 — Outdated / Stale
- Category 7 — Needs Discussion
- Decision rubric for borderline cases
- Context7 verdict → allowed category mapping

## Category 1 — Valid & Actionable

**Definition.** A real bug, security flaw, performance issue, design gap, or idiomatic improvement — confirmed by Context7 evidence, the project's architecture documentation, or a logical analysis of the code itself.

**Preconditions.**

- If the comment makes a library claim, Context7 or the architecture documentation confirms it.
- The fix is in scope for the current change.
- The fix can be implemented without violating any constraint declared in the project's context files (AGENTS.md / CLAUDE.md "Always" / "Ask first" / "Never" sections, layer or module hierarchies, forbidden patterns).

**Action.** Apply the fix per SKILL.md Step 4a (code) or Step 4c (architecture). Verify by running the relevant subset of the project's documented verification commands.

**Worked example.** Reviewer writes: "This database call discards the caller's cancellation context — pass it through so the query is cancelled when the request is cancelled." You inspect the call site and confirm the context is available locally but not forwarded into the persistence layer. The project's architecture documentation mandates context propagation to every persistence operation. Apply the fix. → Valid & Actionable.

## Category 2 — Valid — Deferred to Backlog

**Definition.** A genuine improvement that is out of scope for this change: an acceptable trade-off at the current scale, a dependency on unfinished work, or work that is better tracked as a dedicated task.

**Hard rule. Deferred ↔ ticket.** A comment is only Category 2 if Step 4b can produce a ticket reference for it — newly created or already existing. A Deferred classification without a ticket reference is forbidden, regardless of which tracker the project uses. If Step 4b's gates prevent creation, the comment was misclassified and belongs in Category 5 (Incorrect, when the architecture conflicts) or Category 7 (Needs Discussion, when no appropriate roadmap lane exists or creation failed without recovery in this session).

**Preconditions.**

- The concern is real (Context7 or architecture confirms it, or logic supports it).
- Applying it now would materially expand the blast radius of the current change.
- A ticket can be created in the project's tracker, or a matching ticket already exists.

**Action.** Trigger tracker triage per SKILL.md Step 4b — discover the project's tracker and any sibling skill that manages it, then apply the three gates. The end state of Step 4b is a ticket reference (newly created or pre-existing) recorded in the Step 6 summary. If no ticket reference can be produced, the comment is not Deferred.

**Boundary versus Subjective.** A Deferred concern has an objective basis and will eventually be addressed. A Subjective concern has no objective basis and will never be addressed. Do not route real improvements through Subjective to avoid the triage work.

**Worked example.** Reviewer writes: "The retry loop should back off exponentially on repeated upstream failures, not retry at a fixed interval." The project's architecture agrees adaptive backoff is the long-term direction, but the current spec defines fixed-interval retry, and the change would ripple across multiple call sites. → Valid — Deferred. Open a refactor ticket under the closest-fitting milestone or epic, citing the architecture section that needs to evolve first.

## Category 3 — Valid but Already Addressed

**Definition.** The concern was correct when the review was written, but the issue has since been resolved — by a later commit on the same branch, by a separate PR that merged first, or by in-progress work in another branch that is about to land.

**Preconditions.**

- The current repository state no longer exhibits the issue.
- You verified this by reading the actual current file, not the diff that was reviewed.

**Action.** Skip. In the Step 6 summary, name the commit, PR, or branch that resolved the issue.

**Worked example.** Reviewer wrote three days ago: "The path construction does not enforce containment under the workspace root after normalization — possible path escape." The containment check was added in a later commit on the same branch; you read the current source and confirm the check is in place. → Valid but Already Addressed. Cite the commit SHA that added the check.

## Category 4 — Subjective / Stylistic

**Definition.** Neither better nor worse — merely different. No library backing. No architectural backing. No Context7 support. No project convention backing.

**Preconditions.**

- No library claim was made, or if one was made, Context7 did not confirm it.
- The existing code is idiomatic within the project's style.
- The proposed change is equally idiomatic but not superior.

**Action.** Skip with an explanation of the stylistic trade-off. Be specific: "equal readability, different word choice" beats "just style."

**Boundary.** Subjective is a narrow category. If the reviewer cites a pattern that improves readability, maintainability, concurrency safety, or performance — even mildly — the correct category is Valid & Actionable (if in scope) or Valid — Deferred (if out of scope). Do not hide real improvements behind Subjective to avoid doing the work. In particular, anything that touches established review dimensions in the project's review standards (concurrency, error handling, persistence, security, boundary integrity) is almost never Subjective.

**Worked example.** Reviewer writes: "Prefer destructuring over property access here." Both forms are idiomatic in the project; existing code uses both depending on local context. Either is fine here. → Subjective.

## Category 5 — Incorrect or Counterproductive

**Definition.** Would introduce a bug, degrade quality, violate architecture, reference a non-existent or deprecated API, or reduce clarity. Context7 refutation is sufficient and conclusive grounds. So is violation of a project invariant declared in context files or architecture documentation (forbidden libraries, banned patterns, prohibited APIs, layer-boundary breaches).

**Action.** Reject with a technical, specific rationale. Cite Context7 findings or the architectural section / context-file rule that the suggestion violates. Never dismissive, never personal.

**Worked example 1.** Reviewer writes: "Use the deprecated `legacyClient` API instead of the new `client` factory — it is better for batch operations." Context7 confirms `legacyClient` was removed in the major version pinned by this project, and `client` is the supported entry point with batch support. → Incorrect. Cite the Context7 finding refuting the claim.

**Worked example 2.** Reviewer writes: "Add a dependency on `<library>` for this — it ships a built-in helper." The project's context files declare a "Never" rule against adding `<library>` (e.g., wrong license, requires a toolchain the project intentionally avoids, breaks a deployment guarantee). → Incorrect. Cite the context-file rule in the Step 6 summary's Rejected section.

## Category 6 — Outdated / Stale

**Definition.** References code, behavior, or design that no longer exists in the current state of the repository.

**Preconditions.**

- The referenced file, function, or pattern was renamed, moved, or removed.
- The reviewer was reading an older snapshot of the PR or the base branch.

**Action.** Skip with an explanation of what changed and where the referenced entity went, if it still exists under a different name.

**Boundary versus Already Addressed.** Outdated applies to the *subject* of the comment (the code it refers to no longer exists). Already Addressed applies to the *opinion* (the code still exists, but the concern has been fixed). Use Outdated when the reviewer is pointing at a file or symbol that no longer has the shape they remember.

**Worked example.** Reviewer writes: "The `fetchIssues` helper in `internal/orchestrator/fetch.<ext>` should paginate." That helper was renamed and moved during a refactor; the equivalent is now `Adapter.list` in `internal/tracker/list.<ext>`, and it already paginates. → Outdated. Point the summary at the new location.

## Category 7 — Needs Discussion

**Definition.** You disagree with the comment but cannot definitively disprove it, or Context7 returned ambiguous or version-conflicting results.

**Preconditions.**

- You ran Context7 (Step 2b) for any [C7-REQUIRED] comment.
- Either: the result is ambiguous across versions, the finding could support either interpretation, or no indexed documentation (and no authoritative web fallback) addresses the claim directly.
- Or: the comment concerns an architectural trade-off that the spec does not decide either way, and both interpretations are defensible.

**Action.** Flag for human decision. Do not apply, do not reject. In the Step 6 summary, state the open question and both sides with citations to the ambiguous evidence.

**Worked example.** Reviewer writes: "Workflow metadata should live in `.<project>/state.json` OR be encoded into a sidecar document the upstream emits — the architecture allows both." Context7 cannot answer project-design questions, and the architecture documentation lists `.<project>/state.json` as the current contract without excluding alternative encodings in the future. → Needs Discussion. Describe both options and flag for the architect.

## Decision rubric for borderline cases

Some comments could plausibly fit multiple categories. Apply these tests in order and take the first match:

1. Does Context7 refute the library claim? → Category 5 (Incorrect).
2. Does the suggestion violate a constraint declared in the project's context files (a "Never" rule, an architectural invariant, a forbidden pattern, a layer-hierarchy breach)? → Category 5 (Incorrect).
3. Does the referenced code still exist? → No: Category 6 (Outdated).
4. Is the concern already resolved in the current tree? → Category 3 (Already Addressed).
5. Does Context7 or the architecture documentation confirm the concern?
   - Yes, and it is in scope for the current change → Category 1 (Valid & Actionable).
   - Yes, but it is out of scope → Category 2 (Valid — Deferred).
6. Is the Context7 result ambiguous or version-conflicting? → Category 7 (Needs Discussion).
7. None of the above; the comment is pure taste → Category 4 (Subjective / Stylistic).

## Context7 verdict → allowed category mapping

The Library Evidence Table verdict constrains the allowable classification. The table below is the contract between Step 2 and Step 3.

| Context7 verdict                        | Allowed categories                                  |
|-----------------------------------------|-----------------------------------------------------|
| REVIEWER CORRECT                        | Category 1 (in scope) or Category 2 (out of scope)  |
| REVIEWER CORRECT — optional improvement | Category 1, Category 2, or Category 4 (genuinely equal-quality alternatives only) |
| REVIEWER INCORRECT                      | Category 5                                          |
| AMBIGUOUS / VERSION-CONFLICTING         | Category 7                                          |
| FALLBACK: web (authoritative)           | Same as the equivalent Context7 verdict             |
| N/A (not a library behavior claim)      | Any of the seven, based on logic and spec           |

A classification that violates this mapping is a Step 2d Binding Rule violation. Stop and re-read the evidence table.
