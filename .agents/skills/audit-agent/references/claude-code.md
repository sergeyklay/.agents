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

## Rebuild delegation

Prefer explicit child metadata such as parent id, agent type, spawn depth, and spawning tool-call id. Reconcile child records with spawn tool calls in the parent. A missing transcript leaves the child's usage unknown; it does not prove the child never ran.

Keep root and child totals separate before summing them. Message ids are not assumed globally unique, so the source file remains part of every grouping key.
