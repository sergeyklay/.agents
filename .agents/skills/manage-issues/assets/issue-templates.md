# Issue Body Templates

Five templates indexed by `## <Kind>` headings. Load the relevant section when composing an issue body; drop bracketed `[...]` sections when they do not apply. Required sections are unbracketed.

## Bug

```markdown
## Summary

One-paragraph description of what is broken and how it deviates from expected behavior.

## Root Cause (observed)

What investigation has revealed so far. Include relevant code paths, log output, or state transitions. Only include this section if the root cause is known or strongly suspected.

## Symptoms

Bullet list of observable effects:
- What the user or operator sees
- Error messages, incorrect output, missing data
- Which components are affected

## Steps to Reproduce

1. Numbered steps to trigger the bug
2. Include config, commands, or setup needed
3. State the actual vs expected result

## Verification

The bug is fixed when:
- Specific observable condition that proves correctness
- Test that should pass
```

## Feature

```markdown
One-paragraph description of the capability and its motivation (why this matters, what it unblocks).

[Detail paragraphs as needed: behavior, config fields, CLI flags, defaults, edge cases. Reference related issues with #NNN.]

Verify: concrete command, test, or observable outcome that proves the feature works. Include a default-behavior-preserved check when applicable.
```

## Research

```markdown
One-paragraph framing of the question or uncertainty to resolve.

Options to evaluate:
- Option A with brief rationale
- Option B with brief rationale
- Option C with brief rationale

Priority: [high|medium|low] with brief justification.

[Optional] Deliverable that proves the research is complete (ADR, design doc, prototype, benchmark results).
```

## Docs

```markdown
One-paragraph description of what documentation is missing, outdated, or incorrect.

[Specifics: which pages, sections, or examples need attention.]
```

## Refactor / Test

```markdown
One-paragraph description of what to improve and why (readability, coverage, performance, maintainability).

[Specifics: which packages, files, or patterns are affected.]
```
