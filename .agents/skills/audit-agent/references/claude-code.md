# Claude Code JSONL Adapter

Use this adapter only after the installed Claude Code version has been recorded and its current CLI or settings identify the session store. The paths and fields below came from an unversioned Linux observation in September 2026, so they are discovery candidates, not a supported schema or contract.

## Discover the current layout

Ask the CLI for diagnostic, export, or state paths first. If it exposes none, inspect files written inside the run window. One observed layout was:

| Role | Observed candidate |
|---|---|
| project store | `~/.claude/projects/<project-slug>/` |
| root transcript | `<session-id>.jsonl` |
| child transcripts | `<session-id>/subagents/*.jsonl` |
| child metadata | `*.meta.json` beside a child transcript |

Do not derive `<project-slug>` from the working directory. Verify candidates from a marker or record inside each file, and include only files linked to the requested root session.

## Verify the record model

One observed schema wrote several records for a single assistant message. These candidate roles must be confirmed from raw records:

| Role | Observed candidate |
|---|---|
| message key | `message.id` |
| usage object | `message.usage` |
| cache read | `cache_read_input_tokens` |
| cache write | `cache_creation_input_tokens` |
| input | `input_tokens` |
| output | `output_tokens` |
| terminal marker | `message.stop_reason` |

Run the bundled probe against every root and child transcript:

```sh
python3 scripts/audit_usage.py --probe <transcript.jsonl>
```

Use maximum-per-message aggregation only if all three observations hold on this run: records repeat one message id, counters are cumulative snapshots rather than deltas, and every per-field maximum equals the terminal record. Then run:

```sh
python3 scripts/audit_usage.py \
  --id-path message.id \
  --usage-path message.usage \
  --stop-path message.stop_reason \
  <root-and-child-jsonl-files>
```

The script exits `1` when terminal evidence is missing or disagrees. Without the script, group by `(file, message id)`, compare terminal values with per-field maxima, and sum only after they agree.

That comparison validates the reduction, not the counter. The terminal record is the per-field maximum by construction here, so the check cannot fail and passing it says nothing about whether the terminal record holds the message's true final value. Validate `output_tokens` separately, from its distribution against the content it accompanies:

```sh
python3 scripts/audit_claude_code.py --counters <transcript.jsonl>
```

A healthy transcript spreads `output_tokens` over many values that track message length. When a large share of messages carry a small value while their content holds `tool_use` blocks or long text, the transcript froze an early streaming snapshot and the terminal total never landed. Observed on one host across 40 child transcripts: 1086 of 1772 messages contained at least one `tool_use` block yet recorded `output_tokens` of 20 or fewer, which no message emitting a tool call can be. Treat that transcript's output tokens as a floor, label the figure `estimate`, and lean on the prompt-side counters, which are fixed at request time and unaffected.

Do not assume the repeated records are identical copies. On the same host `output_tokens` varied between records sharing one message id in 483 of 1772 groups, so the maximum is the correct reduction even though it does not rescue the counter.

## Rebuild delegation

Prefer explicit child metadata such as parent id, agent type, spawn depth, and spawning tool-call id. One observed layout wrote `subagents/<agent-id>.meta.json` beside each child transcript carrying `agentType`, `description`, `toolUseId`, `parentAgentId`, and `spawnDepth`. Join `toolUseId` to the spawning `tool_use` record in the parent to place the child in the tree, and read `parentAgentId` for the edge; a child with no `parentAgentId` hangs off the root session. Within one transcript `parentUuid`, `uuid`, and `isSidechain` chain records of a single session and do not cross session boundaries, so do not use them to link a parent to its children.

Separate delegation modes before summing. A child spawned through the agent tool carries the spawning `toolUseId`; a child forked from a slash command that declares `context: fork` does not. Their cost profiles and their completion semantics differ, so report the two populations separately rather than as one subagent total. Confirm the mapping from the command's own frontmatter rather than from the agent name alone.

A missing transcript leaves the child's usage unknown; it does not prove the child never ran. Keep root and child totals separate before summing them. Message ids are not assumed globally unique, so the source file remains part of every grouping key.

## Find command-driven runs

A command that declares `context: fork` leaves almost no trace in the root transcript: its `<command-name>` marker is written into the forked child, not the parent. Searching root transcripts for one is a near-total undercount. On one host, two such commands matched 3 root transcripts while 297 child `meta.json` files named the agents those commands bind to. Route command questions through the child metadata instead.

Two controls before reporting a zero here. Grep an ordinary non-forking command to prove the marker is logged at all. And anchor the match to a real record field, because a bare `<command-name>` substring search also matches the transcript's own echoed tool-schema text, which documents the marker without being an invocation.
