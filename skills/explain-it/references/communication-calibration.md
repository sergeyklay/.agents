# Communication Calibration

## Contents

- Audience model
- Precision
- Analogies (the bounded-analogy pattern)
- Tone (banned phrases, acceptable warmth)
- Vocabulary pacing
- Curse-of-knowledge countermeasures
- Calibration checklist

This document expands the four calibration dimensions from `SKILL.md`: **precision**, **analogies**, **tone**, and **vocabulary pacing**. Read it when an explanation is going off the rails and you cannot name why, or when preparing to write for an audience whose technical background is unclear.

## Audience model

Hold one model of the reader at all times: a competent technical professional who is unfamiliar with *this specific topic*. They write software (or build systems, or do science) for a living. They handle complexity for a living. They have not encountered this particular thing yet.

This single fact shapes every calibration choice below. The reader is not fragile. They are not lazy. They are not a beginner. They are a peer with a different specialisation.

## Precision

Call things by their actual names. When introducing a new term, define it once and use it consistently afterwards. Do not paraphrase a defined term later in the text — that is not graceful variation, it is a working-memory tax on the reader.

**Precision in vocabulary is how you respect the reader's ability to form accurate mental models.** Vague language does not protect a confused reader — it gives them false confidence that they understood something they did not.

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

## Analogies

A good analogy maps specific properties from a familiar domain to the unfamiliar one. It is not a vibe match. It is not a marketing slogan. It is a single structural correspondence that gives the reader a handhold.

### The bounded analogy pattern

When you use an analogy, do exactly three things:

1. **Name what maps.** "X is like Y in the sense that [specific property Z]."
2. **Name where it breaks.** "Unlike Y, X does not [property where the analogy fails] — and that difference matters because…"
3. **Move on.** Do not build on the analogy further. Return to direct explanation.

### Worked example

> A Go channel is like a Unix pipe in the sense that one goroutine writes
> bytes (well — values) and another reads them in order. Unlike a pipe, a
> channel is typed and can be closed by either side, and the language has
> built-in syntax (`select`) for waiting on multiple channels at once. That
> last difference is the reason `select` exists: pipes need `epoll` or
> equivalent to multiplex; channels do it natively.

After this paragraph, return to direct explanation. Do not say "imagine the pipe is colourful…", do not extend the metaphor to packaging or shipping or postal workers. The handhold has done its job.

### When to skip the analogy

If you cannot bound the analogy cleanly — if you cannot name where it breaks — do not use it. Direct explanation is always available as a fallback, and direct explanation never misleads.

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
- "It's easy — you just…"
- "Don't worry about the details…"

The word **"just"** is the most common offender. Search every draft for it. Each occurrence likely hides a skipped explanation or a value judgement about how easy something should feel. Replace or remove every one.

### What replaces them

Nothing. The sentence after "Simply put, X is Y" usually works fine on its own as "X is Y". Patronising framing does not ease learning — it adds noise and signals to the reader that they need to be managed.

### Acceptable warmth

The ban on patronising framing is not a ban on warmth or personality. It is fine — and good — to write with voice, to acknowledge that something is non-obvious, to flag when a topic has well-known footguns. The line is between *acknowledging the reader's intelligence* (warmth) and *managing their feelings* (patronising).

| Patronising | Acknowledging |
|---|---|
| "Don't worry, this is simpler than it looks!" | "This is one of the parts that took me a while to internalise — here is the move that made it click." |
| "Great question — many people get confused here!" | "This is genuinely confusing because the docs name two different things 'context'." |
| "Easy: just call `defer cleanup()`." | "Use `defer cleanup()`. The subtle part is that `defer` runs in LIFO order, so the order of `defer` statements matters." |

## Vocabulary pacing

Each new domain-specific term is a chunk in working memory. Stack five in a sentence and the reader stops understanding and starts cataloguing. The **order** and **pacing** of term introduction controls cognitive load.

### Rules

- **One new term per sentence.** Two if absolutely necessary, never three.
- **Define each term once, on first use.** The definition can be parenthetical, a short clause, or a full sentence — but it must be there.
- **Reuse the defined term consistently.** Do not switch to a synonym to avoid repetition. Repetition reduces working-memory load; synonym variation increases it.
- **Order terms by dependency.** If understanding term B requires understanding term A, introduce A first — even if B is more important to the conclusion.

### Counter-example to avoid

> The event loop processes microtasks from the task queue after macrotask
> completion via the structured clone algorithm using transferable objects.

This sentence introduces six terms with no definitions and no order. It teaches nothing. The reader either already knows all six (in which case the sentence is redundant) or knows none (in which case the sentence is opaque).

### Reworked

> JavaScript runtimes process work in **macrotasks** — coarse-grained units
> like "run this script" or "handle this network event". After each macrotask
> finishes, the runtime drains a separate queue of **microtasks** — finer
> work like resolving a promise. This means a promise's `.then` handler
> always runs before the next `setTimeout` callback, even if the timeout is
> set to zero.

Two terms (macrotask, microtask), introduced in dependency order, each with a one-sentence definition, followed by a concrete consequence. The reader gains a working mental model from the same number of words.

## Curse-of-knowledge countermeasures

Once you understand something, you cannot fully imagine what it was like not to understand it. This is the **curse of knowledge** (Camerer, Loewenstein and Weber, 1989), and it is the most destructive force in technical explanation.

Symptoms:

- Unexplained acronyms ("Configure the IAM role")
- Missing "why" ("Just add the middleware" — why? what does it do?)
- Skipped prerequisites ("Set up the webhook" — the reader has never created a webhook)
- Minimising language ("Simply run the migration" — there is nothing simple about it for someone who has never done it)

Countermeasures:

- Search every draft for "just", "simply", "obviously", "of course", "easy", "straightforward". Each occurrence likely hides a skipped explanation.
- Write for your past self six months ago — the version of you that had never seen this technology before.
- Ask before each sentence: "What would I have needed to know before this sentence made sense?"

## Calibration checklist

Before publishing an explanation, walk this checklist:

- [ ] First paragraph names the **why**, not the **what**.
- [ ] Each new technical term has a one-sentence definition on first use.
- [ ] No sentence introduces more than two new terms.
- [ ] No analogies appear without a "this is where it breaks" sentence.
- [ ] Search results for "just", "simply", "obviously", "of course", "straightforward" return zero matches — or each occurrence has been reviewed and justified.
- [ ] No sentence states an implementation detail that was not verified against source code or authoritative documentation.
- [ ] The closing paragraph names a tradeoff, a failure mode, or a runnable experiment — not a triumphant summary.
