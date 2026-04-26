---
name: babysit-pr
description: "Resolve reviewer comments on a pull request or pasted feedback using a six-step evidence-grounded protocol. Use when asked to resolve review feedback, address reviewer comments, process PR comments, triage review feedback, apply review suggestions, handle code review feedback, decide which review comments to accept or reject, or babysit a PR through its review lifecycle. The protocol verifies every library claim with Context7, classifies each comment across seven categories, applies changes surgically or defers them to the project's issue tracker, and emits a summary intended strictly for the human operator. The skill NEVER posts replies, reactions, or messages back to the reviewer. Do NOT use for authoring a new code review, for security scans, or for opening a new PR."
metadata:
  author: Serghei Iakovlev
  version: "2.0"
  category: review
---

# Babysit PR — Reviewer Comment Resolution Protocol

Apply changes that genuinely improve the work. Respectfully decline those that do not. Every accept, reject, defer, or skip is backed by documented evidence: Context7 lookups, the project's architecture documentation, or an explicit logical argument grounded in the code. The goal is not to mark every comment resolved; the goal is to ship correct, maintainable work.

This skill carries the protocol. The project supplies the standards: coding conventions, verification commands, architectural invariants, tracker choice, and Context7 mechanics live in the project's context files (AGENTS.md, CLAUDE.md, CONTRIBUTING.md, README.md) and architecture documentation. This skill tells you *how to reason*; the project tells you *what to reason about*.

## Running scripts bundled with this skill

Script paths in this document (e.g. `scripts/`) are resolved relative to **this** SKILL.md file, not to your current working directory. If a relative command fails to resolve, prefix it with the path your platform loaded this SKILL.md from.

**Fallback.** If `python3` is not installed or the script cannot be located, every procedure in this skill provides a manual alternative — follow those steps instead.

## Prerequisites

Before executing any step, confirm:

1. **`gh` CLI** is available and authenticated — required for Source B (fetching comments from a GitHub PR). Inline-input mode (Source A) does not need it.
2. **Context7** is available and you know its workflow (two calls: `resolve-library-id`, then `query-docs`). This skill defines *when* to use it; the project context defines *how*.
3. **Project verification commands** (formatter, linter, tests, type checker) are documented in the project's context files. You will read those at Step 4a and run only the subset relevant to what you change.
4. **Project architecture documentation** can be located. Common forms: a dedicated file (`docs/architecture.md`, `ARCHITECTURE.md`), an architecture section inside the primary context file (AGENTS.md/CLAUDE.md), a directory of design notes, or a set of accepted ADRs. If no dedicated doc exists, treat the most architecturally-detailed context file as the de facto record. Never guess what the architecture says — read it.
5. **Issue tracker discovery** happens in Step 4b. Do not assume GitHub Issues, Jira, GitLab, Linear, or any specific tool until you have evidence from project context.

## Workflow

Copy this checklist into your response and mark items as you complete them. Do not skip gates. Each gate exists to prevent a specific failure mode documented in the protocol's rules.

- [ ] Step 1 — Ingest feedback and classify domain
- [ ] Step 2 — Context7 evidence audit (triage, execute, tabulate, bind)
- [ ] Step 3 — Classify every comment with a per-comment block
- [ ] Step 4 — Apply changes (code, tracker defer, or architecture)
- [ ] Step 5 — Verify no reviewer-facing output was emitted
- [ ] Step 6 — Produce the human-only summary

### Step 1 — Ingest feedback and classify domain

Examine the input the user provided.

**Source A — Inline input.** The user pasted or typed review comments. Use them as-is. Do not fetch anything from a remote tracker.

**Source B — GitHub PR.** The user provided a PR number or URL, or the input is empty and a PR exists on the current branch. Run the fetch script to collect every kind of comment: `python3 scripts/fetch_pr_comments.py [PR_NUMBER]`. The script emits a single JSON object on stdout with `pr`, `inline`, `reviews`, and `issue` fields.

If `python3` or the script is unavailable, run the three commands it wraps — missing any of them silently drops a class of comments:

```bash
PR=$(gh pr view --json number --jq '.number')
gh api "repos/{owner}/{repo}/pulls/${PR}/comments" --paginate
gh api "repos/{owner}/{repo}/pulls/${PR}/reviews"  --paginate
gh pr view "$PR" --json comments --jq '.comments'
```

Classify the feedback domain from what the comments reference:

| Signal                                                              | Domain       | Role      |
|---------------------------------------------------------------------|--------------|-----------|
| Source files, function/class names, test failures, idiom or style   | Code         | Coder     |
| Architecture documentation, design decisions, models, ADRs          | Architecture | Architect |
| Both                                                                | Mixed        | Split the comments into two groups; resolve each in its own domain |

### Step 2 — Context7 evidence audit

**MANDATORY.** Complete every sub-step before assigning any classification to any comment. There are no exceptions.

A reviewer asserting that a library behaves a certain way is making a verifiable, falsifiable claim. Context7 is the verification mechanism. Accepting or rejecting on unchecked library assumptions is the proximate cause of both false approvals and false rejections. This step prevents both failure modes.

#### 2a. Triage — which comments require Context7

For each collected comment, answer: *does this comment reference, either explicitly or implicitly, the behavior, API surface, correct usage pattern, or known limitations of an external library, framework, SDK, or third-party API?*

If yes, mark the comment **[C7-REQUIRED]** in your internal analysis.

The tag is a working annotation for Steps 2b–2c and Step 3 reasoning only. It MUST NEVER appear in tracker-visible artifacts (PR replies, ticket bodies, the Step 6 summary, or any other output visible outside your own reasoning).

For the heuristic that decides what counts as a library claim, the categories of comments that do NOT require Context7, the cautious-default rule, and the failure-recovery procedure, read [references/context7-triage.md](references/context7-triage.md).

The default posture is cautious: **when in doubt, run Context7.** A false positive (running it when not strictly necessary) costs one tool call. A false negative (skipping it when needed) costs a wrong classification and a defensible-looking mistake.

#### 2b. Execute the Context7 workflow

For every **[C7-REQUIRED]** comment, run the two-step Context7 workflow per the project's Context7 usage instructions. Follow those instructions for query phrasing, topic filtering, token budgets, and failure recovery.

When the library is not indexed and you fall back to an authoritative source (the library's official docs, its package-registry page, or its GitHub README at the version pinned in the project's manifest), record `[FALLBACK: web]` in the evidence table. The finding is still treated as authoritative; only the logistics differ.

#### 2c. Library Evidence Table

Build this table completely before proceeding to Step 3. Every **[C7-REQUIRED]** comment gets exactly one row. The table is evidence, not interpretation — classification comes in Step 3.

Use [assets/evidence-table-template.md](assets/evidence-table-template.md) as the structural template. It contains a blank skeleton, filled example rows demonstrating each verdict type, and column-discipline notes.

#### 2d. Binding rules

These rules govern every classification in Step 3. They are not guidelines; they are gates. They exist to counteract the well-documented tendency of language models to drift toward agreeing with whoever spoke last — a drift that is the proximate cause of both sycophantic acceptance of wrong suggestions and sycophantic rejection of correct ones when the reviewer's tone becomes uncertain.

1. **Refuted library claim ⇒ not Valid.** A comment whose library claim Context7 refutes CANNOT be classified as Valid. It is Incorrect or Counterproductive, regardless of the reviewer's seniority, the certainty of their tone, or any perceived social pressure to agree.
2. **Confirmed library claim ⇒ not Subjective.** A comment whose library claim Context7 confirms has an objective basis. Classify it on correctness and scope grounds, never as Subjective.
3. **Confirmed but out of scope ⇒ Deferred, not Subjective.** The confirmation is real; only the timing is wrong. Route it to Step 4b.
4. **Ambiguous result ⇒ Needs Discussion.** If Context7 returns ambiguous, version-conflicting, or contradictory results, classify the comment as Needs Discussion. Document the exact ambiguity in the Step 6 summary — which claims conflict, and across which versions.
5. **Skipped [C7-REQUIRED] comment ⇒ may not classify.** If you did not run Context7 for a [C7-REQUIRED] comment, you may not classify it. Stop, return to Step 2b, and run it.
6. **Context7 vs project architecture documentation ⇒ architecture wins.** Context7 describes what a library *can* do; the project's architecture documentation specifies what this project *will* do. When they conflict, the project's specification wins.

### Step 3 — Classify every comment

With the Library Evidence Table complete, classify every comment. Write the per-comment classification block verbatim before assigning a category. Forcing yourself through each field catches comments that seem clear but turn out to depend on an unverified library claim or an unstated architectural assumption.

Use [assets/classification-block-template.md](assets/classification-block-template.md) as the structural template. It contains the blank block, a filled example, and discipline notes.

The seven categories:

| Category                          | Action                        |
|-----------------------------------|-------------------------------|
| Valid & Actionable                | Apply the fix (Step 4a / 4c)  |
| Valid — Deferred to Backlog       | Tracker triage (Step 4b)      |
| Valid but Already Addressed       | Skip with explanation         |
| Subjective / Stylistic            | Skip with explanation         |
| Incorrect or Counterproductive    | Reject with rationale         |
| Outdated / Stale                  | Skip with explanation         |
| Needs Discussion                  | Flag for human decision       |

For precise criteria, worked examples, the borderline-case decision rubric, and how Context7 verdicts map to each category, read [references/classification-categories.md](references/classification-categories.md).

### Step 4 — Apply changes

#### 4a. Code-domain comments (Valid & Actionable)

1. Locate the exact file and line range.
2. **Before writing any fix that uses an external library API,** run Context7 for the *implementation* — not just for the classification. Verify the exact method signature, parameter types, and return shape against current documentation. The reviewer may be correct in direction but wrong in the specific API call they suggested.
3. Implement the change surgically. Modify only what is necessary.
4. Run the project's documented verification commands. Project context files (AGENTS.md, CLAUDE.md, CONTRIBUTING, README) declare the canonical commands for formatting, linting, type checking, and testing. Read them, then run only the subset relevant to what you changed:
   - A change to source code runs the formatter, linter, type checker (if any), and the tests covering the affected area.
   - A change to documentation runs the documentation linter or link checker if defined; otherwise no verification is needed.
   - A change to configuration runs the schema validator if defined; otherwise no verification is needed.
   Follow declared commands verbatim. Do not substitute equivalents (e.g., do not invoke a tool directly when conventions specify a task runner). If conventions are silent on a category you touched, infer the default from the project's manifest and note the inference in the Step 6 summary so the human operator can confirm.
5. If the suggestion is directionally correct but the proposed implementation is suboptimal, implement a **better version** that addresses the underlying concern. Document the divergence in the Step 6 summary.

#### 4b. Deferred comments — tracker triage

A comment classified **Valid — Deferred to Backlog** in Step 3 is a real concern the agent has chosen not to fix in the current change. The Deferred classification is a *promise* that the concern will be tracked. The promise is only valid if backed by a ticket reference.

**Hard rule. Deferred ↔ ticket.** Every comment that ends Step 4b in the Deferred category MUST resolve to a ticket reference — either a newly created ticket or an existing ticket already covering the concern. A Deferred comment without a ticket reference is forbidden, regardless of which tracker the project uses: it is a memory leak in the review process. If the workflow below cannot produce a ticket reference, the comment was misclassified — return to Step 3 and pick a different category.

Step 4b begins with **discovery, not action**. Two discoveries happen before any ticket is created.

##### Discover the project's issue tracker

The project uses one of: GitHub Issues, Jira, GitLab Issues, Linear, or another tracker. Identify it from the strongest available signal:

1. **Project context files first.** AGENTS.md / CLAUDE.md / README.md / CONTRIBUTING.md may explicitly name the tracker — "issues live in Jira project ABC", "open a GitHub issue", a Linear board URL, a tracker-specific ticket-key convention. Trust these; they are authoritative.
2. **Repository signals second.** A GitHub remote with a `.github/` directory and an authenticated `gh` CLI suggests GitHub Issues. Atlassian URLs (`*.atlassian.net`) in commit messages, PR descriptions, or branch names suggest Jira. GitLab CI configuration and `gitlab.com` remotes suggest GitLab Issues. Treat these as evidence only when context files do not name a tracker explicitly.
3. **If ambiguous, ask the user.** Do not guess between two equally plausible trackers. State both candidates and the evidence for each, then ask which is canonical for the backlog.

##### Discover sibling skills that manage the chosen tracker

The current session loads a catalogue of skills. Inspect their descriptions for words that match the chosen tracker — typically descriptions naming the tracker, naming a ticket type, or describing operations like "create a ticket", "manage backlog", "triage issues", "manage roadmap", "manage epics". A matching skill is the *correct* tool because it carries project-specific conventions (label taxonomy, body templates, duplicate-detection logic, parent-epic resolution, custom-field handling) that hand-rolled CLI calls do not.

If a matching skill exists, load and apply it for the create operation. Pass the deferred concern with full context: the file:line being deferred, the reviewer attribution, and the gate verdicts below. Let the discovered skill handle the mechanics; this skill's job is to decide *whether* to create a ticket and *what it should contain semantically*, not to format ticket payloads.

If no matching skill exists, fall back to manual creation:

- For GitHub Issues: `gh issue create` with a clear title, a body that names the file:line and the reviewer, and labels inferred from the project's existing issue conventions (read a few existing open issues for examples).
- For Jira / GitLab / Linear: use any available API or MCP tool the session exposes. Compose the description in the project's expected markup.
- Note in the Step 6 summary that ticket creation was hand-rolled (no managing-skill found) so the human operator can verify the result against project conventions.

##### Apply the three triage gates in order

The gates validate the Deferred classification. They are not silent stops: if a gate trips, the comment was misclassified and Step 3's category was wrong. **Reclassify and continue — never leave a Deferred comment without a ticket.**

1. **Architecture-conflict gate.** Read the relevant section of the project's architecture documentation. If the suggestion contradicts the design intent — not merely the current implementation — the comment is **Incorrect or Counterproductive (Category 5)**, not Deferred. Reclassify, cite the architecture rule as the rejection rationale, and document the reclassification in the Step 6 summary's Rejected section. Do not create a ticket.

2. **Duplicate check.** Search open tickets for existing work covering this concern, even partially. If a matching ticket exists, the Deferred classification is validated. The outcome is `{existing ticket reference} (existing)`. Do not create a new ticket.

3. **Scope test.** Would this realistically matter within the scope of the project's open milestones, epics, or roadmap?
   - **Yes** → proceed to creation.
   - **Out of current horizon, but the project has a backlog / icebox / future-ideas lane** → create the ticket in that lane. Deferred stands.
   - **Out of current horizon, with no appropriate lane** → the comment is **Needs Discussion (Category 7)**, not Deferred. Reclassify and flag for the human operator to decide whether the project should track aspirational work at all.

##### Create the ticket and verify

If gates 1 and 3 pass, create the ticket via the discovered skill (preferred) or the manual fallback. Confirm the create operation returned a ticket identifier (the tracker echoed an ID, key, or URL) — a silent failure means no ticket exists, which means the comment cannot stay in Deferred.

Record the outcome in the Step 6 summary as `{ticket reference} (created via discovered skill)` or `{ticket reference} (created via manual fallback)`. If creation failed and cannot be retried in this session, reclassify as **Needs Discussion (Category 7)** with the failure noted, and flag for the human operator to create the ticket manually.

#### 4c. Architecture-domain comments (Valid & Actionable)

1. Locate the relevant section of the project's architecture documentation.
2. Revise the specification to address the concern.
3. Verify internal consistency — the change must not contradict other architectural sections, supporting diagrams, contracts, or accepted ADRs.
4. If the revision has downstream implications for existing code (e.g., a state transition was renamed, a validation rule tightened, a contract reshaped), enumerate them in the Step 6 summary so the human operator can schedule follow-up code work.

Never modify accepted ADRs without explicit instruction from the user. Accepted ADRs preserve the context, alternatives, and consequences of prior decisions; rewriting them retroactively destroys the historical record.

### Step 5 — Verify no reviewer-facing output

**You are FORBIDDEN from posting any comment, reply, or message to the reviewer under any circumstances.**

This prohibition is absolute and has no exceptions:

- Do NOT post reply comments to any review comment, inline or otherwise.
- Do NOT post issue-level comments on the PR conversation tab.
- Do NOT share your analysis, reasoning, plans, or rationale with the reviewer.
- Do NOT explain why you accepted or rejected a suggestion.
- Do NOT evaluate or react to the quality of the review.
- Do NOT use any CLI or API call that writes to the PR (comments, reviews, reactions, resolutions, marking-as-outdated).

Before producing the Step 6 summary, confirm you have not executed any of the forbidden operations. All reasoning, all evidence, all decisions belong in the summary for the human operator — not in the PR thread.

### Step 6 — Produce the summary

Write the summary using [assets/summary-template.md](assets/summary-template.md). The template has one section per category plus the source header and the Context7 evidence log.

If the validator script is available, run it on the summary file: `python3 scripts/validate_report.py <summary-file>`. Fix any reported violations and re-run until it reports PASS.

If the script is unavailable, verify manually using this checklist:

- [ ] Source header present (PR #N / Inline feedback / Mixed).
- [ ] Context7 Evidence Log table has one row per [C7-REQUIRED] comment.
- [ ] All seven category sections are present, including empty ones.
- [ ] No `[C7-REQUIRED]` tags appear anywhere in the summary.
- [ ] Every populated entry names the file:line changed.
- [ ] Every "Deferred" entry names a ticket reference (newly created or existing). Any Deferred entry missing a ticket is a misclassification — move it to Rejected (Category 5) or Needs Discussion (Category 7).
- [ ] Every "Rejected" entry cites specific Context7 or architecture evidence.
- [ ] Every "Needs Discussion" entry names the open question and both sides.

## Constraints

- **NEVER post any comment, reply, or message to the reviewer.** This is the single highest-priority rule. Skill output is for the human operator only.
- Do NOT fabricate review comments. Work only with comments from the identified source.
- Do NOT apply changes that break the project's documented verification commands. After every fix in Step 4a, the relevant verification subset must pass.
- Do NOT act on a suggestion about library behavior without first running Context7 for any [C7-REQUIRED] comment, regardless of how confident you feel.
- Do NOT classify a [C7-REQUIRED] comment before Step 2b completes for that comment.
- Do NOT leave a Deferred comment without a ticket reference. Deferred ↔ ticket — every Deferred entry in the Step 6 summary must name a newly created or already existing ticket. If no ticket can be produced (the architecture forbids the work, no roadmap lane exists, the create operation failed without recovery), reclassify the comment in Step 3 as Rejected or Needs Discussion. "Just defer it" without follow-through is forbidden regardless of tracker.
- Do NOT skip Context7 because you feel confident about the API. Confidence is the proximate cause of hallucination. Certainty is earned from documentation, not recalled from training data.
- Do NOT reference the project's architecture documentation, ADRs, section numbers, or ticket IDs in source-code comments — those belong in specs and plans, not source.
- Do NOT introduce dependencies, languages, toolchains, or patterns that the project context forbids. If AGENTS.md / CLAUDE.md declares a "Never" rule (forbidden libraries, banned patterns, prohibited APIs), the rule binds you regardless of any reviewer suggestion to the contrary.
- Preserve the project's existing code style, module boundaries, and architectural conventions.
- When rejecting, your rationale must be technical and specific — never dismissive. Cite Context7 findings when they support the rejection.

### Scope boundaries

The skill's responsibility ends at deciding what to do with each comment and applying the minimum change that resolves it. Adjacent actions belong to other skills or to the human operator.

- Do NOT commit or push. Leave the working tree modified; commit and PR creation belong to separate skills.
- Do NOT alter PR metadata — status, labels, assignees, reviewers, milestone, or branch protection settings.
- Do NOT close, merge, approve, or reopen the PR.
- Do NOT resolve, delete, or rename review threads. Thread state belongs to the PR author.
- Do NOT switch branches or modify files outside the paths named in a comment classified Valid & Actionable.

## Guiding principles

1. **Library claims are falsifiable.** A reviewer asserting an API behavior is making a verifiable claim. Context7 verifies it. Accepting or rejecting without verifying is the root cause of both false approvals and false rejections.
2. **Quality over harmony.** Never apply a change that makes the work worse, regardless of who suggested it or how confidently.
3. **Architecture wins over library capability.** When the project's architecture documentation and Context7 conflict, architecture wins. Context7 describes what a library *can* do; architecture specifies what the project *will* do.
4. **Spec-first, code-second.** For architecture-domain feedback, the specification is the source of truth; code follows. Revising code without revising the spec is drift.
5. **Think like a maintainer, not a people-pleaser.** The goal is not to mark every comment resolved. The goal is to ship correct, maintainable work.
6. **Be thorough but surgical.** Apply the minimum change that fully addresses the concern. Every changed line must trace to a classified comment.
7. **Every decision needs evidence.** Document reasoning, source, and conclusion for every apply, skip, or reject. Assertions without citations are opinions.
8. **Defer wisely, not reflexively.** "Not now" is only valid when paired with a tracked ticket — Deferred ↔ ticket, regardless of which tracker the project uses. A deferred comment without a ticket reference is forbidden: it is a promise the agent has no way to keep. If Step 4b cannot produce a ticket, the comment was misclassified; move it to Rejected or Needs Discussion.
