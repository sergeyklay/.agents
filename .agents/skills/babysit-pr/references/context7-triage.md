# Context7 Triage — Library Claim Heuristic

Use this reference at Step 2a (triage decisions) and Step 2b (executing the workflow). It defines the heuristic that decides which reviewer claims require Context7 validation, the categories of claims that do not, the cautious-default rule, and the procedure when Context7 lacks coverage.

## Contents

- What counts as a library claim
- Comments that do NOT require Context7
- The "when in doubt, run it" rule
- Examples that look safe but are not
- Handling Context7 failures

## What counts as a library claim

A reviewer comment makes a **[C7-REQUIRED]** library claim when both conditions hold:

**(1) The claim concerns an external surface.** External means anything *not* native to the project's language standard library and *not* internal to the project. Specifically:

- A dependency declared in the project's manifest (`package.json`, `go.mod`, `pyproject.toml`, `Cargo.toml`, `Gemfile`, `pom.xml`, `*.csproj`, `composer.json`, etc.).
- A third-party REST / GraphQL / gRPC API the project consumes.
- An external SDK, CLI, or service whose behavior the code depends on.
- A framework's version-specific behavior (routing, middleware, lifecycle hooks, runtime configuration, build pipeline).

**(2) The claim is specific.** Specific claims have a falsifiable kernel — Context7 either confirms or refutes them. Indicators:

- It names a symbol (function, method, class, constant, parameter, hook, decorator, attribute).
- It asserts version-dependent behavior (a feature was added, removed, renamed, or reshaped in version X).
- It compares two libraries, two versions, or two transports ("X is faster than Y at task Z", "GraphQL has a different rate limit than REST").
- It references a configuration option, header, status code, error code, schema field, endpoint path, or migration step.
- It describes a "should" behavior the API is supposed to expose.

If both conditions hold, the comment is **[C7-REQUIRED]**.

If either condition fails — the surface is internal, or the claim is too vague to falsify — the comment does not require Context7.

The project's context files (AGENTS.md, CLAUDE.md) and architecture documentation may further refine "external" for the project's stack. If those documents identify specific dependencies as well-known and stable enough to skip Context7 for, treat that as an authoritative override of the default cautious posture. In the absence of such an override, the heuristic above governs.

## Comments that do NOT require Context7

The following categories never trigger [C7-REQUIRED]:

- **Logic errors.** Off-by-one, wrong predicate, missing guard, unused variable, dead code. The reviewer is reasoning about the code's own logic; no library API is involved.
- **Architectural and design decisions.** When the project's architecture documentation, ADRs, or context files have already settled a question, that settlement wins. Context7 cannot override project-internal design decisions.
- **Naming, documentation, or formatting.** Pure style. Follow project conventions, not external sources.
- **Project-internal patterns already specified.** If the project context establishes a pattern (testing approach, error-handling shape, layout convention, layer hierarchy), no external verification is needed.
- **Language standard library facts.** Standard libraries are backward-compatible by design and have authoritative first-party documentation. Do not call Context7 for stdlib symbols of the project's language.
- **Operating-system, shell, or version-control semantics.** These belong to their tools' own documentation, not to Context7.

## The "when in doubt, run it" rule

The default posture is cautious. A false positive (running Context7 when it turns out the claim was internal or vague) costs one tool call. A false negative (skipping Context7 when the claim was external and version-dependent) costs a wrong classification plus any downstream work built on it.

The asymmetry favors running it.

If a claim straddles the internal / external boundary — for example, a question about how the project's own wrapper around an external library behaves — split the claim. The wrapper is internal (no Context7); the wrapped library's behavior is external (Context7 if specific).

## Examples that look safe but are not

These claims look like they might be internal but turn out to involve external library behavior. Treat each as **[C7-REQUIRED]**:

- "Pass a cancellation token / context to `<wrapper>.NewWatcher()`." Whether the wrapped library accepts a cancellation primitive — and how — is library- and version-specific.
- "Use the new `<hook>` API instead of the deprecated `<previous>` hook." Deprecation timing and replacement semantics differ across major versions.
- "Use the recommended `<helper>` for composition instead of the direct constructor." Recommendations evolve; the helper may not exist in the version pinned by this project.
- "Page results with the standard `<header>` headers." Pagination conventions vary across REST / GraphQL / SDKs and across endpoint families.
- "Use `<auth helper>` instead of the older `<token method>`." Auth surfaces are major-version-sensitive and fail silently when called wrong.
- "Round-trip preserves comments and ordering with `<format library>`." Format-library round-trip semantics differ across versions.
- "This `<query method>` returns `<type>` directly in the body." Response shapes change across API versions and across regional deployments.

If you catch yourself thinking "I already know how this library works" about any specific claim, treat that as a signal to run Context7, not a license to skip it. Confidence is the proximate cause of hallucination.

## Handling Context7 failures

### `resolve-library-id` returns no match

1. Try alternative names. Common patterns:
   - Full package path ↔ short name (e.g. `@scope/package` ↔ `package`, `github.com/org/project` ↔ `project`).
   - Author/repo form ↔ registry form (e.g. `org/project` ↔ npm/PyPI/crates name).
   - Old name ↔ new name (libraries are sometimes renamed across major versions).
2. Fall back to authoritative documentation. Priority order:
   - The library's official documentation site (a canonical `docs.<project>.dev`-style URL).
   - The library's repository README at the version pinned in the project's manifest.
   - The package registry page for the project's language (npm, PyPI, crates.io, pkg.go.dev, Maven Central, RubyGems, NuGet, Packagist, etc.).
   - For external APIs: the vendor's official REST / GraphQL / SDK reference.
   Do not use random blog posts or community Q&A as authoritative.
3. Record `[FALLBACK: web]` in the Library Evidence Table. Include the URL of the authoritative source in your internal reasoning so the evidence is auditable.
4. Proceed with classification as if Context7 had returned the same finding, per the Step 2d Binding Rules.

### `query-docs` returns irrelevant content

1. Narrow the `topic` parameter — use a single specific word (`transitions`, `pagination`, `webhooks`, `migrations`, `transactions`, `routing`, `caching`, `streaming`, `auth`, `middleware`).
2. Rephrase the query to be more specific — name the exact symbol, the exact version, the exact scenario.
3. Reduce the `tokens` budget to force higher-relevance filtering.
4. If the best result still does not address the claim, classify the comment as **Needs Discussion** per Binding Rule 4. Do not guess.
