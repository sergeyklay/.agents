## Remediation: {SPEC_NAME}

**Spec:** {SPEC_PATH}

### Required Fixes (in implementation order)

Fixes are listed in dependency order: shared types and contracts first, callers second. Apply them top-to-bottom; a later fix may depend on an earlier one.

#### Fix 1: {SHORT_TITLE}

- **Severity:** `{critical | major}`
- **File:** `{path/to/file}`
- **Requirement (from spec):** "{exact spec quote}"
- **Spec location:** §{section} (line {N})
- **Current behavior:** {what the code does now, with `{file}:{line}` reference}
- **Required behavior:** {what the code must do instead}
- **Implementation guidance:** {specific, actionable steps - function signatures to change, conditions to add, dependencies to introduce}
- **Done when:** {verifiable condition - a passing test, a code grep that should return zero matches, an invariant that must hold}

#### Fix 2: {SHORT_TITLE}

(Repeat the block above for every critical or major finding. Skip `minor` findings - they go into the review summary, not the remediation plan.)

### Verification Checklist

After all fixes are applied, verify:

- [ ] Project builds without errors
- [ ] Linter passes
- [ ] Tests pass (existing tests + any new tests required by the fixes)
- [ ] Each fix's "Done when" condition is satisfied

If any item fails, the remediation is not complete - address the failure before declaring the spec re-verified.
