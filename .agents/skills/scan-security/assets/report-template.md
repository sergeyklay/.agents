# Security Audit Report

**Commit:** {full SHA}
**Scope:** {all | code | deps | changed}
**Date:** {ISO 8601, e.g., 2026-05-13}

## Summary

| Severity | Found | Fixed | Remaining |
|---|---|---|---|
| Critical | N | N | N |
| High     | N | N | N |
| Medium   | N | N | N |
| Low      | N | N | N |
| **Total** | **N** | **N** | **N** |

**Verdict:** CLEAN | FIXED | ACTION REQUIRED

- CLEAN: no findings.
- FIXED: findings were present and fully remediated.
- ACTION REQUIRED: one or more findings remain open and require human action.

## Fixed ({N} findings)

For each successfully remediated finding:

- **[ID] [Severity] [CWE or CVE]** `{location or package}`: {one-sentence description}. **Fix applied:** {what was changed; why it resolves the issue}.

## Manual Review Required ({N} findings)

Findings that could not be auto-remediated. A human must act on each one before this branch can be considered secure.

### {ID}: {Short title}

- **Severity:** {critical | high | medium | low}
- **Type:** {CWE-NNN description | CVE-YYYY-NNNNN}
- **Location:** `{file:line-range | package@version}`
- **Description:** {what the vulnerability is; what an attacker could do}
- **Why not auto-fixed:** {specific technical reason, e.g., "upgrade path requires major version bump that changes the exported API surface of X"}
- **Recommended action:** {concrete steps a developer should take}
- **Acceptance criteria:** {how to verify the fix is complete}

## False Positives Suppressed ({N} findings)

Findings classified as false positives for project-specific reasons. Each entry cites the project pattern that justifies suppression.

- **[ID] [CWE]** `{location}`: {why this is safe in the project's context; cite the documented pattern from project context or architecture documentation}.

## Tracked - Low Priority ({N} findings)

Low-severity findings with no safe upgrade path at this time. Triage into the project backlog.

- **[ID] [CVE]** `{package@version}`: {description}. Fixed in: `{version}`. Blocker: {reason a safe upgrade is not yet possible}.

## Next Steps

Bulleted, ordered by impact. Be specific: name files, packages, and commands. Include at least one item when any findings remain open. Use "None required" only when the verdict is CLEAN.
