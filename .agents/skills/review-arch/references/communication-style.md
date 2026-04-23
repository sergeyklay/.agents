# Communication Style

## Contents

- Audience and voice
- Precision - say what you mean
- Hedging - the thin and the thick
- Banned phrases
- The domain-vocabulary rule
- Basics - when to explain, when to skip
- Recommending alternatives
- Depth calibration
- The anti-lecture rule
- Calibration checklist

The full voice and tone guide for architecture reviews. Read this file when the draft review feels off and you cannot name why - drifting into linting, coaching, salesmanship, or the kind of padded caution that hides the signal. Most of the failure modes this file prevents are not deficiencies of knowledge; they are deficiencies of **tone calibration**.

An architecture review is read under time pressure by a busy author. The review either lands within the first two paragraphs or it doesn't. Every sentence in the review competes for the reader's attention; every sentence that carries no information loses that competition.

## Audience and voice

The audience is **a senior engineer or architect** who owns the system under review. They are not a student. They are not a stakeholder who needs to be managed. They are a peer who has, for whatever reason, not yet seen the specific risk you are about to name.

The voice is **principal-to-principal**. Direct. Informed. Willing to disagree. Not combative. Not performative. The tone of a colleague who takes the system seriously enough to tell the author the truth.

Everything in this file is an instance of that one calibration.

## Precision - say what you mean

Call things by their actual names. When introducing a new term in a review, define it the first time it appears, then reuse it consistently. Do not paraphrase a defined term later. "Write-ahead log" stays "write-ahead log"; it does not become "the logging thing" three paragraphs later.

Vague language gives the reader false confidence that they understood something they did not. An architectural finding that is ambiguous is worse than no finding at all, because the reader files it as "reviewed" and the risk remains.

### Examples

| Vague | Precise |
|---|---|
| "This might cause problems under load" | "This produces O(n²) behaviour against the stated 10k orders/sec target, so p99 latency degrades past the 200ms SLO at roughly 4k orders/sec." |
| "The coupling here is kind of high" | "Services A, B, and C must be deployed together because they share a schema migration surface; this is the distributed-monolith anti-pattern." |
| "Security could be better" | "The session-token validation is done inside the service rather than at the edge; this places the trust boundary in the wrong layer and means every new service re-implements validation." |
| "There seems to be some concerns around availability" | "The order service is a single region, stateful, and sits in the critical path for checkout. A regional failure takes checkout down. Given the stated availability priority, this is a critical risk." |

Precision is not verbosity. The precise versions above are not longer than the vague versions; they are **different**. The work is substituting named mechanisms for hand-waving adjectives.

## Hedging - the thin and the thick

A review is allowed to hedge when the uncertainty is **real** and **relevant**. It is not allowed to hedge to soften findings.

### Acceptable (thin) hedging

Naming genuine uncertainty about the fact:

- "Given the scenarios provided, this is a risk. If the team has a different threat model in mind, I would want to see it."
- "The load figures are not declared, so this analysis assumes the 10k/sec figure from the RFC. If actual traffic is an order of magnitude higher, the conclusion changes."

These hedges carry information. The reader learns what the finding depends on.

### Unacceptable (thick) hedging

Softening the finding itself:

- "You might want to maybe consider possibly thinking about…"
- "I'm not sure if this is a problem, but…"
- "This could perhaps potentially be a concern…"

These hedges are **social cushioning**, not epistemic hedging. They train the reader to skim past findings. Worse, they train the reader to discount the reviewer, because a reviewer who buries real concerns in fluff is signalling that even they don't believe in the concern.

### The rule

If you believe the thing is a risk, say so. If you believe it is an observation, say so. If you are not sure, name what you are not sure about - not the whole finding.

## Banned phrases

These signal padding, performative modesty, or coaching voice. Cut them on sight.

- "Great question!" (Not a question. And the patronising open is its own signal.)
- "I think", "I believe", "I feel" — in a review, the text is already the reviewer's opinion. The hedge adds nothing and weakens the signal.
- "It's easy to…" / "Simply…" / "Just…" — the word "just" is the single most common review tell. Search every draft for it. Each occurrence hides a skipped explanation or a value judgment about how hard something should feel.
- "Of course…" / "Obviously…" / "As everyone knows…" — if the author knew it, you would not be writing this review.
- "You might want to consider thinking about whether it could perhaps…" — the Noun Pile of Hedging. Cut.
- "It would be nice if…" — this is a preference, not a finding. Either the nice-to-have is a real concern (restate as a finding) or it is not (cut).
- "Perhaps you could…" — either recommend or don't; the softening helps nothing.
- "I'm not an expert in X, but…" — if you are not qualified to evaluate X, either become qualified enough or omit the section. The disclaimer does not immunise the review from being wrong.
- "Just my two cents" — weakens everything that follows.

### What replaces them

Nothing. The sentence after "I think it's possible that X is Y" is usually fine as "X is Y". The hedging was never load-bearing; it was just friction.

## The domain-vocabulary rule

Use the vocabulary of the domain. Reference specific architectural patterns, quality attributes, and failure modes by name.

This is **not** jargon for its own sake. It is compression. When you say "this is a sensitivity point for availability under a single-region-loss scenario", you have condensed two sentences of explanation into one named concept - and if the author does not know what "sensitivity point" means, they can look it up once and have the vocabulary for every subsequent review.

When you say "this feels like it could be a problem", you have condensed nothing and named nothing.

### Load vocabulary from the references

The ATAM vocabulary (sensitivity point, tradeoff point, risk, non-risk, utility tree, scenarios) and the ISO/IEC 25010:2023 quality-attribute names are in [quality-attributes.md](quality-attributes.md). The anti-pattern names are in [anti-patterns.md](anti-patterns.md). Use them where they apply, not as decoration.

## Basics - when to explain, when to skip

Do not lecture on basics. If the team chose Kafka, do not explain what Kafka is. Evaluate whether the choice is appropriate here.

### When explanation is warranted

- A term is unfamiliar because it is **recent** or **niche** and you need the reader to follow the finding. One sentence of definition is acceptable.
- A term has a specific **disputed meaning** in this context and you need to pin down which one you are using. Name the meaning briefly.
- You are citing a **methodology** (ATAM, a specific anti-pattern) and the name alone does not convey what you are claiming. A one-sentence link to the named mechanism is acceptable.

### When explanation is noise

- The team chose a popular database, framework, or broker and you write a paragraph describing it. Cut.
- The section titled "What is a message queue?" before the finding about message-queue usage. Cut.
- Long preambles about "in modern software architecture…" before the actual finding. Cut.

Every paragraph the reader spends on context they already have is a paragraph they do not spend on the finding you actually need them to see.

## Recommending alternatives

When recommending an alternative, explain the **tradeoff**, not just the alternative. "Use X instead of Y" is incomplete; "Use X instead of Y, because it trades [quality attribute A] for [quality attribute B], which aligns with the stated priority of [attribute B]" is a recommendation.

### Strong recommendation (cite the tradeoff)

> Consider async events here instead of synchronous calls. This decouples the services at the cost of eventual consistency, which is acceptable for this use case because order confirmation does not need to be synchronous from the user's perspective. Implementation: publish `OrderCreated` from the order service via the transactional outbox, and move inventory reservation, fraud check, and notification onto independent consumers. This removes the four-hop synchronous chain and the cascading-failure risk it creates.

### Weak recommendation (no tradeoff named)

> Use events instead of synchronous calls.

The weak version gives the reader nothing to argue with or accept. The strong version names the direction of the tradeoff, the priority it aligns with, and a starting concrete shape. Arguments against the recommendation can now be specific ("actually order confirmation *is* synchronous from the user's perspective because we show inventory on the confirmation screen") rather than vague ("we prefer our current approach").

### Do not recommend an alternative without naming

- Which quality attribute the alternative improves
- Which quality attribute the alternative degrades (all recommendations trade)
- Why the trade points in the right direction for the stated priorities

Three lines is enough. One line is not.

## Depth calibration

Adapt depth to the review's scope. A high-level review of system decomposition does not need code-level analysis. A detailed review of a specific component does not need to re-evaluate the entire system.

| Review scope | Right depth |
|---|---|
| Pre-implementation RFC (1-3 pages) | Focus on Dimensions 1 and 5 (alignment, gaps). One to three critical risks at most. |
| Full system architecture | All five dimensions. Five to eight findings total, sorted by severity. |
| Single-component design | Dimensions 2 and 3 (tradeoffs, structure). Deep; every finding cites specific code or spec sections. |
| Post-incident architecture audit | Heavy on Dimensions 3 and 4; the incident itself often tells you where to look. |
| Conversational "is this a good idea?" | One or two findings, one or two sentences each. No preamble. |

**Wrong depth is itself a review defect.** A ten-finding review on a single-paragraph design question wastes the reader's time. A surface-level scan on a full system architecture misses the load-bearing findings. The first sentence of the review should implicitly commit to a depth; the rest of the review should deliver it.

## The anti-lecture rule

The review is not a course. The author knows their system better than the reviewer does. The review's role is to add **one thing the author did not see**, per finding. Everything that is not that one thing is noise.

### Tell-tales that the review is lecturing

- Multiple paragraphs of "background" before the first finding.
- Findings that start with "let me explain what happens when…"
- "You should know that…" followed by domain knowledge the author certainly already has.
- Repetition: a finding is stated, then restated, then restated.
- Meta-discussion: several sentences about *the shape* of the review instead of the review's content.

### The replacement

State the finding, cite the evidence, state the recommendation, move on. If the finding needs supporting context, give it in one sentence. If the author needs a longer explanation to act on the finding, the link to the reference file is enough; the review does not need to teach.

## Calibration checklist

Walk this before saving the review. Cut or rewrite anything that fails.

- [ ] Every finding cites specific evidence: a file path, a line range, a named decision, or a quoted requirement. No finding is a vibe.
- [ ] Every finding uses a named quality attribute (ISO/IEC 25010:2023) or a named anti-pattern, where one applies. If the finding cannot be named in domain vocabulary, it may not be a real finding.
- [ ] The review contains no instance of "just", "simply", "obviously", "of course", "easy", "straightforward", "perhaps you might want to consider possibly" - or each instance has been reviewed and justified.
- [ ] No finding starts with praise as a social bumper.
- [ ] No recommendation says "use X instead" without naming the tradeoff.
- [ ] No paragraph is lecturing the author on a topic they clearly know.
- [ ] The depth matches the scope: not too shallow for a full review, not too deep for a conversational one.
- [ ] The review can be read and understood in under five minutes. If not, three findings of substance are drowning in ten that are not.
- [ ] If the architecture is sound, the review says so **briefly** and stops. A short review of sound work is more valuable than a long review searching for problems that are not there.
