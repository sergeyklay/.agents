# Sub-task Template

Use when the issue is a slice of an existing parent Story, Task, or Bug. A Sub-task always has a parent and a narrower scope than the parent. Load in Workflow Step 4 (Draft per type) when the classified type is `Sub-task`. Compose body content in Jira wiki markup per `jira-syntax`.

## Template

Copy verbatim. Fill required sections. Drop bracketed `[…]` sections when they do not apply. Cite the parent and any existing code by `file:line` or key.

```
h2. Summary

{One paragraph stating this slice of the parent's work. Reference the parent by key. State what this Sub-task changes that the parent's other Sub-tasks do not.}

h2. Background

{How this Sub-task fits into the parent. The portion of the parent's requirements this Sub-task addresses. Any ordering relative to sibling Sub-tasks.}

h2. Requirements

* {MUST checkable outcome scoped to this Sub-task}
* {Each requirement independently verifiable}
* {Minimum 1 requirement; 2-3 typical}

h2. [Self-checks]

h3. Automated (CI)

* {Specific test name and assertion the Sub-task adds or makes pass}

h3. Manual

* {Operator-runnable scenario when CI cannot cover this slice}

h2. Context

{Parent key. Sibling Sub-tasks under the same parent. Dependencies. Who is implementing.}
```

## Filled example

```
h2. Summary

Wire the audit-log event emitter into the API-key revoke endpoint, part of parent [PROJ-2100].

h2. Background

[PROJ-2100] introduces self-serve key revocation with an audit-log requirement. The audit-log substrate ([PROJ-1700]) ships a typed event emitter at {{src/services/audit/emitter.ts:14-58}}; this Sub-task adopts it in the revoke endpoint only. Sibling Sub-tasks cover issue, rotate, and list; they will reuse the wiring pattern this Sub-task establishes.

h2. Requirements

* The revoke endpoint MUST emit an {{api_key.revoked}} event on success with operator id, target key id, and timestamp.
* No event MUST be emitted on failure paths (404, 403, validation errors).
* The integration test in {{src/app/api/admin/keys/[id]/revoke/__tests__/route.test.ts}} MUST assert the event payload.

h2. Self-checks

h3. Automated (CI)

* Integration test ({{src/app/api/admin/keys/[id]/revoke/__tests__/route.test.ts}}): assert the emitter is called exactly once with the expected payload on a successful revoke.
* Integration test: assert the emitter is NOT called on 404, 403, or validation-error paths.

h3. Manual

* Trigger a revoke on staging; query the audit log within 60 seconds and confirm the {{api_key.revoked}} row exists.

h2. Context

Parent: [PROJ-2100]. Sibling Sub-tasks: issue endpoint, rotate endpoint, list endpoint (created after this Sub-task lands and establishes the pattern). Coordinator: @carol.
```
