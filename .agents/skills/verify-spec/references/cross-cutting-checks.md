# Cross-Cutting Verification Dimensions

Use this reference at Phase 5 of `verify-spec`. The eight dimensions below cover properties that span multiple requirements and are easy to miss in line-by-line review. For each dimension, run the check only when the project's tech stack and the spec's domain make it relevant - and skip explicitly rather than silently.

## Contents

- Dimension 1: Dependency direction
- Dimension 2: Naming consistency
- Dimension 3: Context and lifecycle management
- Dimension 4: Error handling
- Dimension 5: Concurrency safety
- Dimension 6: Interface compliance
- Dimension 7: Security boundaries
- Dimension 8: Data safety
- When to skip a dimension

## Dimension 1: Dependency direction

**Question.** Does the implementation respect the project's layer hierarchy and dependency rules?

**How to check.** From Phase 1's project documentation, identify the layered architecture (e.g., `domain → application → infrastructure`). Walk the implementation's import graph and verify no upstream layer imports a downstream one. Look for `internal/` boundary violations and unauthorized cross-package access.

**When to skip.** Single-package or flat projects with no layering convention.

## Dimension 2: Naming consistency

**Question.** Do identifiers follow the project's established conventions?

**How to check.** From Phase 1's review standards, identify the naming conventions (PascalCase vs camelCase, snake_case vs kebab-case, public/private prefixes, file naming patterns). Spot-check identifiers introduced by the implementation against the convention. Look for inconsistencies *within* the new code (mixed conventions).

**When to skip.** Projects with no documented naming convention. Use the dominant pattern in the existing codebase as the implicit convention before skipping.

## Dimension 3: Context and lifecycle management

**Question.** Are resources, contexts, and connections properly managed?

**How to check.** Identify resource-acquiring calls (file opens, DB connections, HTTP clients, locks, watchers). Verify each has a paired release path on every code path including errors. For context-aware languages (Go's `context.Context`, Python's `asyncio` cancellation, Rust's lifetimes), verify propagation through every layer the spec covers.

**When to skip.** Pure compute / pure data-transformation specs with no resource acquisition.

## Dimension 4: Error handling

**Question.** Does error handling follow the project's established patterns and the spec's error categories?

**How to check.** From Phase 2's `error-handling` requirements, list the error categories the spec defines. For each, verify the implementation classifies errors into the documented categories and routes them per the spec (retry, propagate, terminal). Look for `panic` or unhandled exceptions where the spec mandates structured error returns. Look for swallowed errors (caught and discarded).

**When to skip.** Specs that explicitly delegate error handling to a referenced framework or downstream consumer.

## Dimension 5: Concurrency safety

**Question.** Is mutable state access properly synchronized?

**How to check.** Identify shared state (package-level variables, struct fields accessed from multiple goroutines/threads). Verify each is either immutable, properly synchronized (mutex, atomic, channel), or documented as single-threaded. Look for read-modify-write patterns without synchronization. Look for goroutine/thread leaks (started without bounded lifetime).

**When to skip.** Specs that explicitly declare a single-threaded execution model.

## Dimension 6: Interface compliance

**Question.** Do concrete types satisfy their declared interfaces?

**How to check.** From Phase 2's `interface-contract` requirements, identify each interface the spec defines or references. For each concrete type that should implement the interface, verify all required methods are present, with correct signatures. Look for methods that satisfy the interface syntactically but with incompatible semantics (e.g., a `Close()` method that does not actually release resources).

**When to skip.** Specs without explicit interfaces (e.g., pure procedural specifications).

## Dimension 7: Security boundaries

**Question.** Are trust boundaries, input validation, and access controls implemented per spec?

**How to check.** Identify trust boundaries from the spec (network ingress, user input, untrusted third-party data). For each, verify validation/sanitization is present at the boundary. Verify access-control checks are not bypassable through alternate code paths. Verify secrets are not logged or exposed in error messages.

**When to skip.** Specs that explicitly inherit security checks from a parent layer or middleware. Verify the parent layer is invoked instead - do not skip without that confirmation.

## Dimension 8: Data safety

**Question.** Are queries parameterized, transactions properly bounded, and data integrity maintained?

**How to check.** Identify all data-store interactions. Verify queries are parameterized (no string concatenation of user input into SQL/NoSQL queries). Verify transactions wrap the spec-mandated atomic units - neither narrower (loses atomicity) nor wider (causes contention). Verify constraint violations are handled per spec.

**When to skip.** Specs with no persistence layer (pure compute, pure routing).

## When to skip a dimension

A skipped dimension must be **explicitly skipped** in your output, not silently dropped. Use phrasing like:

> Dimension 5 (Concurrency safety) - skipped: spec declares single-threaded execution model in §2.1.

Skipping without explanation is the failure mode this reference exists to prevent.
