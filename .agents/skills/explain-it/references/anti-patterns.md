# Anti-Patterns in Technical Explanation

## Contents

1. The Textbook Dump
2. The Expert Blind Spot
3. The Allegory Cascade
4. The Confidence Bluff
5. The Jargon Wall
6. The Kindergarten Trap
7. The Scope Creep
8. The Unverified Survey
9. The Hollow Opener
10. The Cold Start
11. Maxims and the cross-cutting principle

Ten failure modes that show up repeatedly in technical writing. Each one includes a symptom, an example of the broken form, and the structural fix.

If you catch yourself doing any of these, stop writing and restructure. They are not stylistic preferences - they are predictable ways an explanation fails to land.

## 1. The Textbook Dump

**Symptom.** Definition → History → Features → Comparison, in mechanical encyclopaedia order. The structure mirrors a Wikipedia article rather than the reader's path of understanding.

**Broken form**

> Kafka is a distributed event streaming platform developed at LinkedIn in
> 2011 and later open-sourced under the Apache Software Foundation. Its
> features include high throughput, fault tolerance, horizontal scalability,
> and integration with the Confluent ecosystem. Compared to RabbitMQ, Kafka
> uses a log-based storage model rather than a queue-based one…

The reader has not yet been told *what problem any of this solves*.

**Fix.** Open with the **why**. What problem motivated the thing? What is the first concrete situation where someone would reach for it? History, features, and comparisons can appear later, but only after the reader has a working mental model of why the thing exists.

> When you have one service producing events and many services that need
> to consume them - possibly at different rates, possibly hours later, possibly
> after a restart - you need somewhere durable to put the events that lets
> consumers read at their own pace. Kafka is that "somewhere durable".

## 2. The Expert Blind Spot

**Symptom.** "And then it does Y, which naturally follows from X." *Does* it follow naturally? Did you verify the inferential gap is actually small to someone seeing this for the first time?

This is the most common way explanations fail technically fluent readers. Skipping intermediate steps because they are automatic for you leaves the reader with an unbridged gap and no way to ask about it.

**Broken form**

> The garbage collector marks live objects from the roots, then the sweeper
> reclaims unmarked memory. Naturally, this means write barriers must be
> active during marking.

That "naturally" is doing enormous work. The reader who does not already know why mark-sweep needs write barriers will silently get lost here.

**Fix.** Surface the bridge explicitly.

> While the marker is walking the heap, the program keeps running and may
> rewrite pointers - for example, an old object can suddenly start pointing
> to a brand-new object the marker has not visited yet. If the marker
> finishes its walk without knowing about that new pointer, it will treat
> the new object as garbage and free memory the program is still using.
> A **write barrier** is a small piece of code the runtime injects at every
> pointer write that records "the marker needs to revisit this". That is
> why mark-sweep collectors need write barriers active during the marking
> phase.

## 3. The Allegory Cascade

**Symptom.** Three (or more) metaphors stacked in sequence. Each one dilutes the previous. The reader stops tracking the actual subject and starts tracking the metaphors.

**Broken form**

> Think of goroutines like factory workers, channels like conveyor belts,
> the scheduler like a floor manager, and the runtime like a foreman who
> reports to the OS, which is like the head office…

By sentence three the reader is no longer thinking about Go. They are imagining a factory.

**Fix.** One bounded analogy maximum, then return to direct explanation. See `communication-calibration.md` for the bounded-analogy pattern.

## 4. The Confidence Bluff

**Symptom.** Stating implementation details, version numbers, behaviours, or performance characteristics that you have not actually verified. Often the giveaway is a casually specific number ("about 30% faster", "around 256 megabytes") with no source.

**Broken form**

> Internally, V8 inlines functions smaller than about 600 bytes and uses a
> tiered compilation pipeline that promotes hot functions after roughly 1000
> invocations.

If those numbers came from training data and were not verified against current V8 source, you have just inserted plausible-sounding fiction into the reader's mental model.

**Fix.** Either verify and cite, or remove the claim, or mark it as unverified.

> V8 uses a tiered compilation pipeline (Ignition → Sparkplug → Maglev →
> TurboFan in modern versions) that promotes functions to higher tiers based
> on how often they run; the exact thresholds change between releases and
> are tuned via internal heuristics. For current values, read
> `src/flags/flag-definitions.h` in the V8 source.

False confidence corrupts mental models in ways that are hard to undo later. The reader builds further understanding on top of the false claim, and unwinding it requires rebuilding the rest.

## 5. The Jargon Wall

**Symptom.** A sentence that combines several unexplained domain terms in a single grammatical structure, on the assumption that defining each one would slow things down.

**Broken form**

> The event loop processes microtasks from the task queue after macrotask
> completion via the structured clone algorithm using transferable objects.

This teaches nothing. The reader either already knows all four terms (in which case the sentence is redundant) or knows none of them (in which case the sentence is opaque).

**Fix.** Unpack terms before combining them. Introduce one at a time, each with a one-sentence definition, in dependency order. See `communication-calibration.md` for the full vocabulary-pacing rules.

## 6. The Kindergarten Trap

**Symptom.** Patronising the reader with simplifying analogies pitched several technical levels too low.

**Broken form**

> A database is basically a really big filing cabinet! Each row is like a
> piece of paper inside a folder.

This person writes software for a living. They know what a database is. The analogy is not just unhelpful, it is insulting.

**Fix.** Treat the reader as what they are: a competent professional in a new area. If they are reading an explanation of database isolation levels, they already know what a database is. Start from where they are, not from where a 10-year-old would be.

The cost is cognitive, not only social: re-explaining what the reader already knows is redundant load - the **expertise-reversal effect**, where scaffolding that helps a novice slows an expert. Explaining what a Git commit is before explaining `git rebase` to a senior engineer does not help; it makes them wade through what they walked in knowing.

## 7. The Scope Creep

**Symptom.** A question about a narrow topic gets answered with a tour of the entire surrounding ecosystem. The TCP question gets a lecture on the history of networking. The WebSocket framing question gets HTTP, TLS, and RFC 793.

**Broken form** (responding to "how does WebSocket framing work?")

> To understand WebSocket framing, we should first review the history of
> network protocols, starting with the OSI model. The transport layer in
> particular plays a critical role… [twenty paragraphs later] …and that's
> how we eventually arrived at WebSocket framing.

The reader asked one question. They got an essay.

**Fix.** Answer the question asked, at the depth the question warrants. Surrounding context belongs only when it is *load-bearing* for the answer. Follow-up questions exist; they are how dialogue works.

If the surrounding context is genuinely required, name it explicitly as prerequisite ("this answer assumes you know that WebSocket runs over a TCP connection initially upgraded from HTTP - if not, [link]") rather than expanding the scope of the answer itself.

## 8. The Unverified Survey

**Symptom.** Listing frameworks, tools, APIs, configuration options, or behaviours pulled from training data without checking whether they apply to the current version. Especially common in answers about ecosystems that move fast (JS bundlers, Python packaging, cloud SDKs, LLM tooling).

**Broken form**

> Popular React state management libraries include Redux, MobX, Recoil,
> Zustand, Jotai, Valtio, XState, and Effector. Most projects today use
> Redux Toolkit because it provides a sensible default API.

Some of those libraries may have been deprecated, renamed, merged, or displaced. The "most projects today" claim is unverifiable training-data extrapolation.

**Fix.** Verify against current sources before listing. If a list is meant to be exhaustive or "current", check it. If it is meant to be illustrative, say so explicitly: "Examples include X and Y; the ecosystem changes quickly, so verify currency before adopting."

For active ecosystems, prefer pointing the reader at the authoritative index (the framework's docs, the language's official package list, the project's GitHub) over reciting a list.

## 9. The Hollow Opener

**Symptom.** A filler claim included for conversational rhythm rather than because it carries information. The classic case is a rapport-opener - "these two are easy to confuse", "this is the tricky part", "here is where it gets interesting" - asserted before, or instead of, showing that it is true.

**Broken form**

> The single-writer rule and WAL mode are easy to confuse.

Followed by two paragraphs describing two clearly distinct, non-overlapping mechanisms. The reader who was not confused now distrusts themselves: *why is this "easy" to confuse - what am I missing?* The opener asserted a difficulty the body never substantiates, so the reader hunts for a point that does not exist.

**Fix.** Cut the filler, or earn it. If you claim two things are confusable, the next sentence must show the specific way they get mixed up. If they do not actually get confused, delete the opener and state the distinction directly. This is a Quantity failure - the reader assumes the claim has a point - compounded by a Quality one, since the claim was not true. Casual register changes sentence rhythm, never the standard that every sentence be true and load-bearing.

## 10. The Cold Start

**Symptom.** A sentence or paragraph opens on new or unanchored information instead of linking to what the reader already has. Unlike the Jargon Wall, every word is defined and clear; unlike the Expert Blind Spot, no step is missing. The order is the fault - the new arrives before the given, so the reader's search for an antecedent fails and they stumble.

**Broken form**

> A retry budget that decrements on every attempt and refuses new work at zero is what the client checks before each call.

The sentence opens on a long, brand-new noun phrase. The reader has nothing established to attach it to yet.

**Fix.** Known to the front, new to the end, and let the new become the starting point of the next sentence (the given-new contract; theme before rheme). Reworked: *"Before each call, the client checks its retry budget. That budget decrements on every attempt and refuses new work at zero."* Each sentence now starts on something already established. This is the sentence-level form of Manner's *be orderly*.

## Maxims and the cross-cutting principle

Each anti-pattern is a broken conversational maxim, and naming the maxim points straight at the fix:

| Anti-pattern | Maxim broken | Why |
|---|---|---|
| 1. Textbook Dump | Relation + Manner | relevant material in the wrong order, at the wrong stage |
| 2. Expert Blind Spot | Quantity (too little) | a step the reader needs is missing |
| 3. Allegory Cascade | Manner | obscurity: metaphors bury the subject |
| 4. Confidence Bluff | Quality | stated without evidence |
| 5. Jargon Wall | Manner | obscurity: undefined terms stacked |
| 6. Kindergarten Trap | Quantity (too much) + tone | redundant load on an expert (expertise-reversal), plus condescension |
| 7. Scope Creep | Quantity (too much) + Relation | answering a larger question than asked |
| 8. Unverified Survey | Quality | lists recited without checking currency |
| 9. Hollow Opener | Quantity + Quality | filler with a phantom point, often untrue |
| 10. Cold Start | Manner | given/new order inverted: new before its antecedent |

Quality is primary: patterns 4, 8, and the Quality half of 9 corrupt the reader's model directly, which is the worst failure mode - an honest gap beats a fluent error.

Two root causes underlie the table. Patterns 1, 2, 4, 5, 7, 8 ship a skipped verification or synthesis step; defend with the **investigation discipline** of the `conducting-deep-research` skill. Patterns 3, 6, 9, 10 are calibration failures - over-explaining, talking down, filling space, or mis-ordering information; defend with the **calibration discipline** of `communication-calibration.md`.
