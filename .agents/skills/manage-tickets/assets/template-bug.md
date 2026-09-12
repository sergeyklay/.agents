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

{The documented or intended behaviour. If a spec or constant defines it, cite by file:line: "the polling cadence is governed by {{STATUS_POLL_INTERVAL_MS}} (path/to/constants.ts:11)".}

h2. Observed behaviour

{What happens instead. Anchor each observation to the code path that produces it: "After the final progress event fires from inside processBatch (path/to/worker.ts:757-769), the dialog displays processed === total but status is still RUNNING."}

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

{Origin (where this bug came from - manual validation, production incident, customer report, internal review). Verbatim quote of the original report if any: "After the job finished I still see the dialog with the progress bar full and no autoclose." Investigation trace summary: who looked, what was ruled out, what evidence anchors the Root cause section. Related tickets and links to logs.}
```

## Filled example

```
h2. Summary

After an API key is revoked from the keys list, the confirmation dialog keeps showing "Revoking..." with the spinner for an extended period before switching to the success view. Once the success view appears, the dialog never auto-closes; the operator must click Close manually.

h2. Steps to reproduce

# Sign in as a user holding the {{admin:keys.revoke}} permission.
# Navigate to {{/admin/keys}}.
# Choose any active key row and press Revoke.
# Confirm the destructive preview to start the revocation.
# Watch the dialog enter its progress phase; the spinner appears and the row is marked pending.
# Observe that the dialog keeps showing "Revoking..." for tens of seconds after the key has already stopped authenticating.
# Eventually the dialog flips to "Key revoked" with the green check and a "Back to keys" button.
# Note that the dialog never auto-closes; it stays open until the operator clicks Close.

h2. Expected behaviour

When the back end marks the key {{revoked}}, the dialog transitions to the success view within one polling interval ({{STATUS_POLL_INTERVAL_MS = 2_000}} at {{path/to/constants.ts:11}}). After the success view is shown, the dialog auto-closes within 2-3 seconds via a toast notification so the operator can return to the key roster without an extra click.

h2. Observed behaviour

The revoke endpoint flips the key state and returns, but the dialog polls a status field that the audit-log write updates only afterwards ({{path/to/revoke-handler.ts:120-148}}). {{RevokeProgressView}} ({{path/to/revoke-progress-view.tsx:180-209}}) keeps rendering the spinner while the handler emits the {{api_key.revoked}} event and waits for the emitter to acknowledge it; that acknowledgement takes 10-30 seconds under load. {{RevokeDialog.handleTerminalStatusChange}} at {{path/to/revoke-dialog.tsx:321-331}} then sets the phase to 'completed' but never calls {{onOpenChange(false)}}.

h2. Root cause

Two independent issues compose into the observed UX.

*Issue A - No auto-close on terminal status (primary).* {{handleTerminalStatusChange}} ({{path/to/revoke-dialog.tsx:321-331}}) renders the success view but never asks the dialog to close. Missing UX affordance since the component shipped.

*Issue B - Audit acknowledgement delays the terminal state (visibility amplifier).* The handler awaits the audit emitter before reporting the terminal state. The dialog faithfully shows the truth - the operation is still in flight - but the key is already unusable and the operator perceives the dialog as stuck.

h2. Proposed solution

Confine the fix to {{path/to/revoke-dialog.tsx}}. Add an auto-close {{useEffect}} that watches {{phase}}; when {{phase}} becomes 'completed', schedule a {{setTimeout}} to call {{onOpenChange(false)}} after 2500 ms. Clear the timer on unmount and when {{phase}} changes, so an operator who closes the dialog manually before the timer fires sees no late side effect. Pair the auto-close with a toast notification so the completion signal is not lost.

Issue B (audit acknowledgement delay) is acknowledged but explicitly out of scope; track it in a follow-up if the "stuck on Revoking" perception persists after the auto-close lands.

h2. Out of scope

* No edits to {{RevokeProgressView}}, the event emitter, the revoke handler, or any service-layer file. The fix is UI-only.
* No new event type.
* No change to {{STATUS_POLL_INTERVAL_MS}}.

h2. Requirements

* After the key reaches the revoked state and {{RevokeDialog}} enters the 'completed' phase, the dialog MUST auto-close within 3 seconds via {{onOpenChange(false)}}.
* A toast notification confirming "Key revoked" MUST appear when the dialog auto-closes so the completion signal is preserved.
* The auto-close MUST be cancellable: if the operator clicks Close before the timer fires, the dialog closes immediately and the timer is cleared with no further side effects.
* The auto-close MUST NOT fire on a failed revocation; the dialog stays open with the failure view.
* The auto-close MUST NOT fire while {{phase}} is 'progress', even if the row already reads as pending. The trigger is {{phase === 'completed'}}, not visual progress.
* The change MUST be confined to {{path/to/revoke-dialog.tsx}}. {{RevokeProgressView}}, the emitter, the handler, and all service files MUST be untouched.

h2. Self-checks

h3. Automated (CI)

* Unit test: drive {{RevokeDialog}} from pending to revoked via a mocked terminal-status callback; assert {{onOpenChange(false)}} is called exactly once within 3000 ms.
* Unit test: drive to 'completed', then trigger manual Close before the auto-close timer fires; assert {{onOpenChange(false)}} is called exactly once.
* Unit test: drive to the failed state; advance fake timers past the auto-close delay; assert {{onOpenChange(false)}} was NOT called.
* Unit test: drive to 'completed', unmount; advance fake timers; assert no call after unmount.
* The repository's type-check and lint commands pass.

h3. Manual

* Revoke a disposable key on a scratch account; observe the dialog auto-closes 2-3 seconds after the "Key revoked" view appears; observe the success toast.
* Trigger a deliberate failure (revoke a key that another session already revoked); observe the dialog stays open showing the failure message; no auto-close.

h2. Context

Surfaced during manual validation of the self-serve key revocation flow. The operator reported: "After the key was revoked I still see the dialog with the spinner and no autoclose." Investigation traced the symptom to two independent factors (no auto-close logic in the dialog, and the audit acknowledgement that precedes the terminal state). This ticket scopes the fix to the primary user-visible complaint; the acknowledgement-delay visibility issue is acknowledged and left for a separate ticket if it remains a complaint after this fix lands.
```
