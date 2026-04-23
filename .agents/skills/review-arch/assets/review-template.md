# Architecture Review: [system or task name]

- **Status:** Draft
- **Reviewer:** [name or agent]
- **Date:** YYYY-MM-DD
- **Artefact under review:** [path to spec / diagram / codebase / GitHub issue]

---

## Context summary

[2-3 sentences confirming your understanding of the system, its goals, and its constraints. This is the author's chance to correct misunderstandings before reading the review. If the author disagrees with the framing here, the rest of the review is not grounded and needs to be revisited.]

**Stated priorities (in order):** [e.g. 1. Availability, 2. Data integrity, 3. Cost, 4. Time to market.] If priorities are not stated, record that here and promote it to the first Open Question below.

---

## Critical risks

[Issues that could cause system failure, data loss, security breach, or fundamental inability to meet a stated requirement. Must be addressed before the system proceeds. Sort severity-descending. Omit this section entirely if there are no critical risks - do not invent one to fill space.]

### C1: [Short descriptive title]

- **Finding.** [Concrete statement of what is wrong, with evidence anchor: file path, line range, decision reference, or quoted requirement.]
- **Why it matters.** [Which quality attribute (ISO/IEC 25010:2023 name) or business goal is threatened. One or two sentences.]
- **Mechanism.** [How the risk manifests in practice. Cite an anti-pattern by name if one applies.]
- **Recommendation.** [Concrete action. Name the tradeoff the recommendation makes. Do not say "fix it"; say what to do.]

### C2: [Short descriptive title]

[Same structure. Repeat for each critical risk.]

---

## Significant concerns

[Issues that will cause pain over time - technical debt, scalability ceiling, operational burden, coupling that will slow future change, a tradeoff pointing the wrong way. Should be addressed before scaling the system beyond its current context, but do not block a next step. Sort severity-descending.]

### S1: [Short descriptive title]

- **Finding.** [Concrete statement with evidence anchor.]
- **Why it matters.** [Named quality attribute or business consequence. How soon this becomes a real problem.]
- **Mechanism.** [How it fails. Cite a pattern or anti-pattern by name if applicable.]
- **Recommendation.** [Concrete action with the tradeoff named.]

### S2: [Short descriptive title]

[Same structure. Repeat for each significant concern.]

---

## Observations

[Worth noting but not blocking. Alternative approaches the author may want to consider, minor structural issues, points worth monitoring. One or two sentences each. Do not inflate - if there are no observations, say "None."]

- **O1.** [Observation. One or two sentences.]
- **O2.** [Observation.]
- **O3.** [Observation.]

---

## Strengths

[Sound decisions that fit the stated requirements. 1-3 sentences total. Do not enumerate every good decision; pick the decisions that are non-obviously correct or that reinforce the priorities well. The purpose of this section is to show that the reviewer examined the whole system, not only the problems.]

[1-3 sentences.]

---

## Open questions

[Things the reviewer cannot evaluate without more information from the team. Specific questions, not vague requests for "more detail". Each question should be one the team can answer in a sentence; if the answer cannot be that concise, the question is too broad to be useful.]

1. [Specific question, one sentence.]
2. [Specific question.]
3. [Specific question.]

---

## Verdict

[One line - optional, include only for formal ARB-style reviews that expect a decision.]

**Decision:** [Block / Request changes / Approve with notes / Approve]

**Rationale:** [One or two sentences. The decision follows from the findings above; the rationale names which findings drove it.]

---

<!-- Template-usage notes (remove these before saving the review)

Section calibration:

- Critical risks: zero or more. Cap at about three. More than three usually means the critical/significant line is drawn wrong; revisit severity.
- Significant concerns: zero or more. Cap at about five.
- Observations: zero or more. Cap at about five. More than that, and the review is drowning the actual findings.
- Strengths: 1-3 sentences total across the whole section. Not per strength. Per whole section.
- Open questions: zero or more. Cap at about five.

Anchors that every Critical and Significant finding needs:

1. A concrete evidence anchor: file path with line range, a quoted requirement, a named decision in a design doc, a named field in a data model.
2. A named quality attribute from ISO/IEC 25010:2023, where one applies: Functional suitability, Performance efficiency, Compatibility, Interaction capability, Reliability, Security, Maintainability, Flexibility, Safety.
3. A named mechanism of failure. Often this is an anti-pattern name (distributed monolith, shared database, synchronous call chain, dual-write, chatty services, etc. - see references/anti-patterns.md).
4. A recommendation that names its own tradeoff. "Use async events here, which trades immediate consistency for independent service deployment - correct direction because the stated priority is availability."

Calibration against the review-philosophy.md checklist:

- Every Critical and Significant finding is anchored in a stated priority from Context Summary.
- No finding is a nit.
- No finding lifts a pattern from a different context without explaining why it applies here.
- No finding is a preference promoted to a risk.
- The full review reads in under five minutes.

-->
