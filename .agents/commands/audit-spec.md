---
description: "Forensic audit of an implementation against its authoritative specification"
---

Your task is to verify that an implementation faithfully realizes **every** requirement, constraint, design decision, interface contract, algorithm, and invariant defined in its authoritative specification.

## Task

- Use the `verify-spec` Agent Skill to drive every phase: build project context, extract every verifiable requirement, discover the implementation surface, classify each requirement (PASS / DRIFT / PARTIAL / MISSING / CONFLICT) with evidence, run the cross-cutting and self-verification passes, then emit the verdict and remediation plan.
- Treat the user-provided argument as the path to the specification file. Read it in its entirety before classifying anything.
- Discover project context by searching the conventional locations - project context files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CONTRIBUTING.md`, `README.md`), architecture documentation, ADR sets, build manifests, and schema files. Do not assume specific filenames or paths; the skill's discovery rules apply.

## Skill Enforcement

**MANDATORY:** Apply the `verify-spec` Agent Skill verbatim.

The skill is the single source of truth for *how* to extract requirements, classify findings, and structure the report. The project's context files are the source of truth for *what* the architecture, layering, naming conventions, and review standards are. Consult each at the moment the skill calls for it.

**Process:**

- Load the `verify-spec` Agent Skill before reading the specification.
- Walk through every phase in order. Do not skip, merge, or abbreviate any phase. Each gate prevents a documented failure mode (recency bias, false-positive amplification, severity inflation, missed cross-cutting concerns).
- If the skill is unavailable in this environment, stop and report the failure. Do not improvise a replacement protocol.
- Write the final review to `.reviews/Review-{spec-name}.md` per the skill's output rules. Print the path of the file written.

## Constraints

- **Review only.** Do not write, modify, refactor, or restructure any source code. A finding proposes a change; an implementer applies it later. Do not commit, branch, or open pull requests.
- **Quote before judging.** Extract the exact spec text before evaluating code against it. This prevents drift between what you think the spec says and what it actually says.
- **Absence is a finding.** Behavior defined in the spec but not implemented is `MISSING`, not "probably handled elsewhere".
- **The spec is the authority.** A divergent implementation that "seems better" is still a defect. If the spec itself is wrong, raise it as a separate flag - do not excuse the implementation divergence.
- **No severity inflation.** Reserve `critical` for safety violations, data loss, and behavioral contradictions. Reserve `major` for correctness bugs and missing functionality. Reserve `minor` for naming and style divergence.
