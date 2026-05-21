# Story Template

Use when the issue is a user-visible feature, capability, or behaviour change. Load in Workflow Step 4 (Draft per type) when the classified type is `Story`. Compose body content in Jira wiki markup per `jira-syntax`.

## Template

Copy verbatim. Fill required sections. Drop bracketed `[…]` sections when they do not apply. Cite existing code by `file:line` in every section where source is referenced.

```
h2. Summary

{One paragraph stating what this Story delivers and why it matters to the user. State the capability, not the implementation. Not a restatement of the title.}

h2. Background

{What exists today and why it falls short. Why this is needed now (trigger, deadline, dependency). Constraints (technical, business, regulatory). References to related issues, files, or modules - cite by file:line where relevant.}

h2. [Proposed solution]

{Optional - include when the reporter has investigated and has a concrete suggestion. Name the file or module the change touches, the approach in 1-2 paragraphs, and any specific values (timeouts, defaults, feature flag). State explicitly that the proposal is a starting point for the implementer, not a mandate.}

h2. [Out of scope]

{Optional - include when the Story has ambiguous edges.}

* {Item observers may expect but this Story does not deliver}
* {Adjacent feature explicitly deferred to a separate ticket}
* {Surface change rejected with rationale}

h2. Requirements

* {MUST observable outcome verifiable by test or visible result}
* {MUST NOT regression - default behaviour preserved where applicable}
* {Each requirement independently verifiable}
* {Minimum 2 requirements; target 3-5}

h2. [Self-checks]

h3. Automated (CI)

* {Specific test name and assertion, e.g. "Component renders the new button when permission X is granted"}
* {Linter, type-check, or schema-validator run that must pass}

h3. Manual

* {Operator-runnable scenario with specific data: account, route, action, observable result}
* {Permission-denied or fallback path scenario when applicable}

h2. Context

{Origin (where this Story came from - product brief, customer request, internal discussion). Verbatim quote of the original request if any. Related tickets and links to design docs. Examples: "Related to [PROJ-148]", "Requested by @alice in 2026-04 product review", "Discussed in [design doc|https://...]".}
```

## Filled example

```
h2. Summary

Allow operators to revoke a long-lived API key from the admin console without leaving the session, removing the 10-15 minute support escalation that currently blocks revocation during incidents.

h2. Background

API keys today can only be revoked via the support team's internal CLI ({{tools/admin-cli/revoke-key.sh}}). Operators routinely escalate revocation requests during incidents; the 10-15 minute response time exceeds the published 5-minute SLA. The admin console already authenticates operators with the same RBAC the CLI uses ({{src/auth/rbac.ts:42-67}}) and exposes the keys list view ({{src/app/admin/keys/page.tsx}}), so the missing surface is a per-row action plus the revoke endpoint.

h2. Proposed solution

Add a "Revoke" button to each row in the keys list view. On click, open a confirmation dialog; on confirm, POST to {{/api/admin/keys/{id}/revoke}}. Implement the endpoint in {{src/app/api/admin/keys/[id]/revoke/route.ts}}, gated on {{admin:keys.revoke}}. Emit an {{api_key.revoked}} event into the existing audit-log substrate ({{src/services/audit/emitter.ts}}). Starting point for the implementer; the dialog wording and confirmation copy can be refined in review.

h2. Out of scope

* Self-service key issuance by customers (tracked separately, [PROJ-2100]).
* Programmatic revocation via the public API.
* Bulk revocation across multiple keys in one action.

h2. Requirements

* Operators with the {{admin:keys.revoke}} permission MUST see a "Revoke" button on every active key in the keys list view.
* Clicking "Revoke" MUST prompt for confirmation; on confirm, the key MUST be disabled.
* A revoked key MUST return 401 within 60 seconds of revocation across all regions.
* A revocation event MUST appear in the audit log with operator, target key, and timestamp.
* Operators without the {{admin:keys.revoke}} permission MUST NOT see the "Revoke" button.
* Already-revoked keys MUST display as "Revoked" and the "Revoke" button MUST be absent for them.

h2. Self-checks

h3. Automated (CI)

* Component test ({{src/app/admin/keys/__tests__/page.test.tsx}}): assert "Revoke" button visible when {{useUserPermissions()}} returns {{admin:keys.revoke}}.
* Component test: assert "Revoke" button absent when the permission is missing.
* Integration test ({{src/app/api/admin/keys/[id]/revoke/__tests__/route.test.ts}}): assert {{POST /api/admin/keys/{id}/revoke}} returns 204 and an audit row appears within 60 seconds.
* {{npm run typecheck}} and {{npm run lint}} pass.

h3. Manual

* As an operator with the permission, revoke a key on test account {{customer-staging-001}}; observe 401 from the customer's next API call within 60 seconds.
* As an operator without the permission, navigate to the keys list and confirm the "Revoke" button is not rendered on any row.

h2. Context

Requested by @alice in the 2026-04 product review. Related: [PROJ-148] (audit log schema). Permissions table reference: {{docs/permissions.md}}. The RBAC role already covers {{admin:keys.revoke}}; no new role required.
```
