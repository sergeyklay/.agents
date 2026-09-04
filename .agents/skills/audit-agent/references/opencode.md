# OpenCode Adapter

Use this route when the installed CLI provides `opencode db`. The adapter is gated to OpenCode 1.18.x; it was observed with CLI 1.18.27 and records written by 1.18.26. Every run still checks installed and recorded versions plus the schema because the SQLite tables are implementation details exposed through a public CLI.

## Preferred workflow

1. Record the version and identify the root session:

```sh
opencode --version
opencode session list --format json -n 20
```

Verify the chosen id against its `directory` and time window. Do not select by title or recency alone.

2. Run the read-only auditor from this skill directory:

```sh
python3 scripts/audit_opencode.py <root-session-id>
```

The script asks `opencode db path` for the database, opens one read transaction, walks `session.parent_id`, sums root and descendant session counters, counts message/step/tool records, reconciles every session total against its `step-finish` parts, and matches task-tool `metadata.sessionId` values to child rows. It emits no prompts, tool inputs, or tool outputs.

Default output contains totals, session ids, and failed validations only. Add `--sessions` for per-session usage; add `--details` only for schema columns and per-session tool breakdowns. Large trees otherwise spend context on repeated diagnostics.

Exit codes: `0` means versions, usage totals, and spawn links all reconciled; `1` means a version is unsupported or detail, child-session, or terminal evidence was incomplete or disagreed; `2` means the session, database, or expected schema was unavailable. Fix or explain every nonzero result before quoting an exact figure.

Before reporting zero child sessions, cache writes, or tool errors, run the bundled positive-control fixture:

```sh
python3 scripts/test_audit_scripts.py -v
```

It exercises the same auditor against one linked child session, nonzero cache writes, and one tool error; it also proves the stream parser rejects missing terminal evidence. If this control fails, do not report the target's zero.

Fallback when Python or the script is unavailable: inspect the schema, then query the tree through the CLI:

```sh
opencode db "PRAGMA table_info(session)" --format json
opencode db "PRAGMA table_info(message)" --format json
opencode db "PRAGMA table_info(part)" --format json

opencode db "WITH RECURSIVE run(id, depth) AS (
  SELECT id, 0 FROM session WHERE id = '<root-session-id>'
  UNION ALL
  SELECT s.id, run.depth + 1 FROM session s JOIN run ON s.parent_id = run.id
) SELECT run.depth, s.id, s.parent_id, s.agent, s.model,
  s.tokens_input, s.tokens_output, s.tokens_reasoning,
  s.tokens_cache_read, s.tokens_cache_write, s.cost,
  s.time_created, s.time_updated
FROM run JOIN session s ON s.id = run.id
ORDER BY run.depth, s.time_created" --format json
```

Sum the five token columns and `cost` across returned sessions. Separately sum `tokens.input`, `tokens.output`, `tokens.reasoning`, `tokens.cache.read`, `tokens.cache.write`, and `cost` from each session's `part.data` where `type` is `step-finish`; exact equality, with normal floating-point tolerance for cost, is the reconciliation gate.

Also inspect completed `tool` parts named `task`. Match each `state.metadata.sessionId` to a returned child row and require that row's `parent_id` to equal `state.metadata.parentSessionId`. A completed task without a session id, a referenced child without a row, or a nonterminal task status makes tree completeness unknown.

## OpenCode semantics

- Session counters are already sums of terminal `step-finish` records in the verified schema. Do not apply the Claude-style per-message maximum reduction.
- A delegated task is another `session` row linked by `parent_id`. A root-only query excludes its cost.
- Completed task-tool metadata names the spawned session. Reconcile those ids with the parent tree; usage agreement over only the rows that remain cannot detect a deleted child by itself.
- `message` rows distinguish user and assistant messages. `step-finish` parts count model steps. `tool` parts count tool calls; `state.status = 'error'` identifies recorded failures.
- `time_updated - time_created` is the session span and can include user idle time. It is not active runtime.
- `cost` is the runner's recorded numeric value; the session schema does not identify a currency. Do not add a currency label without a separate provider source.
- A TUI session is resumable and has no permanent completed marker. Report a cutoff snapshot unless the requested boundary is externally fixed. For `opencode run`, process exit can close the invocation boundary.

## Native exports and cross-checks

`opencode export <session-id>` is useful as a portable snapshot, but validate the result with `jq empty` before using it; a truncated export is not evidence. Add `--sanitize` before sharing it. Do not assume one export contains descendant sessions or parent links: reconcile exported ids against the database tree.

`opencode stats` aggregates broader project/time windows. Use it only as a coarse cross-check when the window contains exactly the sessions under audit; otherwise it is not a per-run denominator.

After any OpenCode minor-version upgrade, rerun the schema checks and known-session reconciliation before extending the script's supported-version gate.
