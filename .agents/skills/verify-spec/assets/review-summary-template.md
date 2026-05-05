## Spec Verification: {SPEC_NAME}

**Spec:** {SPEC_PATH}

### Metrics

- **Requirements extracted:** {N}
- **PASS:** {N} | **DRIFT:** {N} | **PARTIAL:** {N} | **MISSING:** {N} | **CONFLICT:** {N}
- **Conformance rate:** {X}% (PASS / total)
- **Critical findings:** {N} | **Major findings:** {N} | **Minor findings:** {N}

### Verdict: {CONFORMANT | CHANGES REQUIRED | NON-CONFORMANT}

### Key Findings

Findings ordered by severity, then by spec section. Each entry follows this shape:

#### {SEVERITY}: {SHORT_TITLE}

- **Requirement ID:** `{R-section-seq}`
- **Spec quote:** "{verbatim spec text}"
- **Spec location:** §{section} (line {N})
- **Code location:** `{file}:{line_range}`
- **Code quote:**

  ```{lang}
  {verbatim code}
  ```

- **Status:** `{PASS | DRIFT | PARTIAL | MISSING | CONFLICT}`
- **Discrepancy:** {one or two sentences explaining what diverges}
- **Confidence:** `{high | medium}`

(Repeat per finding. PASS findings are not listed individually here - they appear only in the metrics above and the Phase 4 detailed table in the body of the review file.)
