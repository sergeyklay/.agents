# Generic Log Adapter

Use this route only when no tested vendor adapter matches the runner. Discover the source and update semantics before choosing arithmetic.

## Source priority

Prefer, in order: a runner-native export or stats command, a documented local database/API, structured event logs, then a plain transcript. Ask `--help`, diagnostic commands, and environment/configuration before searching the home directory.

Record the runner version, source paths or query, run window, and whether the source is still being written. If no machine-readable usage survives, report only directly observable values such as recorded timestamps and tool events. Never estimate tokens from bytes, words, or a model's context limit.

## Probe the schema

For JSON arrays or JSONL streams, sample records from the root and at least one child or later turn. Normalize a nested single-document export before using the bundled stream script. Locate candidate run id, parent id, message/step id, role, usage object, terminal marker, timestamps, tool name/input/status, and error fields. Confirm every path against raw records; a name such as `input_tokens` does not establish whether cache tokens overlap it.

The bundled probe can rank string identifiers, numeric usage objects, and sparse terminal fields:

```sh
python3 scripts/audit_usage.py --probe <log-files>
```

It proposes candidates only. If the script is unavailable, inspect representative early, middle, and terminal records and list the same candidate roles manually.

## Choose the reduction

Classify each counter from observed records:

| Update shape | Correct reduction |
|---|---|
| delta on each event or model step | sum every event once |
| cumulative snapshot for a message/session | take the terminal value |
| repeated final total on several records | count once per proven key |
| unknown or mixed | do not publish an exact total |

For cumulative per-message streams, use `(source file, message id)` as the key unless the vendor documents wider id uniqueness. Run the aggregator only after terminal values equal per-field maxima on sampled messages:

```sh
python3 scripts/audit_usage.py \
  --id-path <message-id-path> \
  --usage-path <usage-object-path> \
  --stop-path <terminal-marker-path> \
  <log-files>
```

Without `--stop-value`, every pre-terminal marker must be null or absent and the final usage record must carry one nonempty string. For boolean, numeric, or status markers, pass an exact JSON literal, for example `--stop-value true` or `--stop-value '"completed"'`. The marker must occur exactly once and on the final usage record.

If the usage object also carries metadata or nested counters, repeat `--usage-field <relative.path>` for every numeric field to include. The script rejects unselected nonnumeric members rather than silently dropping them.

The script exits `1` when any group lacks valid terminal evidence or a maximum disagrees. For delta or session-level records, do not use this script; sum or select terminal records according to the observed shape.

## Rebuild the run tree

Join root and child records on explicit session/parent/spawn ids. If only timestamps exist, attribution is inferred and remains an estimate. Reconcile observed children with parent spawn events, but treat missing child evidence as unknown rather than as proof of non-execution.

Include the source in a deduplication key when ids may be replayed, imported, resumed, or copied. Never sum a summary row together with the detail rows it summarizes.

## Validate

Cross-check detail totals against a separately persisted summary or native stats command. If no second path exists, report the formula and label the result an estimate. Exercise every zero-producing extractor on a known positive fixture before claiming no errors, retries, children, or cache writes occurred.
