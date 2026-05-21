# Task Template

Use when the issue is non-feature work: infrastructure, build, dependencies, documentation, chores, or technical work without a direct user-facing surface. Load in Workflow Step 4 (Draft per type) when the classified type is `Task`. Compose body content in Jira wiki markup per `jira-syntax`.

## Template

Copy verbatim. Fill required sections. Drop bracketed `[…]` sections when they do not apply. Cite existing code by `file:line` in every section where source is referenced.

```
h2. Summary

{One paragraph stating the work and its motivation. Not "we should do X" - state what changes and why now.}

h2. Background

{What triggered the task, what depends on it, any constraints. Include version numbers, deadlines, or compliance drivers if relevant. Cite the files or modules the task touches.}

h2. [Proposed solution]

{Optional - include when the recipe is known. Name the files the change touches, the migration or upgrade approach, and any breaking-change handling. State that the proposal is a starting point.}

h2. [Out of scope]

{Optional - include to bound the chore.}

* {Adjacent file or module the task MUST NOT touch}
* {Behaviour change that belongs in a separate ticket}

h2. Requirements

* {MUST checkable outcome that proves the task is done}
* {MUST preserve any documented behaviour the task is not changing}
* {Each requirement independently verifiable}

h2. [Self-checks]

h3. Automated (CI)

* {Test, lint, or schema-validator run that proves the task succeeded}
* {Regression test guarding any behaviour the task is not supposed to change}

h3. Manual

* {Operator-runnable scenario when CI cannot cover the change (e.g. infra rollout, deploy validation)}

h2. Context

{Origin (compliance deadline, dependency EOL, incident postmortem, etc.). Related tickets, links to upstream notes or migration guides. Who needs to approve or review.}
```

## Filled example

```
h2. Summary

Upgrade the {{pg}} Node.js driver from 8.11.x to 9.0.x across the API and worker services, ahead of the 8.x end-of-life on 2026-08-01.

h2. Background

8.11.x reaches end-of-life on 2026-08-01 per the upstream support policy. 9.0.x is a major version bump; the migration guide lists three breaking changes that touch our codebase: removed {{Client.escape}} (used in {{src/db/legacy.ts:23}}, {{src/db/legacy.ts:51}}, {{src/db/legacy.ts:88}}), changed default {{ssl}} handling ({{src/db/client.ts:14}}), and stricter type checks on {{numeric}} columns ({{src/db/types.ts:67}}). We pin the driver in both services ({{services/api/package.json}}, {{services/worker/package.json}}); CI installs are reproducible.

h2. Proposed solution

Migrate {{Client.escape}} call sites to parameterised queries in a separate Task ([PROJ-401]) before this upgrade lands - that work is a prerequisite. Once parameterisation is in, bump the pin in both services in a single PR, set explicit {{ssl: { rejectUnauthorized: false }}} where the 8.x default was relied on, and run the integration suite against staging for 48 hours before merging.

h2. Out of scope

* Migrating away from {{pg}} to a different driver. Stay on {{pg}}; only the version changes.
* Schema changes to {{numeric}} columns. The 9.0.x stricter types are accommodated in code, not by relaxing the schema.

h2. Requirements

* Both services MUST pin {{pg}} 9.0.x in {{package.json}} and {{package-lock.json}}.
* {{Client.escape}} call sites in {{src/db/legacy.ts}} MUST migrate to parameterised queries (covered by prerequisite [PROJ-401]).
* All existing integration tests MUST pass without modification, including the {{numeric}}-column tests in {{tests/db/types.spec.ts}}.
* Staging deploy MUST run for 48 hours with no new {{pg}}-related errors in logs.

h2. Self-checks

h3. Automated (CI)

* {{tests/db/**/*.spec.ts}} pass with the new driver pin.
* {{npm run typecheck}} passes for both services.
* {{npm audit}} reports no new high-severity vulnerabilities.

h3. Manual

* Deploy to staging and run the {{scripts/db-smoke-test.sh}} script against a copy of production data.
* Monitor staging logs for 48 hours; confirm no new error patterns containing "pg" in the message.

h2. Context

End-of-life deadline: {{2026-08-01}} per [pg release support policy|https://...]. Migration guide: [https://...]. Related: [PROJ-401] (parameterise legacy queries - prerequisite). Coordinator: @bob. Owning team: Platform.
```
