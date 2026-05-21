# Bug Template

Use when the issue is a defect, regression, or behaviour that deviates from a documented or intended specification. Load in Workflow Step 4 (Draft per type) when the classified type is `Bug`. Compose body content in Jira wiki markup per `jira-syntax`.

## Template

Copy verbatim. Fill required sections. Drop bracketed `[…]` sections when they do not apply. Cite existing code by `file:line` in every section where source is referenced.

```
h2. Summary

{One sentence stating the broken behaviour: what happens, where, since when. The Summary is not a restatement of the title - it adds the orienting context (component, version range, who is affected).}

h2. Steps to reproduce

# {Numbered steps from a clean state}
# {Include test data, fixtures, accounts, archives, commands - whatever is needed for someone else to reproduce}
# {End with the exact action that exposes the bug}

h2. Expected behaviour

{The documented or intended behaviour. If a spec or constant defines it, cite by file:line: "the polling cadence is governed by {{SCAN_PROGRESS_POLL_INTERVAL_MS}} (src/hooks/constants.ts:11)".}

h2. Observed behaviour

{What happens instead. Anchor each observation to the code path that produces it: "After the final scan:progress event fires from inside processEmailBatch (src/services/pipeline/workflow.ts:757-769), the dialog displays emailsProcessed === emailsTotal but scanStatus.status is still RUNNING."}

h2. [Root cause]

{Optional - include only when the reporter has investigated. Diagnose the source of the defect with file:line anchors. When two distinct issues compose into the symptom, split into Issue A (primary) and Issue B (amplifier or co-cause). Include relevant code excerpts when they fit in 5-15 lines.}

h2. [Relationship to {RELATED-KEY}]

{Optional - include when the bug surfaced during work on another ticket. Disambiguate regression-from vs surfaced-during. Cite the related ticket and the line at which their change does or does not affect this defect.}

h2. [Proposed solution]

{Optional - include when the reporter knows the fix shape. Name the file the change touches, describe the approach in 1-2 paragraphs, and pin specific values (timeouts, defaults, retry counts). State explicitly that the proposal is a starting point for the implementer, not a mandate.}

h2. [Out of scope]

{Optional - include when the fix has tempting adjacent edits the implementer should resist.}

* {Adjacent file the fix MUST NOT touch}
* {Behaviour change that belongs in a separate ticket}
* {Constant or feature flag that stays unchanged}

h2. Requirements

* {The Steps to reproduce MUST no longer trigger the defect}
* {A regression test MUST guard the fix}
* {Default behaviour of unrelated paths MUST be preserved}
* {The fix MUST be confined to the files named in Out of scope's complement (when applicable)}
* {Add per-defect MUSTs as needed; each independently verifiable}

h2. [Self-checks]

h3. Automated (CI)

* {Unit/integration test name and the assertion it makes; cite the file the test lives in}
* {Linter, type-check, or schema-validator run that must pass}

h3. Manual

* {Operator-runnable scenario with specific data: account, archive, environment, observable result}
* {Deliberate negative scenario when applicable: trigger the failure path and confirm the fix does not mask other errors}

h2. Context

{Origin (where this bug came from - MC1 validation, production incident, customer report, internal review). Verbatim quote of the original report if any: "After scan finished I still see dialog window with scan progress 1000/1000 with no autoclose." Investigation trace summary: who looked, what was ruled out, what evidence anchors the Root cause section. Related tickets and links to logs.}
```

## Filled example

```
h2. Summary

After a synthetic seed scan reaches 100% progress, the admin seed dialog displays "1000/1000 - Seed run in progress" with the spinner for an extended period before transitioning to the "Seed run completed" success view. Once the success view appears, the dialog never auto-closes; the operator must click Close manually.

h2. Steps to reproduce

# Sign in as an admin user.
# Navigate to {{/admin/users}}.
# Open {{AdminSeedDialog}} on any user row and upload a synthetic mailbox archive (e.g. {{atlanticmedicalnj@gmail.com.zip}}).
# Confirm the destructive preview to start the seed.
# Watch the dialog enter the progress phase; the progress bar climbs to 100% and the count reaches emailsTotal/emailsTotal.
# Observe that the dialog continues to show 1000/1000 with the spinner and the message "Seed run in progress" for tens of seconds.
# Eventually the dialog flips to "Seed run completed" with the green check and "Back to users" button.
# Note that the dialog never auto-closes; it stays open until the operator clicks Close.

h2. Expected behaviour

When the back-end pipeline reaches {{ScanJob.status = COMPLETED}}, the dialog transitions to the success view within one polling interval ({{SCAN_PROGRESS_POLL_INTERVAL_MS = 2_000}} at {{src/hooks/constants.ts:11}}). After the success view is shown, the dialog auto-closes within 2-3 seconds via a toast notification so the operator can return to the user roster without an extra click.

h2. Observed behaviour

After the throttler's final scan:progress event fires from inside {{processEmailBatch}} (src/services/pipeline/workflow.ts:757-769), the dialog displays emailsProcessed === emailsTotal but {{scanStatus.status}} is still RUNNING. {{AdminSeedProgressView}} (src/components/admin/admin-seed-progress-view.tsx:180-209) keeps rendering the in-progress spinner and the "1000/1000" counter while the back end runs {{extractBusinessProfile}} (src/services/pipeline/workflow.ts:778-782) and {{tagContactRelationships}} (src/services/pipeline/workflow.ts:785-789); each takes 10-30 seconds. Only after both finish does {{transitionScanJob(scanJobId, 'COMPLETED')}} at src/services/pipeline/workflow.ts:792 flip the DB status. {{AdminSeedDialog.handleTerminalStatusChange}} at src/components/admin/admin-seed-dialog.tsx:321-331 sets the phase to 'completed' but never calls {{onOpenChange(false)}}.

h2. Root cause

Two independent issues compose into the observed UX.

*Issue A - No auto-close on terminal status (primary).* {{handleTerminalStatusChange}} (src/components/admin/admin-seed-dialog.tsx:321-331) renders the success view but never asks the dialog to close. Missing UX affordance since the component shipped.

*Issue B - Post-batch LLM work delays COMPLETED (visibility amplifier).* {{processEmailBatch}} runs {{extractBusinessProfile}} (LLM, 10-30 s) and {{tagContactRelationships}} (LLM, 10-30 s) between the final progress event and the COMPLETED transition. The dialog faithfully shows the truth - the scan is still running - but the progress bar is full and the operator perceives the dialog as stuck.

h2. Proposed solution

Confine the fix to {{src/components/admin/admin-seed-dialog.tsx}}. Add an auto-close {{useEffect}} that watches {{phase}}; when {{phase}} becomes 'completed', schedule a {{setTimeout}} to call {{onOpenChange(false)}} after 2500 ms. Clear the timer on unmount and when {{phase}} changes (e.g. if the operator closes the dialog manually before the timer fires). Pair the auto-close with a toast notification (existing project toast utility) so the completion signal is not lost.

Issue B (post-batch LLM delay) is acknowledged but explicitly out of scope; track it in a follow-up if the "stuck at 1000/1000" perception persists after the auto-close lands.

h2. Out of scope

* No edits to {{AdminSeedProgressView}}, the event bus, the orchestration, or any service-layer file. The fix is UI-only.
* No new scan:phase event type.
* No change to {{SCAN_PROGRESS_POLL_INTERVAL_MS}}.

h2. Requirements

* After {{ScanJob.status}} transitions to COMPLETED and {{AdminSeedDialog}} enters the 'completed' phase, the dialog MUST auto-close within 3 seconds via {{onOpenChange(false)}}.
* A toast notification confirming "Seed run completed" MUST appear when the dialog auto-closes so the completion signal is preserved.
* The auto-close MUST be cancellable: if the operator clicks Close before the timer fires, the dialog closes immediately and the timer is cleared with no further side effects.
* The auto-close MUST NOT fire on FAILED status; the dialog stays open with the failure view.
* The auto-close MUST NOT fire while {{phase}} is 'progress', even if emailsProcessed === emailsTotal. The trigger is {{phase === 'completed'}}, not visual progress.
* The change MUST be confined to {{src/components/admin/admin-seed-dialog.tsx}}. {{AdminSeedProgressView}}, the event bus, the orchestration, the workflow, and all service files MUST be untouched.

h2. Self-checks

h3. Automated (CI)

* Unit test: drive {{AdminSeedDialog}} from QUEUED → RUNNING → COMPLETED via mocked {{onTerminalStatusChange}}; assert {{onOpenChange(false)}} is called exactly once within 3000 ms.
* Unit test: drive to 'completed', then trigger manual Close before the auto-close timer fires; assert {{onOpenChange(false)}} is called exactly once.
* Unit test: drive to FAILED; advance fake timers past the auto-close delay; assert {{onOpenChange(false)}} was NOT called.
* Unit test: drive to 'completed', unmount; advance fake timers; assert no call after unmount.
* {{npm run typecheck}} and {{npm run lint}} pass.

h3. Manual

* Seed {{atlanticmedicalnj@gmail.com.zip}} against a clean user; observe the dialog auto-closes 2-3 seconds after the "Seed run completed" view appears; observe the success toast.
* Trigger a deliberate failure (invalid token, network-blocked LLM); observe the dialog stays open showing the failure message; no auto-close.

h2. Context

Surfaced during the manual MC1 validation step for the synthetic-seed end-to-end check. The operator reported: "After scan finished I still see dialog window with scan progress 1000/1000 with no autoclose." Investigation traced the symptom to two independent factors (no auto-close logic in the dialog, and the multi-second post-batch LLM work before COMPLETED transitions). This ticket scopes the fix to the primary user-visible complaint; the post-batch LLM-work visibility issue is acknowledged and left for a separate ticket if it remains a complaint after this fix lands.
```
