# Optional Run Analysis

Apply only the analyses requested. Raw usage and behavior counts remain primary; derived efficiency and workflow metrics are descriptive, not universal quality scores.

## Compare runs

Compare runs only when they share the task input, starting repository revision and dirty state, runner version, tool permissions, available skills/instructions, model/provider/variant, and completion criterion. Record every difference that remains.

Establish that sameness by hashing rather than by inspection. Hash each run's prompt and require equality, then hash every tool result in order and diff the sequences. Equal prompts are not equal inputs: tool results come from a filesystem, a clock and a network that no run controls, so runs given byte-identical prompts routinely observe different listings, file contents and command output.

Classify each remaining difference instead of only recording it. The systematic variable is the one thing under test and must be present in exactly one configuration. A nonce differs by construction every run, such as a session id, a timestamp or a per-run state root; name its generator, then discard it. An inert difference is one the run cannot read, and that rests on the read path rather than on the file's name. Nonce and inert differences separate no configurations and do not belong in the reported difference list.

One run per configuration is a case study. For a performance claim, repeat each configuration under isolated but equivalent state, report the individual observations and spread, and use paired comparisons when runs share test cases. Do not hide heavy tails behind a mean alone.

Normalize only after reporting raw values. Useful denominators include completed task, accepted artifact, model step, or user turn. A ratio cannot repair non-comparable inputs.

## Duplicated reads

Extract completed read-like tool calls with agent/session, path, range or query, timestamp, and returned bytes when recorded. A path touched by two phases is not automatically duplicate context: exclude reads after intervening writes and calls that request disjoint ranges or queries.

Count actual returned bytes when the record provides them. Whole-file size is only an upper bound for sliced reads, and file paths alone are a lower bound when searches or shell commands also read content. Label either bound.

## Failures, retries, and strategy changes

Count explicit tool error states directly. An exact retry is the same normalized tool name and input repeated after a failure or without an intervening state change. Near-duplicate inputs, repeated edits, and switches between tool families require judgment; report them as heuristic candidates with examples, not as exact counts of agent intent.

For `zero failures` or `zero retries`, run the same extractor against a known error/retry fixture first. A query that has never returned a hit cannot establish absence.

## Artifact yield

Define the durable artifact from version-control changes attributable to the run. Exclude pre-existing dirty changes, generated caches, transcripts, scratch files, and files later deleted. Report additions/deletions or bytes together with the exact diff boundary.

Ratios such as artifact bytes per output token or cost per accepted change are descriptive only. Tokenizers, tool protocols, generated formats, reasoning policies, and discarded work change the ratio; there is no portable plausible band. Use it to compare controlled repetitions of the same task, never to infer missing token counts or rank unrelated tasks.

## Mechanism claims

For a claim that a cache, guard, retry policy, or delegation fired, name the record only that mechanism could produce: a cache-write counter, rejection event, delayed retry, or child session linked to a spawn. If no distinguishable record exists, classify the mechanism as untestable from this run rather than present or absent.

Check what a counter measures before reading its magnitude as a quantity. A per-run `cache_creation` total measures re-caching, not the length of text added to the input; it can land within a few tokens of that length while the first-request delta is a single token and per-run totals do not sort by configuration at all. A figure with the right sign and the wrong construct is worse than no figure, because it reads as confirmation. Settle a size claim from a paired per-request delta under known cache state, or from the artifact on disk, and name which.
