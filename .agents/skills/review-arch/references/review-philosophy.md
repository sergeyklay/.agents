# Review Philosophy

## Contents

- Why the philosophy matters
- Principle 1 - Focus on decisions that matter
- Principle 2 - Evaluate tradeoffs, not "correctness"
- Principle 3 - Be direct and honest
- Principle 4 - Do not nitpick
- Principle 5 - Respect context and constraints
- Principle 6 - Distinguish risks from preferences
- Pre-write checklist

Six principles that separate a useful architecture review from an opinionated one. Read this file before writing the first review of a session, and once again before you press "save" on the final write-up.

Architecture is the set of decisions that are **expensive to reverse**. A review exists to help the author see risks and tradeoffs early, while they can still be changed cheaply. Every paragraph of the review should be measured against that purpose.

## Why the philosophy matters

An architecture review is written under time pressure by and for busy people. The author reads it on the way to their next meeting. If the review is wrong, they may skip the fix. If the review is right but sounds like nitpicking, they may skip the fix *and* discount the reviewer for the next round. If the review is right, sounds serious, and focuses on the decisions that matter, it shapes the system for years.

The six principles below are not style preferences. They are the difference between a review that changes the system and a review that is read, filed, and ignored.

## Principle 1 - Focus on decisions that matter

Architecture is defined by what is **expensive to reverse**. A decision about a shared database is architecture; a decision about variable naming is not. A decision about whether two capabilities live in the same service is architecture; a decision about which unit-testing library to use is not.

### How to apply

Before writing a finding, ask: *if this decision is wrong, what is the cost of changing it in six months?*

- If the cost is measured in **weeks or months** (service boundary, data ownership, storage engine, primary consistency model, auth model) - this is architecture. Flag it if it is wrong.
- If the cost is measured in **hours or days** (library choice, HTTP client, internal DTO shape, test framework) - this is not architecture. Do not flag it in an architecture review even if you disagree with it.

### Common failure mode

Spending the review on the cheap-to-reverse decisions because they are easier to see, and running out of attention for the expensive-to-reverse ones. The team ships with a shared database untouched because the review spent three pages on dependency-injection style.

## Principle 2 - Evaluate tradeoffs, not "correctness"

There is no single right architecture. Every decision trades one quality attribute for another. Your job is to make those tradeoffs explicit and assess whether they align with the stated goals.

### How to apply

For each significant decision, name:

- **What it favours** - which quality attribute improves.
- **What it sacrifices** - which quality attribute degrades.
- **Whether the tradeoff aligns with the priorities** - given what the team said mattered in Step 1 of the workflow, is this the right direction on the dial?

"Event-driven here trades a synchronous guarantee of order confirmation for the ability to process payment retries independently from order creation. The stated priority is availability over immediate consistency, so the tradeoff is correct. The risk is that the team has not named a strategy for idempotency, so retries can double-charge" is a tradeoff-shaped finding.

### Common failure mode

Flagging a decision as "wrong" because it does not match the pattern *you* would have used, without naming what the actual team priority would have to be for this choice to be correct. A review that reads "you should have done it differently" with no grounding in the team's stated priorities is advocacy, not evaluation.

## Principle 3 - Be direct and honest

Do not soften real risks with praise. Do not pad feedback with compliments. If the architecture is sound, say so briefly and move on. If there is a problem, name it clearly with the reasoning behind your concern.

### Acceptable

> "The order service has no idempotency strategy for event consumption. Under retry, duplicate charges are inevitable. Add a deduplication key keyed on external order ID before this ships to production."

### Not acceptable

> "There are many excellent decisions in this design! One small thing you might want to consider thinking about is whether there could perhaps be some potential concerns around idempotency, maybe, though I'm sure you've already thought about this..."

The hedged version wastes the author's time and buries the risk. The direct version can be read, understood, and acted on in ten seconds.

### How to apply

- State the risk first, then the reasoning, then the recommendation.
- Do not lead with praise as a social bumper. It trains the author to skim past it and may hide the signal.
- Do not end every finding with "let me know if this helps!" - the review is the help.

### Common failure mode

Writing the review in a tone calibrated to the author's feelings rather than the system's health. Kindness is fine; **false softness is its own risk**, because it lets the author discount findings that are actually critical.

## Principle 4 - Do not nitpick

If a choice is reasonable and the tradeoffs are acceptable for the context, acknowledge it and move on. Not everything needs a comment. A review that flags forty items teaches the author that nothing on the list is important.

### How to apply

Before adding a finding, ask three questions:

1. *If this decision is wrong, what does it cost?* If the answer is "nothing measurable" - cut the finding.
2. *Does the author already know this?* If the finding is a tutorial on a topic the team is clearly competent in, cut it.
3. *Is there already a finding in the review that covers the same root cause?* Consolidate.

### Common failure mode

A fifteen-finding review where three are genuine critical risks and twelve are observations about naming and file layout. The three risks get lost. A short review that names the three clearly is more useful than a long one that drowns them.

## Principle 5 - Respect context and constraints

A startup MVP and a regulated financial system have different architectural needs. Evaluate against the stated requirements and constraints, not against an idealised system.

### How to apply

- **Startup, pre-product-market-fit.** Time-to-market and learning velocity dominate. An over-engineered architecture is a bigger risk than a simple one. "The system has no horizontal scaling strategy" is not a risk at 100 requests/day; it is premature distribution if you force it.
- **Regulated industry (finance, healthcare, defence).** Auditability, data residency, and security boundaries dominate. "The audit log is buffered in memory before persistence" is a critical risk even if the business is small.
- **Internal tools for ten users.** Operability and cost-per-user dominate. Full multi-region HA is not a risk absent; it is an over-spec.

The **context** is not optional scaffolding. It is the rubric the review is graded against.

### Common failure mode

Applying Netflix-scale patterns to a 100-user internal tool and flagging their absence as a risk. Every recommendation that lifts a pattern from a fundamentally different context needs a one-sentence justification for why the pattern applies *here*.

## Principle 6 - Distinguish risks from preferences

Clearly separate **objective architectural risks** from **subjective preferences**. A risk is something the author needs to address; a preference is something they can evaluate and discard.

### Risks (examples)

- Single point of failure for a stated-high-availability system
- Missing failure-isolation strategy in a system with known cascading-failure risk
- Data consistency model that cannot support the stated integrity requirements
- Security boundary that the threat model does not justify

### Preferences (examples)

- Choice of message broker when several would work
- Naming convention for services
- Specific cloud provider when vendor requirements do not dictate it
- Whether to use gRPC vs. REST when both would satisfy the contract

If a finding is a preference, either cut it or mark it explicitly: "Observation (preference): the choice of RabbitMQ vs. Kafka here is a judgment call; both would meet the stated durability and throughput requirements. The team's existing operational familiarity with RabbitMQ is a reasonable tiebreaker."

### How to apply

Before writing a critical risk, ask: *would a different but equally competent architect disagree with this?* If yes, this is not a critical risk. Downgrade it to an observation or cut it.

### Common failure mode

Promoting a preference to a risk because the reviewer feels strongly about it. This is the single most common way architecture reviews lose credibility with the teams they review. Every mislabelled preference erodes the weight of genuine risks in later reviews.

## Pre-write checklist

Before saving the review, walk this checklist. Cut or rewrite anything that fails a check.

- [ ] Every Critical Risk and Significant Concern is anchored in a quality-attribute goal from Step 1 of the workflow, not in the reviewer's personal preference.
- [ ] No finding is a nit that could be resolved by rename, reformat, or small local refactor.
- [ ] No finding lifts a pattern from a different context (Netflix, FAANG, regulated finance) without explaining why it applies here.
- [ ] Every finding names the tradeoff it affects, not just the decision it criticises.
- [ ] The review is balanced: strengths are acknowledged briefly; critical risks are stated directly; observations are bounded.
- [ ] The review is short enough to read in under five minutes. If it is longer, three findings of substance are being drowned by ten that are not.
