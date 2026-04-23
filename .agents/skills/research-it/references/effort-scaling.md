# Effort Scaling

## Contents

- The three tiers (Lookup / Mechanism / Investigation)
- Parallelism patterns
- Stop conditions, in detail
- Calibration examples
- A note on cost

How much investigation is the right amount? This file calibrates effort to question complexity, derived from Anthropic's published heuristics for their multi-agent research system and from the GAIA / BrowseComp benchmark literature.

The headline finding from Anthropic's analysis of BrowseComp (2025): **token usage by itself explains 80% of the variance** in research success. Investigation effort — not cleverness — is the dominant factor in answer quality. Within that, parallelism explains most of the rest. Calibrate accordingly.

## The three tiers

Pick the tier *before* searching. The tier controls scope, parallelism, and stop conditions.

### Tier 1 — Lookup

**Profile.** A single fact, value, or definition. The answer is a number, a name, a yes/no, or a short description. The user likely could find it themselves but is delegating the lookup.

**Examples.**

- "What is the default port for PostgreSQL?"
- "Who is the current maintainer of the `requests` library?"
- "What is the URL of the Go memory model specification?"

**Effort.**

- 3–10 tool calls
- Serial is fine — there is one thing to find
- One authoritative source is acceptable if the source is tier 1 (official docs, source code, the spec)
- Triangulation is *recommended* but not *required* for trivial facts

**Stop condition.** The fact is found in a tier-1 source. Stop.

**Failure mode.** Spending 30 tool calls on a tier-1 question. If this is happening, either the question is actually tier 2 (you under-classified) or you are searching the wrong source type.

### Tier 2 — Mechanism / Comparison

**Profile.** Explaining how something works, or comparing two things, or answering "why is X built this way". The answer is a paragraph or two of explanation grounded in evidence.

**Examples.**

- "How does Go's garbage collector decide when to run?"
- "Why does Postgres use MVCC instead of locking like MySQL InnoDB?"
- "What changed in the React 19 reconciliation algorithm?"

**Effort.**

- 10–15 tool calls
- **Parallel** where the next steps are independent (e.g. fetching the Postgres docs and the InnoDB docs in parallel)
- Decompose into 2–4 lines of inquiry, each followed independently, then synthesised
- Triangulation **required** for every implementation claim
- Read full content of authoritative sources, not just snippets

**Stop condition.** Each line of inquiry has reached either confirmation (triangulated answer) or a named dead end (no authoritative source found, which itself is a result).

**Failure mode 1.** Sequential when parallel was possible. This is the single biggest waste of effort in tier 2.

**Failure mode 2.** Stopping after one source. The first source frames the problem; the second source confirms or refutes the framing.

### Tier 3 — Investigation / Forensic

**Profile.** Open-ended investigation requiring decomposition into sub-questions, synthesis across many sources, and explicit uncertainty reporting. The answer may be a structured document.

**Examples.**

- "Why did project X switch from technology Y to technology Z in 2024?"
- "Verify whether claim X about library Y holds across its last five releases."
- "What does the academic literature say about the performance of approach A vs approach B for use case C?"
- "Reconstruct the design rationale for feature F based on the public record."

**Effort.**

- 15–30+ tool calls, occasionally more
- **Heavy parallelism** — every independent sub-question runs in parallel
- Decompose into ≥4 sub-questions before searching
- Each sub-question gets its own evidence chain and triangulation
- Synthesise only after the sub-questions have answers (not during)
- Conflicts and unknowns named explicitly in the output

**Stop condition.** Each sub-question has either a triangulated answer or a named dead end, AND the synthesis hangs together as a coherent answer to the original question, AND further investigation is producing diminishing returns (Anthropic reports a roughly logarithmic pass-rate curve against tool-call count — at some point each new call adds <1% to expected accuracy).

**Failure mode 1.** Skipping the decomposition step and searching as if it were tier 2. Tier-3 questions that are not decomposed produce sprawling, anchor-biased answers.

**Failure mode 2.** Synthesising too early. Writing the answer before all sub-questions are settled lets the early findings dictate the final shape.

## Parallelism patterns

From Anthropic's published findings, parallelism cuts research time by up to 90% on complex queries. Use it deliberately:

### What is independent

Two searches are independent if **the result of one does not change the query you would issue for the other**.

Independent → parallel:

- Fetching the docs of two different libraries in a comparison
- Searching for source code in two different repositories
- Reading two RFCs that govern different aspects of a protocol
- Querying for an issue in GitHub *and* fetching the docs that issue references

Dependent → serial:

- Step 1: find the latest version. Step 2: fetch the docs *for that version*.
- Step 1: identify the relevant RFC. Step 2: read it.
- Step 1: find which file implements feature X. Step 2: read that file.

### Parallelism budget

Anthropic's heuristic: 3–5 parallel sub-investigations per "spawn", with each sub-investigation issuing 3+ parallel tool calls. Beyond that, the synthesis cost dominates.

In a single-agent setting (no subagent spawning), this translates to: issue 3–5 independent searches per round, then synthesise the results before the next round.

## Stop conditions, in detail

### Hard stops

These end the investigation regardless of completeness:

- The triangulation rule is satisfied for every claim that will appear as fact in the output.
- The remaining unknowns are explicitly named in the output and the user has enough to decide whether to ask for more.

### Soft stops (consider stopping)

- Three consecutive tool calls have produced no new information (diminishing returns).
- The investigation has crossed 2× the upper bound of the tier's tool-call budget. Either the tier was misclassified or the question is genuinely unanswerable with available sources.
- A single authoritative source contradicts the working hypothesis. Stop the current line, reassess, then continue.

### Anti-stops (do not stop here)

- The first plausible answer appeared. **Verify.**
- The training-data answer "looks right". **Verify.**
- The user is waiting. The user is better served by a sound smaller answer than a fictional larger one.
- It feels like enough. Feelings are not stop conditions.

## Calibration examples

### "What is the default goroutine stack size in Go 1.22?"

- **Tier.** 1 (lookup).
- **Plan.** Search Go source for stack size constant; verify against Go release notes if anything looks ambiguous.
- **Tool calls.** 3–5.
- **Triangulation.** Source code is tier 1 and authoritative on its own for "what value does this version use".

### "How does Go's garbage collector decide when to run?"

- **Tier.** 2 (mechanism).
- **Plan.** Decompose into: (a) what triggers a GC cycle, (b) the pacer algorithm, (c) what tunables control it. Three parallel lines: fetch the GC design docs, find the pacer source, find the runtime package docs.
- **Tool calls.** 10–15.
- **Triangulation.** Each claim about pacer behaviour confirmed by source
  + design doc.

### "Reconstruct why React 19 changed its reconciliation behaviour and what the alternatives were."

- **Tier.** 3 (investigation).
- **Plan.** Decompose into: (a) what changed exactly, (b) what motivated the change, (c) what alternatives were considered, (d) what the community reaction was. Each is its own evidence chain. Parallel searches against React's RFC repo, the React team's blog posts, the React 19 release notes, and curated community discussion.
- **Tool calls.** 20–40.
- **Triangulation.** Heavy. Multiple sources for each sub-question. The output names what could not be confirmed (e.g. "no public statement from the React team explained why approach X was rejected").

## A note on cost

Multi-step investigation burns tokens. Anthropic reports research agents using ~4× the tokens of chat interactions, and multi-agent systems ~15×. This is the cost of doing the job properly.

The trade is real but well understood: **for tasks where the value of correctness is high, the token cost is worth it**. For tasks where any plausible answer suffices, this skill is the wrong tool — those tasks should not be invoking deep research at all.
