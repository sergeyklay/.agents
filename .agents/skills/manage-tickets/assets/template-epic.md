# Epic Template

Use when the issue is a body of work containing multiple Stories, Tasks, or Bugs, scoped around a single business outcome. Load in Workflow Step 4 (Draft per type) when the classified type is `Epic`. Compose body content in Jira wiki markup per `jira-syntax`.

## Template

Copy verbatim. Fill required sections. Drop bracketed `[…]` sections when they do not apply. Cite existing code or prior tickets by `file:line` or key where relevant.

```
h2. Summary

{One paragraph stating what this Epic groups and the business outcome it delivers. Frame as the change in user, operator, or business state, not the engineering work.}

h2. Background

{Why this Epic now. Stakeholders. Dependencies on other Epics or external commitments. Constraints (compliance, timeline, budget).}

h2. Scope

In scope:

* {Capability or area the Epic delivers}
* {Capability or area the Epic delivers}

Out of scope:

* {Capability observers may expect but this Epic does not deliver - with reference to the separate ticket or roadmap item carrying it}

h2. Requirements

* {High-level observable signal that the Epic delivered - often a metric, milestone, or product behaviour}
* {MUST: explicit success criterion}
* {Minimum 2 requirements; keep them coarse - per-Story criteria live in the Stories}

h2. [Self-checks]

h3. Automated (CI)

* {Cross-cutting test, dashboard, or metric that proves the Epic's outcome, beyond what individual Stories test}

h3. Manual

* {Operator-runnable end-to-end scenario that exercises the Epic's full flow}

h2. Context

{Milestone, owning team, related Epics, links to product brief or design docs.}
```

## Filled example

```
h2. Summary

Self-serve API key lifecycle for paying tenants, so support is removed from the critical path for issue, rotate, and revoke flows.

h2. Background

Support handles roughly 80 API-key requests per week, half of which are revocations during incidents. Each request takes a support engineer 5-15 minutes and blocks customers from acting on their own keys. The admin console already supports operator authentication ({{src/auth/rbac.ts:42-67}}); the missing surface is the customer-facing UI ({{src/app/customer/keys/}}) and the audit/RBAC plumbing behind it.

h2. Scope

In scope:

* Customer-facing UI to issue, list, rotate, and revoke keys.
* Audit log for every lifecycle event.
* Per-key RBAC.

Out of scope:

* Changes to key signing or storage (stays on existing infra).
* Usage-based billing (tracked separately).
* Programmatic key issuance via the public API ([PROJ-2300], separate roadmap item).

h2. Requirements

* All four lifecycle operations (issue, list, rotate, revoke) MUST be available in the customer admin UI.
* Support ticket volume for API-key requests MUST drop by at least 70% measured over a 30-day window after launch.
* Every lifecycle event MUST appear in the audit log within 60 seconds.
* Existing operator-side workflows MUST remain functional - the customer-side UI is additive.

h2. Self-checks

h3. Automated (CI)

* End-to-end test in {{tests/e2e/customer-key-lifecycle.spec.ts}} covers issue → list → rotate → revoke for a single customer account.
* Audit-log dashboard query returns a non-empty result set for each lifecycle event type within 24 hours of launch.

h3. Manual

* Run a 7-day shadow period: support continues to handle existing tickets but routes new requests to the self-serve flow; collect operator feedback on the customer flow.

h2. Context

Owner: Platform team. Target: 2026 Q3. Related Epics: [PROJ-1700] (audit logging substrate), [PROJ-1900] (RBAC v2). Product brief: [https://...]. Designs: [https://...].
```
