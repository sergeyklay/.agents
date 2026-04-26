# Library Evidence Table — Template

Build this table at Step 2c. One row per **[C7-REQUIRED]** comment. The table is evidence, not interpretation — classification happens in Step 3.

## Blank template

Copy this into your analysis and fill one row per [C7-REQUIRED] comment:

| # | Comment (summary) | Library | Context7 query (reformulated) | Context7 finding | Verdict |
|---|---|---|---|---|---|
| 1 |   |   |   |   |   |
| 2 |   |   |   |   |   |

## Filled examples (calibration)

These rows demonstrate column discipline across all five verdict types. The libraries are drawn from disparate ecosystems on purpose — the protocol mechanics are independent of stack, and the examples should not bias the agent toward any one project's dependencies.

| # | Comment (summary) | Library | Context7 query (reformulated) | Context7 finding | Verdict |
|---|---|---|---|---|---|
| 1 | "Pass `signal: AbortSignal.timeout(ms)` to this `fetch` call" | Node.js global `fetch` (undici-based) | "Does Node.js global `fetch` accept `signal: AbortSignal` in v20, and is `AbortSignal.timeout(ms)` supported?" | `fetch` accepts `signal: AbortSignal`; `AbortSignal.timeout(ms)` is the idiomatic way to bound the request and is supported in Node 18+ | **REVIEWER CORRECT** |
| 2 | "Use the recommended `WrapRegistererWith` helper for label composition instead of a custom registry" | prometheus client_golang | "Does `prometheus/client_golang` recommend `WrapRegistererWith` for label composition?" | The current recommendation is `WrapRegistererWith` for new code; the older custom-registry pattern still works but is no longer idiomatic | **REVIEWER CORRECT — optional improvement** |
| 3 | "Switch from REST `/search/issues` to GraphQL `searchIssues` to avoid stricter rate limits" | GitHub GraphQL API | "Are GitHub GraphQL `search` nodes subject to a different secondary rate limit than REST `/search/issues`?" | Both share the same secondary-rate-limit budget for search endpoints; GraphQL has no inherent advantage | **REVIEWER INCORRECT** |
| 4 | "Was `useFormState` renamed to `useActionState` and is the signature the same?" | React | "Was `useFormState` renamed to `useActionState` in React 19, and what changed in the signature?" | Both names exist across the React 18.3 → 19.0 transition. In 19, `useActionState` is the canonical name and the signature differs in argument order. The right answer depends on the project's pinned React major | **AMBIGUOUS** |
| 5 | "GitLab Pipelines API returns the new pipeline ID at the top level of the body" | GitLab Pipelines API v5 | (no Context7 match for "gitlab pipelines"; fell back to the official docs) | Per GitLab's official API reference, `POST /projects/:id/pipeline` returns the pipeline as JSON with `id` at the top level; documented and stable in v5 | **FALLBACK: web** |

## Column discipline

- **Comment (summary)** — a short quote or paraphrase, not a full paragraph. Enough to identify the claim.
- **Library** — the library name as it appears in the project's manifest, with the version designation when relevant ("React 19", not just "React"; "Jira Cloud REST API v3", not just "Jira API"). Use whatever shorthand the project itself uses; if the project pins a specific major, name the major.
- **Context7 query (reformulated)** — the specific question you sent to `query-docs`, not the reviewer's wording verbatim. Reformulating the reviewer's claim as a question forces you to extract the falsifiable kernel.
- **Context7 finding** — what the retrieved documentation actually says about the claim. Cite concretely. Never "Context7 confirms" or "Context7 agrees" — state the specific behavior the docs describe.
- **Verdict** — exactly one of:
  - **REVIEWER CORRECT**
  - **REVIEWER CORRECT — optional improvement** (the claim is valid but the suggestion is a non-mandatory refinement)
  - **REVIEWER INCORRECT**
  - **AMBIGUOUS** (or **VERSION-CONFLICTING**)
  - **FALLBACK: web** (Context7 not indexed; an authoritative web or registry source consulted — the finding is still treated as authoritative)

The verdict feeds Step 3 via the mapping in the classification-categories reference (loaded alongside this template when the agent enters Step 3).
