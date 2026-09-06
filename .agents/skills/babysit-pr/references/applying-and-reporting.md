# Applying changes and reporting

The per-domain apply procedures behind Step 4a and Step 4c, and the draft checklist that gates the Step 6 summary. Read the section matching the work in front of you.

## Contents

- Code-domain comments (Step 4a)
- Architecture-domain comments (Step 4c)
- Summary draft checklist (Step 6)

## Code-domain comments (Step 4a)

1. Locate the exact file and line range.
2. **Before writing any fix that uses an external library API,** run Context7 for the *implementation* - not just for the classification. Verify the exact method signature, parameter types, and return shape against current documentation. The reviewer may be correct in direction but wrong in the specific API call they suggested.
3. Implement the change surgically. Modify only what is necessary.
4. Run the project's documented verification commands. Project context files (AGENTS.md, CLAUDE.md, CONTRIBUTING, README) declare the canonical commands for formatting, linting, type checking, and testing. Read them, then run only the subset relevant to what you changed:
   - A change to source code runs the formatter, linter, type checker (if any), and the tests covering the affected area.
   - A change to documentation runs the documentation linter or link checker if defined; otherwise no verification is needed.
   - A change to configuration runs the schema validator if defined; otherwise no verification is needed.
   Follow declared commands verbatim. Do not substitute equivalents (e.g., do not invoke a tool directly when conventions specify a task runner). If conventions are silent on a category you touched, infer the default from the project's manifest and note the inference in the Step 6 summary so the human operator can confirm.
5. If the suggestion is directionally correct but the proposed implementation is suboptimal, implement a **better version** that addresses the underlying concern. Document the divergence in the Step 6 summary.

## Architecture-domain comments (Step 4c)

1. Locate the relevant section of the project's architecture documentation.
2. Revise the specification to address the concern.
3. Verify internal consistency - the change must not contradict other architectural sections, supporting diagrams, contracts, or accepted ADRs.
4. If the revision has downstream implications for existing code (e.g., a state transition was renamed, a validation rule tightened, a contract reshaped), enumerate them in the Step 6 summary so the human operator can schedule follow-up code work.

## Summary draft checklist (Step 6)

Before sending the response, verify the draft against this checklist:

- [ ] Source header present (PR #N / Inline feedback / Mixed).
- [ ] Tracker header present (discovered tracker, or "n/a - no items deferred").
- [ ] Context7 Evidence Log table has one row per [C7-REQUIRED] comment.
- [ ] All seven category sections are present, including empty ones (use `_(none)_` for empty bodies).
- [ ] No `[C7-REQUIRED]` tags appear anywhere in the summary.
- [ ] Every populated entry names the source file:line referenced.
- [ ] Every "Deferred" entry names a ticket reference (newly created or existing). Any Deferred entry missing a ticket is a misclassification - move it to Rejected (Category 5) or Needs Discussion (Category 7).
- [ ] Every "Rejected" entry cites specific Context7 or architecture evidence.
- [ ] Every "Needs Discussion" entry names the open question and both sides.
