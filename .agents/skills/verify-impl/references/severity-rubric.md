# Severity Rubric

Use this reference at Phase 4 of `verify-impl` whenever classifying a non-PASS finding. The severity assigned drives downstream decisions: critical findings block acceptance, major findings request changes, minor findings document divergence without blocking.

## Contents

- Severity definitions
- Anti-inflation rules
- Worked examples per level

## Severity definitions

| Severity | Definition | Verdict impact |
|---|---|---|
| `critical` | Safety violation, data loss, behavioral contradiction, security boundary breach, undefined behavior under documented inputs, or contract violation that breaks downstream consumers | Maps to **NON-CONFORMANT** verdict; pipelines treat as `revise` |
| `major` | Correctness bug under expected inputs, missing functionality the spec mandates, incorrect algorithm step that produces wrong output for valid inputs | Maps to **CHANGES REQUIRED** verdict; pipelines treat as `revise` |
| `minor` | Naming divergence, style divergence, code organization not aligned with project conventions, comments that should reference the spec but do not | Does not by itself block; **CONFORMANT** verdict can stand if all findings are `minor` |

## Anti-inflation rules

These rules counteract the well-documented tendency of reviewers to over-grade for safety. Inflation makes the severity classification useless because every finding becomes "critical."

1. **Naming-only divergence is `minor`.** A function called `processData` instead of `process_data` is `minor`, regardless of how strongly the spec specifies naming. It does not change behavior.
2. **Style-only divergence is `minor`.** Different but equivalent control flow (early return vs nested if) is `minor` if behavior is identical.
3. **Documentation gaps are `minor`.** A missing comment, a missing docstring, a TODO that was not removed - `minor`.
4. **Behavioral divergence under expected inputs is `major` at minimum.** If the spec says "return -1 on not-found" and the code returns `null`, this is at least `major`, even if downstream callers happen to treat both as falsy.
5. **Safety-invariant violation is `critical`.** If the spec says "must validate before persisting" and the code persists without validation, that is `critical` regardless of whether validation happens elsewhere.
6. **Security-boundary breach is `critical`.** If the spec defines a trust boundary and the code violates it (e.g., accepting unvalidated input across the boundary), that is `critical` regardless of intent.
7. **Concurrency unsafety is `critical` when the spec mandates thread safety.** Race conditions are `critical` even if intermittent - race conditions appear non-deterministically and bypass tests, so under-grading them is the proximate cause of production incidents.

## Worked examples

### Example 1 - `minor`

**Spec.** "The function shall be named `parse_json_payload`."

**Code.**

```go
func ParseJSONPayload(...) {...}
```

**Severity.** `minor`. Naming divergence; behavior is correct.

### Example 2 - `major`

**Spec.** "The retry policy shall back off exponentially with base 2 starting at 100ms."

**Code.**

```go
backoff := 100 * time.Millisecond  // fixed delay
```

**Severity.** `major`. Behavior differs from spec under expected inputs; observable in retry timing but does not corrupt data.

### Example 3 - `critical`

**Spec.** "Before persisting any user-submitted record, the implementation MUST validate that `tenant_id` matches the authenticated session's tenant."

**Code.**

```go
db.Insert(record)  // no validation
```

**Severity.** `critical`. Safety-invariant violation; cross-tenant data leak under normal usage. Even if validation happens upstream in some call paths, the spec mandates it here, and skipping it is a security boundary breach.

### Example 4 - `critical` (despite "compiles fine")

**Spec.** "All database access shall propagate the request context for cancellation."

**Code.**

```go
func (s *Store) Get(id string) (*Record, error) {
    return s.db.QueryRow("SELECT ...", id).Scan(...)  // implicit context.Background()
}
```

**Severity.** `critical`. Concurrency contract violated. Even though the code compiles and works in tests, it cannot be cancelled - meaning a slow query will block requests forever, exhausting the request pool. The spec mandates context propagation specifically to prevent this failure mode.
