# Codex CLI Adapter

Use this adapter for a Codex CLI rollout or a JSONL stream saved from `codex exec --json`. It was observed with Codex CLI 0.153.2 on Linux in September 2026. The local store and event schema are implementation details, so record `codex --version` and re-check the paths and fields below before treating a result as exact.

## Select and verify the source

Prefer one persisted rollout for the requested thread. With the default home, candidates are under `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl`, where `CODEX_HOME` defaults to `$HOME/.codex`. Do not derive the thread id from the filename: verify the `session_meta` record's `payload.session_id`, `payload.cwd`, `payload.cli_version`, model/provider, and timestamp against the requested run.

`codex agents` can help identify a currently connected agent, but it is not a historical usage export. For a new, controlled batch experiment, preserve stdout from `codex exec --json`; do not rerun a production task just to create an audit source.

The default local SQLite databases also contain a mutable index. If they exist, discover their names and schema read-only rather than assuming version suffixes such as `state_5.sqlite` or `thread_history_1.sqlite`:

```sh
sqlite3 -readonly "$CODEX_HOME"/state_*.sqlite '.schema threads'
sqlite3 -readonly "$CODEX_HOME"/thread_history_*.sqlite '.schema thread_turns'
```

In the observed schema, `threads` links a thread to its rollout path and has `tokens_used`; `thread_spawn_edges` links parent and child threads; and `thread_turns` records turn ids, status, timestamps, and rollout byte/ordinal boundaries. These are cross-check candidates only. Query them only after confirming the fields and semantics on the installed version.

## Inspect the rollout before reducing it

Sample an early, middle, and final record. The observed rollout has these distinct record families:

| Purpose | Observed record and fields | Safe interpretation |
| --- | --- | --- |
| identity | `session_meta.payload` | Thread metadata, not a terminal marker. |
| usage | `event_msg.payload.type == "token_count"` | `info.total_token_usage` is a cumulative session snapshot; `last_token_usage` is not a session total. |
| task boundary | `event_msg` `task_started` / `task_complete` | A completed task turn, not proof that the resumable thread cannot receive more work. |
| tools | `response_item.payload.type` `function_call`, `function_call_output`, `custom_tool_call`, or `custom_tool_call_output` | Attempt and completion records link by `call_id`; completion has no stable success field. |
| messages | `response_item.payload.type == "message"` | Count user turns only when `payload.role == "user"`. |

Preserve `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens`, and `total_tokens` under their recorded labels. Do not recompute `total_tokens` or add categories together: overlap is not established by their names.

## Measure and qualify

1. Confirm multiple `total_token_usage` snapshots are cumulative (the counters do not decrease) and choose the latest snapshot by record timestamp. The following is a discovery aid, not a substitute for the schema check:

   ```sh
   jq -s '
     [.[] | select(.type == "event_msg" and .payload.type == "token_count")
      | {timestamp, usage: .payload.info.total_token_usage}]
     | if length == 0 then error("no token_count record") else max_by(.timestamp) end
   ' <rollout.jsonl>
   ```

2. Report that value as a `snapshot` unless the source is closed and a second path reconciles it. A `task_complete` event closes a task turn; it does not prevent a later resume of the same thread. If verified, compare the recorded `total_tokens` with the local `threads.tokens_used` value and explain any difference. Lack of the SQLite index leaves the total an `estimate`, never an invented exact total.
3. Count `function_call` and `custom_tool_call` records as tool attempts. Join output records on `call_id` to identify missing completions. Do not infer success, errors, retries, command exit codes, or tool durations from output text; report them as unavailable unless the saved JSONL stream has an explicit, version-verified field.
4. Count user messages separately from tool attempts and response items. `task_complete.payload.duration_ms`, where present, is a recorded task-turn duration; do not call it total active session runtime.
5. Rebuild delegation only from verified `thread_spawn_edges` rows or an explicit parent/child identifier in saved records. A missing child rollout makes aggregate attribution incomplete.

Codex's OpenTelemetry export, when configured, is a separate observability source. It has documented API, stream, and tool counters and duration histograms; do not mix it with local-rollout counters without an explicit common run boundary.

## Report limits

State the Codex version, rollout path or saved stream, session id, cutoff, completed task-turn ids, whether the thread is resumable, and every SQLite query used. Report subscription usage or API billing as unavailable unless the source records cost or a provider-rate calculation has a verified model and category mapping. Do not expose `base_instructions`, message content, function arguments, tool output, or the rollout itself.
