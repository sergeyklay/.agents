# Communication Calibration

## Contents

- Audience model
- Precision
- Analogies (the bounded-analogy pattern)
- Tone (banned phrases, acceptable warmth)
- Vocabulary pacing
- Information flow (given before new)
- Cognitive load (what you can cut)
- Curse-of-knowledge countermeasures
- Calibration checklist

This document expands the five calibration dimensions from `SKILL.md`: **precision**, **analogies**, **tone**, **vocabulary pacing**, and **information flow**. Read it when an explanation is going off the rails and you cannot name why, or when preparing to write for an audience whose technical background is unclear.

## Audience model

Hold one model of the reader at all times: a competent technical professional who is unfamiliar with *this specific topic*. They write software (or build systems, or do science) for a living. They handle complexity for a living. They have not encountered this particular thing yet.

This single fact shapes every calibration choice below. The reader is not fragile. They are not lazy. They are not a beginner. They are a peer with a different specialisation.

## Precision

Call things by their actual names. When introducing a new term, define it once and use it consistently afterwards. Do not paraphrase a defined term later in the text - that is not graceful variation, it is a working-memory tax on the reader.

**Precision in vocabulary is how you respect the reader's ability to form accurate mental models.** Vague language does not protect a confused reader - it gives them false confidence that they understood something they did not.

### Examples

| Vague | Precise |
|---|---|
| "The timeout is relatively short" | "The timeout is 30 seconds" |
| "This function handles the request efficiently" | "This function processes the request in O(log n) time using a B-tree index" |
| "The system uses some kind of cache" | "The system uses a write-through LRU cache with a 256MB ceiling" |
| "Goroutines are like threads" | "Goroutines are user-space tasks scheduled by the Go runtime onto a small pool of OS threads" |

### When precision must be deferred

Sometimes you genuinely do not know the precise answer mid-explanation. Acceptable responses, in order of preference:

1. Stop, find out, then write the precise answer.
2. State the precise scope of your uncertainty: "The exact pacing constant is tunable; the default in Go 1.22 is 100, but I have not verified this for newer releases."
3. Mark the imprecision explicitly: "approximately X" or "on the order of Y".

Never substitute a vague phrase for an unknown precise value. "Relatively fast" is a lie disguised as humility.

### Concreteness: verbs over zombie nouns

Abstraction hides action. A *nominalisation* - a verb or adjective turned into a noun (`implement` becomes `the implementation of`, `compare` becomes `performs a comparison`) - is what Pinker calls a "zombie noun": it strips the doer and the action out of the sentence, and usually drags a passive in behind it. Prefer the concrete verb.

| Zombie-noun (abstract) | Concrete (verb-driven) |
|---|---|
| "Validation of the input is performed before execution of the query." | "The handler validates the input before it runs the query." |
| "Acquisition of the lock precedes modification of the row." | "The worker acquires the lock before it modifies the row." |

The rule is not "ban the passive". A passive earns its place when the actor is irrelevant ("the row is locked for the length of the transaction") or when it keeps the given before the new (see Information flow). Convert a passive only once you know which of those it is doing.

## Analogies

A good analogy maps specific properties from a familiar domain to the unfamiliar one. It is not a vibe match. It is not a marketing slogan. It is a single structural correspondence that gives the reader a handhold.

### The bounded analogy pattern

When you use an analogy, do exactly three things:

1. **Name what maps.** "X is like Y in the sense that [specific property Z]."
2. **Name where it breaks.** "Unlike Y, X does not [property where the analogy fails] - and that difference matters because…"
3. **Move on.** Do not build on the analogy further. Return to direct explanation.

### Worked example

> A Go channel is like a Unix pipe in the sense that one goroutine writes
> bytes (well - values) and another reads them in order. Unlike a pipe, a
> channel is typed and can be closed by either side, and the language has
> built-in syntax (`select`) for waiting on multiple channels at once. That
> last difference is the reason `select` exists: pipes need `epoll` or
> equivalent to multiplex; channels do it natively.

After this paragraph, return to direct explanation. Do not say "imagine the pipe is colourful…", do not extend the metaphor to packaging or shipping or postal workers. The handhold has done its job.

### When to skip the analogy

If you cannot bound the analogy cleanly - if you cannot name where it breaks - do not use it. Direct explanation is always available as a fallback, and direct explanation never misleads.

A single well-bounded analogy can illuminate a non-obvious relationship. Three analogies in sequence bury the actual explanation under metaphor noise. **When in doubt, explain directly. Precision beats cleverness.**

## Tone

The tone is "competent peer to competent peer". Not "teacher to pupil", not "expert to layman", not "consultant to client".

### Banned phrases

These signal patronising framing. Cut them on sight.

- "Great question!"
- "Think of it like a pizza delivery service…"
- "Simply put…"
- "Just…"
- "Obviously…"
- "Of course…"
- "It's easy - you just…"
- "Don't worry about the details…"

The word **"just"** is the most common offender. Search every draft for it. Each occurrence likely hides a skipped explanation or a value judgement about how easy something should feel. Replace or remove every one.

### What replaces them

Nothing. The sentence after "Simply put, X is Y" usually works fine on its own as "X is Y". Patronising framing does not ease learning - it adds noise and signals to the reader that they need to be managed.

### Acceptable warmth

The ban on patronising framing is not a ban on warmth or personality. It is fine - and good - to write with voice, to acknowledge that something is non-obvious, to flag when a topic has well-known footguns. The line is between *acknowledging the reader's intelligence* (warmth) and *managing their feelings* (patronising).

| Patronising | Acknowledging |
|---|---|
| "Don't worry, this is simpler than it looks!" | "This is one of the parts that took me a while to internalise - here is the move that made it click." |
| "Great question - many people get confused here!" | "This is genuinely confusing because the docs name two different things 'context'." |
| "Easy: just call `defer cleanup()`." | "Use `defer cleanup()`. The subtle part is that `defer` runs in LIFO order, so the order of `defer` statements matters." |

## Vocabulary pacing

Each new domain-specific term is a chunk in working memory, and working memory holds only a few chunks of genuinely new material at once - about four when the reader cannot yet group them (Cowan), not the popular "seven" (that figure assumes the reader can already chunk, which is exactly what they cannot do with terms they have never met). That is why the limit below is two new terms per sentence, with margin. The **order** and **pacing** of term introduction controls cognitive load.

### Rules

- **One new term per sentence.** Two if absolutely necessary, never three.
- **Define each term once, on first use.** The definition can be parenthetical, a short clause, or a full sentence - but it must be there.
- **Reuse the defined term consistently.** Do not switch to a synonym to avoid repetition. Repetition reduces working-memory load; synonym variation increases it.
- **Order terms by dependency.** If understanding term B requires understanding term A, introduce A first - even if B is more important to the conclusion.

### Counter-example to avoid

> The event loop processes microtasks from the task queue after macrotask
> completion via the structured clone algorithm using transferable objects.

This sentence introduces six terms with no definitions and no order. It teaches nothing. The reader either already knows all six (in which case the sentence is redundant) or knows none (in which case the sentence is opaque).

### Reworked

> JavaScript runtimes process work in **macrotasks** - coarse-grained units
> like "run this script" or "handle this network event". After each macrotask
> finishes, the runtime drains a separate queue of **microtasks** - finer
> work like resolving a promise. This means a promise's `.then` handler
> always runs before the next `setTimeout` callback, even if the timeout is
> set to zero.

Two terms (macrotask, microtask), introduced in dependency order, each with a one-sentence definition, followed by a concrete consequence. The reader gains a working mental model from the same number of words.

### Naming is chunking

Defining a term is not bookkeeping; it is how you raise the reader's capacity. Cowan's own illustration: the letters `F B I C I A` are six separate items to someone who does not read them as acronyms, but two chunks - `FBI`, `CIA` - to someone who does. A technical term behaves the same way. Before you define `backpressure`, it is loose syllables the reader holds piece by piece; once you have defined it, it collapses into one chunk they carry forward for free. Every term you name and define *buys back* working memory - which is how an explanation goes deep without overloading, as long as it chunks as it goes.

## Information flow: given before new

The most common reason an explanation reads as "every word is clear, but I keep stumbling" is information order. Each sentence carries *given* information (what the reader can already identify) and *new* information. The reader comprehends by finding an antecedent for the given, then attaching the new to it - the given-new contract (Clark & Haviland). When a sentence opens on the new instead, the antecedent search fails and the reader stalls, even though every word is familiar.

### Rules

- **Open from the known, end on the new.** The start of the sentence is the reader's handhold; put the already-established term, entity, or idea there, and let the new information land at the end. This is theme-before-rheme order (Halliday): the Theme is the point of departure and carries given information, the Rheme develops it and carries the new.
- **Chain sentences: new becomes next given.** Let the new at the end of one sentence become the starting point of the next. This is linear thematic progression (Daneš), and it is the characteristic flow of expository writing.
- **Reuse the reference, do not vary it.** The reader matches the given by recognising the same words; a synonym swap breaks the match (see Precision).

### Counter-example to avoid

> A separate `-wal` file that the writer appends to is what readers read the old version from. Blocking the writer is therefore something a read never does.

Both sentences open on heavy, brand-new noun phrases. The reader has no handhold and stumbles, though every word is clear.

### Reworked

> When the writer commits, it appends to a separate `-wal` file. That file is what readers read from while the commit is in flight, so a read never blocks the writer.

The first sentence opens from the known writer and ends on the new `-wal` file. The second opens on *that file* - the previous sentence's new information - and ends on the new consequence. The reader always starts on something already established.

## Cognitive load: what you can cut and what you cannot

When a passage reads as too hard, name which load is to blame before cutting anything (Sweller). There are three:

- **Intrinsic** - the inherent difficulty of the material, set by how many parts must be held together at once (element interactivity). Recursion is hard because the call and its result refer to each other; you cannot delete that. Manage intrinsic load by sequencing and chunking, not by removing it.
- **Extraneous** - difficulty added by presentation: a tangent, an undefined term, inconsistent naming, a sentence that opens on the new. This is the load you must cut, and most of this file is about cutting it.
- **Germane** - the productive effort of building the mental model. This is the load you *want*; protect it by clearing the other two out of its way.

The triage question is *"is this hard because the topic is hard, or because I made it hard?"* If intrinsic, slow down and chunk. If extraneous, delete. An expert-elsewhere reader has little spare capacity for *your* extraneous load - which is also why re-explaining what they already know (the Kindergarten Trap) hurts: it is redundant load, not just bad manners.

## Curse-of-knowledge countermeasures

Once you understand something, you cannot fully imagine what it was like not to understand it. This is the **curse of knowledge** (Camerer, Loewenstein and Weber, 1989); Pinker calls it the single best explanation he knows of why good people write bad prose. It is the most destructive force in technical explanation.

Symptoms:

- Unexplained acronyms ("Configure the IAM role")
- Missing "why" ("Just add the middleware" - why? what does it do?)
- Skipped prerequisites ("Set up the webhook" - the reader has never created a webhook)
- Minimising language ("Simply run the migration" - there is nothing simple about it for someone who has never done it)

Countermeasures:

- Search every draft for "just", "simply", "obviously", "of course", "easy", "straightforward". Each occurrence likely hides a skipped explanation.
- Write for your past self six months ago - the version of you that had never seen this technology before.
- Ask before each sentence: "What would I have needed to know before this sentence made sense?"

## Calibration checklist

Before publishing an explanation, walk this checklist:

- [ ] First paragraph names the **why**, not the **what**.
- [ ] Each new technical term has a one-sentence definition on first use.
- [ ] No sentence introduces more than two new terms.
- [ ] No analogies appear without a "this is where it breaks" sentence.
- [ ] Search results for "just", "simply", "obviously", "of course", "straightforward" return zero matches - or each occurrence has been reviewed and justified.
- [ ] No sentence states an implementation detail that was not verified against source code or authoritative documentation.
- [ ] Every paragraph is relevant *at this point* - nothing true-but-premature, nothing on-topic-but-not-needed-yet (Relation).
- [ ] No sentence is filler: each carries information the reader needs, none is included only for rhythm (Quantity - the reader assumes filler has a point).
- [ ] Each sentence opens from something already established and ends on the new; across sentences, the new becomes the next sentence's starting point (given before new).
- [ ] Actions are concrete verbs, not nominalisations ("validates", not "performs validation"); every passive earns its place - actor irrelevant, or preserving given-new.
- [ ] The closing paragraph names a tradeoff, a failure mode, or a runnable experiment - not a triumphant summary.
