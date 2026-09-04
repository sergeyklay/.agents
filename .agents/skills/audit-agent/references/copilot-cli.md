# GitHub Copilot CLI adapter

Use this route for a GitHub Copilot CLI run. It was verified against CLI 1.0.82. The CLI stores its state under `COPILOT_HOME`, or `~/.copilot` when that variable is unset. `session-state/` and `session-store.db` are CLI-managed internals, not a stable public schema.

## Select evidence

Prefer the narrowest source that answers the request:

| Request | Preferred evidence | Confidence limit |
| --- | --- | --- |
| A completed batch run that can be repeated | `--usage-output-file <path>` | Inspect the emitted JSON before selecting fields or arithmetic. |
| Current interactive session totals | `/usage`, with `/session` for identity and state | A screen value is a snapshot unless the session is closed and preserved. |
| Run timeline, tools, and failures | `session-state/<session-id>/events.jsonl` | Event fields and counter semantics require per-version verification. |
| Cross-session search or aggregation | `session-store.db` | Discover the schema read-only. Do not assume table or column names. |
| Human-readable archive | `/share` output | Treat it as a sensitive transcript, not the source for precise counters. |

Process logs under `logs/` diagnose the CLI. They are not evidence of model usage, tool completion, or a complete session timeline.

## Discover the run

1. Record `copilot --version`, `COPILOT_HOME`, the working directory, model, mode, permission settings, start, end or cutoff, and whether the session can resume.
2. In the interactive CLI, use `/session` to record the session id and `/usage` to record the displayed totals and model breakdown. Do not infer cost from AI credits.
3. Locate `session-state/<session-id>/workspace.yaml` and `events.jsonl` under the resolved Copilot home. Confirm the id, working directory, and time window from their contents before including them.
4. If the session remains resumable or events are still appended, set the result to `snapshot` with a cutoff. Closing the terminal alone does not prove no process can resume or modify the session.

For a fresh, reproducible non-interactive run, request an explicit output file:

```sh
copilot -p '<task>' --usage-output-file usage.json
```

Keep the command's permission options and model selection identical across compared runs. The task may edit the working directory, so run it only in an approved disposable copy or when those edits are part of the intended experiment.

## Reconstruct the event timeline

`events.jsonl` is the durable local event stream. Read it without modifying it. Sample an early, middle, and final record before choosing extraction paths. The CLI emits separate request and completion events, including `tool.execution_complete` with a tool-call id and success flag, but event schemas can change.

Build each tool record by joining a request with its completion on the exact tool-call id. Count a failure only from an explicit completion with `success: false`; an absent completion is incomplete evidence, not a failure or a success. Preserve the tool name, timestamp, session id, and success state. Do not emit arguments or result content unless the request requires sanitized examples.

Treat an assistant message, a model step, and a tool call as separate metrics. Count user turns from explicit user events only. Do not count timeline records, deltas, or UI notifications as turns.

Find delegated sessions through explicit child session ids and parent spawn records. Include a child only after its linkage and boundary are verified. If fleet or subagent attribution cannot be rebuilt from persisted records, report the root alone and mark total attribution incomplete.

## Measure usage and duration

Use the emitted `usage.json` or `/usage` token categories only after recording their labels exactly. Copilot can report input, output, and cache usage by model, but the public CLI documentation does not define a stable JSON schema or prove whether categories overlap. Keep every reported category separate and do not use `audit_usage.py` until raw records prove repeated cumulative per-message snapshots and a terminal marker.

Do not derive monetary cost from AI credits, model names, transcript bytes, or token totals. Report recorded AI credits separately. A provider rate calculation is `derived` and needs the model, rate date, token-category mapping, and proof that the selected token categories do not overlap.

Call `end - start` the session span. Do not call it active runtime unless event timestamps identify active model or tool intervals. When those intervals are available, report their formula and state whether overlapping work was unioned or summed.

## Reconcile and report

For a closed batch run, reconcile `usage.json` with the final `/usage` display or independently reduced event records. For an interactive session, reconcile the final `/usage` display with an independent read-only query or reduction of its persisted events. If the two paths disagree, preserve both values, name the difference, and label the metric `estimate`.

Before reporting zero completed tools, failures, child sessions, or cache usage, test the extractor against a known positive event fixture or another session containing that event. Without the control, report `no hits observed`.

Report the Copilot CLI version and source path or command next to every headline metric. Include the session id, root and descendants, model and mode, boundary, status, update semantics, reconciliation result, and limits caused by undocumented storage or incomplete child linkage.
