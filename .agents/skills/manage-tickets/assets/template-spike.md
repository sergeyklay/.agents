# Spike Template

Use when the issue is a time-boxed investigation: research, prototype, comparison, or feasibility study whose deliverable is a decision or evidence, not shipped functionality. Load in Workflow Step 4 (Draft per type) when the classified type is `Spike`. Compose body content in Jira wiki markup per `jira-syntax`.

## Template

Copy verbatim. Fill required sections. Drop bracketed `[…]` sections when they do not apply. Cite existing code or prior investigations by `file:line` where relevant.

```
h2. Summary

{One paragraph stating the single decision this spike unblocks and why it cannot be answered without investigation.}

h2. Background

{What blocks on the answer. Why we cannot decide from existing evidence. Prior attempts, if any (cite tickets or branches). Stakes if we guess wrong.}

h2. Timebox

{Wall-clock budget, e.g. "2 days", "1 week", with start and end dates. A spike that exceeds its timebox stops and produces an interim report; it does not silently extend.}

h2. Deliverable

{The concrete artefact produced: an ADR, a prototype branch, a comparison table, a benchmark report, a recommendation document. State where the artefact will live (path or URL).}

h2. Requirements

* {The Deliverable MUST exist and be reviewable}
* {The decision or recommendation MUST be documented and unblock the downstream work named in Background}
* {Findings MUST be reproducible - data, methodology, and assumptions written down}
* {The spike MUST stop on or before the Timebox end date, with an interim report if needed}

h2. [Out of scope]

{Optional - include to bound the investigation.}

* {Adjacent question deferred to a separate Spike}
* {Implementation work the Deliverable is NOT}

h2. [Self-checks]

h3. Automated (CI)

* {Benchmark or comparison script the Deliverable runs; output committed alongside the ADR}

h3. Manual

* {Reviewer walks through the Deliverable and can answer the Background question without re-investigating}

h2. Context

{Issues blocked on this spike. Prior investigations or rejected approaches. Relevant external resources. Owner.}
```

## Filled example

```
h2. Summary

Choose between Kafka, NATS JetStream, and AWS SQS for the event-bus replacement, ahead of the Q3 migration kickoff.

h2. Background

The current RabbitMQ cluster has hit its operational ceiling - repeated outages on the dead-letter queue under spikes ({{services/events/dlq.ts:88-110}} retry path), and the upstream community no longer ships security patches for our pinned 3.8.x version. Three candidates surfaced in initial discovery ([PROJ-1880] from 2025-05); choosing among them affects schema design, ops on-call rotation, and a six-figure cloud commitment.

h2. Timebox

2 weeks: 2026-06-01 through 2026-06-12.

h2. Deliverable

ADR at {{docs/decisions/0042-event-bus-choice.md}} proposing one candidate, with a comparison table on these dimensions: throughput at our 95th percentile, message-ordering guarantees, ops cost at projected volume, multi-region replication, and team familiarity. Benchmark scripts and raw results checked into {{docs/decisions/0042-event-bus-choice/}}.

h2. Requirements

* The ADR MUST be drafted, reviewed by the platform team, and merged into {{docs/decisions/}}.
* Benchmark scripts and raw results MUST be checked into the ADR sub-folder for reproducibility.
* The team's Q3 planning agenda MUST carry a one-paragraph summary of the recommendation.
* The spike MUST stop on or before 2026-06-12 with an interim report if the comparison is incomplete.

h2. Out of scope

* Migration plan from RabbitMQ to the chosen candidate (separate Story [PROJ-2003]).
* Schema design for the new bus (separate Story [PROJ-2002], blocked on this spike).
* Cost negotiation with the cloud vendor.

h2. Self-checks

h3. Automated (CI)

* Benchmark scripts in {{docs/decisions/0042-event-bus-choice/bench/}} run reproducibly via {{make bench}}; results committed.

h3. Manual

* Platform-team reviewer reads the ADR and can answer "which candidate, why" without rerunning the benchmarks.

h2. Context

Blocks: [PROJ-2002] (event schema design), [PROJ-2003] (consumer migration plan). Prior: [PROJ-1880] surveyed candidates 12 months ago; reopen for current pricing and ops experience. Owner: @platform-lead.
```
