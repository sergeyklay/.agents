# Gemini CLI JSONL Adapter

Use this adapter after the installed Gemini CLI version has been recorded and its logs directory is identified.

## Discover the current layout

Check the default log locations or ask the CLI. Observed layouts include:

| Role | Observed candidate |
|---|---|
| session logs | `~/.gemini/tmp/agents/chats/session-*.jsonl` |
| log index | `~/.gemini/tmp/agents/logs.json` |

Verify candidates from a marker or record inside each file, and include only files linked to the requested session ID. Use `gemini --list-sessions` to see available sessions for the project.

## Verify the record model

Gemini CLI logs JSONL events. Some events are root objects containing message details, and some are state patches (e.g., `{"$set": {"messages": [...]}}`).

| Role | Observed candidate |
|---|---|
| message key | `id` |
| usage object | `tokens` |
| input | `input` |
| output | `output` |
| cached | `cached` |

Because Gemini CLI logs contain nested state updates alongside root events, use `jq` to flatten and extract the token usage records before aggregation.

Example to extract usage per message ID:

```sh
jq -c '
  (if ."$set" and ."$set".messages then ."$set".messages[] else . end)
  | select(.id and .tokens)
  | {id: .id, usage: .tokens, model: .model}
' <transcript.jsonl>
```

You can pipe the flattened records directly into `audit_usage.py` to aggregate the maximum cumulative values:

```sh
jq -c '(if ."$set" and ."$set".messages then ."$set".messages[] else . end) | select(.id)' <transcript.jsonl> | \
  python3 scripts/audit_usage.py \
    --id-path id \
    --usage-path tokens \
    -
```

The script will exit `1` and label the result unverified (`estimate`) because Gemini currently provides no explicit terminal marker like `stop_reason`.

## Rebuild delegation

If the session contains sub-agent calls, examine the `toolCalls` and `result` payloads inside the `gemini` message events. Look for `invoke_agent` or similar tool calls that spawn new sessions. Be aware that the `sessionId` may be used to correlate parent and child runs. Reconcile tool execution results with child transcripts where available.
