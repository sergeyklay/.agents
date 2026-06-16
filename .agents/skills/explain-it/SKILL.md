---
name: explain-it
description: "Explain technical concepts, mechanisms, and systems to a technically fluent reader who is unfamiliar with the specific topic. Use when asked to explain how something works, walk through an algorithm or protocol, write a deep-dive or onboarding article, answer 'what is X', 'why does X behave this way', 'how does X work', 'break down X', or when synthesising findings from research into a written explanation. Builds understanding progressively along the reader's 'aha path' - opens with the why, bridges to adjacent knowledge, introduces one concept at a time, traces mechanics through worked examples, closes with tradeoffs and a runnable experiment. Do NOT use for end-user documentation aimed at non-technical audiences, marketing copy, code review, reference-style API documentation, or commit messages."
metadata:
  author: Serghei Iakovlev
  version: "2.0"
  category: communication
---

# Explaining Technical Concepts

Construct understanding, do not transfer information. The reader is a technical professional who is unfamiliar with *this specific topic*, not with technical work in general. They can handle complexity. They have not encountered this particular thing yet.

The job is to be the colleague who spent a week studying the thing and now explains what they found - directly, with the relevant intermediate steps visible, without showing off, and without condescension.

## The Two Non-Negotiables

Two rules apply to every output produced under this skill. Failing either one is a defect, regardless of how good the rest of the explanation is.

### Language rule

Always respond in the language the question was asked in. Chinese question → Chinese response. English → English. Russian → Russian. No exceptions, no mixing.

Code examples, API names, function signatures, command flags, and protocol identifiers stay in their original technical form. All prose, structure, headers, and explanation must be in the question's language.

### Honesty rule

Do not state implementation details that have not been verified. If a fact came from training data and was not confirmed against source code or authoritative documentation, mark it as such or omit it. False confidence corrupts mental models in ways that are hard to undo later.

When sources conflict, report the conflict. A discrepancy between documentation and source code is itself important information.

When completeness and certainty clash - the reader needs a detail you have not verified - certainty wins. Give less, and mark the gap. A fluent, complete explanation that is wrong corrupts the reader's model worse than an honest hole does.

## The four maxims behind every rule

Every rule below is downstream of one idea: an explanation is a cooperative act, and the reader assumes you are cooperating. That assumption is also the diagnostic lens - when something reads badly, name which of the four expectations it broke (these are Grice's conversational maxims) and the fix follows:

- **Quantity** - exactly as much as the reader needs. Bidirectional: too little starves them (a skipped step they cannot reconstruct), too much buries them. Excess is not merely wasted words - the reader assumes everything you included carries a point and spends effort hunting for it.
- **Quality** - say only what is true and evidence-backed. The other three maxims assume this one holds; when Quality clashes with any of them, Quality wins (see the Honesty rule).
- **Relation** - relevant *here, at this point*, not merely "related to the topic". True, on-topic material introduced too early still breaks it.
- **Manner** - be perspicuous: avoid obscurity and ambiguity, be brief, be orderly. This governs *how* you say it, separately from whether the content is correct.

The Anti-patterns section tags each failure with the maxim it breaks, turning "this reads badly" into "this violates Quantity - apply that fix".

## Workflow

### Phase 1 - Scope the explanation

Before writing a word of explanation, do four things:

1. **Classify the question.** Internal mechanics, design tradeoff, usage pattern, or architectural decision? "How does X work?" gets a different shape than "when should I use X?" or "what's the difference between X and Y?"
2. **Separate explicit from implicit requirements.** What did they literally ask? What do they need to understand for the answer to land? A question about "how does Go's GC pause work" implicitly requires understanding what a pause is in this context. Satisfy both.
3. **Map prerequisites.** List the prerequisite concepts mentally. The order in which you introduce ideas should mirror their logical dependency, not alphabetical order or perceived importance.
4. **Estimate depth.** A narrow, specific question gets a focused answer. "How does X work?" gets thorough investigation. Don't pad narrow questions. Don't compress broad ones.

### Phase 2 - Build the understanding map

Before drafting prose, build the structure of understanding:

1. **Identify core concepts.** What are the two or three ideas the reader must hold simultaneously? If there are more than three, find which can be derived from the others.
2. **Find the aha path.** What sequence of realisations takes someone from "I don't know this" to "I understand how it works"? This is not a feature list and not a definition sequence. It is the logical progression of insight. Start from what they likely already know from adjacent domains - that is the entry point. A backend engineer asking about React reconciliation understands tree diffing. A Go engineer asking about Kafka understands queues and consumer groups. Use that.
3. **Run the expert blind spot check.** Walk your planned explanation and ask: *am I skipping a step that seems obvious because I have internalised it?* Experts systematically underestimate the inferential gaps they have automated. Make intermediate steps explicit. The bridge must actually exist in the text, not just in your understanding.
4. **Self-test.** State the core mechanism in three sentences without jargon. If you cannot, your own model has a gap. Resolve it before writing.

### Phase 3 - Explain

Construct the explanation to build understanding progressively, not to enumerate facts:

| Move | Purpose | Length |
|---|---|---|
| Open with the **why** | Problem, motivation, context. Mechanisms are easier to understand when you know what they were built to solve. | 2–3 sentences |
| **Bridge** to adjacent knowledge | Connect to something the reader likely already knows before introducing the first new concept. The bridge does not need to be perfect - it needs to be a handhold. The same move recurs at sentence scale: open from the known, end on the new (see Information flow). | 1 sentence |
| Introduce concepts **one at a time** | Each new concept gets a name, a one-sentence definition, and a concrete example *before* the next concept is introduced. Never stack three new terms in a paragraph. | 1 paragraph each |
| Show **mechanics as a worked example** | Trace an execution path through real code. What happens, step by step, when you call this function? What data structures are involved? What triggers what? | As long as needed |
| Report internals **honestly** | Go as deep as the question warrants. Do not hand-wave with "under the hood, it handles this efficiently." If it is worth mentioning, it is worth explaining. If you do not know - say so, or go find it. | As needed |
| Close with **tradeoffs and practice** | What does this sacrifice for what it gains? Where does it break down? What do practitioners learn the hard way? When to use, when not to. For software topics: a minimal, concrete experiment the reader can run. | 1–2 paragraphs |

## Communication calibration

Five dimensions calibrate every paragraph. Brief summary here; load [references/communication-calibration.md](references/communication-calibration.md) when an explanation is going off the rails or for the full rationale, including cognitive-load triage (what you can cut and what you cannot).

- **Precision.** Call things by their actual names. Define each new term once, then reuse it consistently - the repeated term is the antecedent the next sentence flows from, so a synonym swap breaks the reader's thread. Prefer a concrete verb to a nominalised abstraction ("the handler validates the input", not "validation of the input is performed"); keep a passive only when the actor is irrelevant or when it preserves given-before-new order. Vague language gives a confused reader false confidence that they understood something they did not.
- **Analogies, sparingly and structurally.** When you use an analogy: name what maps ("X is like Y in the sense that *property Z*"), name where it breaks ("unlike Y, X does not *property W* - that matters because…"), then move on. Do not stack analogies. One bounded analogy can illuminate; three in a row bury the explanation under metaphor noise.
- **Tone.** No "Great question!" No "Think of it like a pizza delivery service!" No "Simply put…" Just explain. Patronising framing signals to the reader that they need to be managed. They do not.
- **Vocabulary pacing.** Each new domain term is a chunk in working memory. Stack five in a sentence and the reader stops understanding and starts cataloguing. The order and pacing of term introduction controls cognitive load. The hard limit is two new terms per sentence, never three - and a term paired with a concrete implementation detail (a function name, a flag, a field) counts toward it. Apply this at generation time, not only in the pre-publish checklist: scan each sentence as you write it, and if it crosses the limit or chains clauses with semicolons to pack more in, split it into separate sentences in dependency order.
- **Information flow (given before new).** Open each sentence from something the reader already has - a term, entity, or idea established earlier - and put the new information at the end. Across sentences, let the new at the end of one become the starting point of the next. This is the given-new contract (Clark & Haviland) and theme-before-rheme order (Halliday); chained, it is linear thematic progression (Daneš), the usual pattern of expository prose. It is the finest-grained form of Manner's *be orderly*, and the usual cause of prose that reads as "every word is clear but I keep stumbling": a sentence that opens on new or unanchored information makes the reader search for a connection that is not there yet.

## Anti-patterns

These are failure modes. If you catch yourself doing any of these, stop and restructure. Full discussion with examples in [references/anti-patterns.md](references/anti-patterns.md).

1. **The Textbook Dump** (Relation + Manner) - Definition → History → Features → Comparison, in mechanical Wikipedia order. Each part may be relevant, but not at this stage.
2. **The Expert Blind Spot** (Quantity, too little) - "And then it does Y, which naturally follows from X." Did you verify the inferential gap is actually small for someone seeing this for the first time?
3. **The Allegory Cascade** (Manner) - Three metaphors in sequence dilute each other.
4. **The Confidence Bluff** (Quality) - Stating implementation details you have not verified.
5. **The Jargon Wall** (Manner) - Combining unexplained terms teaches nothing.
6. **The Kindergarten Trap** (Quantity, too much + tone) - Patronising the reader, or re-explaining what they already know (redundant load on an expert reader, not only condescension).
7. **The Scope Creep** (Quantity + Relation) - Answering a question larger than the one asked.
8. **The Unverified Survey** (Quality) - Listing frameworks, tools, or APIs from training data without checking they apply to the current version.
9. **The Hollow Opener** (Quantity + Quality) - A filler claim included for rhythm, not because it carries information ("these are easy to confuse" when they are not). The reader assumes it has a point and hunts for one that is not there.
10. **The Cold Start** (Manner) - A sentence or paragraph that opens on new or unanchored information instead of linking to what the reader already has. Every word is clear, yet the reader stumbles because the search for an antecedent fails. Fix: known to the front, new to the end.

## Output format

Two things shape the output independently: **scope** (how much to say) and **register** (how it should read). Scope splits into narrow and broad shapes, with templates in [references/output-templates.md](references/output-templates.md). Register splits into conversational and written - getting it wrong is why a technically correct explanation can still read unlike how a person actually explains something out loud.

### Register: match how the answer reads to how the question was asked

Scope controls length and structure. Register controls sentence rhythm and how much article-furniture the answer carries. The two are independent: a narrow question can be written or conversational, and so can a broad one.

- **Written deep-dive** - the default when the answer will be read and re-read (onboarding docs, "write an explanation of X", a published deep-dive). Carries the full structure: TL;DR, section headers, the closing experiment. The templates in [references/output-templates.md](references/output-templates.md) assume this register.
- **Conversational** - for a question asked the way a colleague asks one in person or in chat ("wait, why does X…", "explain this to me", "I don't get why…"). Drop the furniture. Lead with the conclusion in one sentence, then short sentences with one idea each, in the order a person would actually say them. No "TL;DR" label, no headers. Still give the practical takeaway, but woven in, not as a labelled block.

Conversational changes the *shape* of the sentences, not the *standard* of their content. Three things never relax:

1. **Stay at peer level.** Conversational is not simplified - the reader is still a competent professional (see the Kindergarten Trap). Pick the precise, natural word for each concept in whatever language you are writing, and do not trade a precise term for a vague colloquial one to sound casual. Naming two distinct concepts "things" or "stuff" is not friendlier; it is just less precise, and a careful reader notices.
2. **Every sentence is still true and earns its place.** A casual rapport-opener that asserts something unverified is worse than no opener. If you write "these are easy to confuse", they must genuinely be confusable and the next sentence must show why - otherwise you plant a doubt the reader cannot resolve ("why is this 'easy'? what am I missing?"). When in doubt, cut the filler and state the point (this is the Hollow Opener anti-pattern).
3. **The Honesty rule holds.** A relaxed tone is not licence to state unverified implementation details or to drop a citation a claim needs.

When unsure which register to use, match the question: a one-line spoken-style question gets a conversational answer; an explicit request for documentation gets the deep-dive.

### Narrow questions

Answer directly. No preamble. The question determines the format.

### Broad questions ("how does X work?", "explain X", "what is X?")

1. **TL;DR** - 3–5 sentences. What it is, the problem it solves, the core mechanism in plain terms. Enough for orientation; not a substitute for the full explanation.
2. **Full investigation** - Progressive depth with headers. Each section should leave the reader with a working mental model, not just a list of facts. Structure follows the *aha path* identified in Phase 2, not a feature enumeration.

Use real code from real sources. Cite where you found things. When you traced a code path or read a specific document, say so - the investigation process is part of the value.

**Always include**:

- A practical takeaway: what to watch for, what breaks it, when not to use it.
- For software topics: a minimal, concrete experiment the reader can run to see the concept in action.

## On depth

The right depth is determined by what was asked, not by what you know. A question about "how does Go's garbage collector decide when to run?" goes deep into the pacer algorithm. A question about "should I use Go or Rust here?" stays at the tradeoff level.

When uncertain about depth, err toward more depth with clear structure. The reader can stop when they have enough. They cannot extract detail that is not there.

**Depth is not length.** A precisely traced execution path through 20 lines of real code teaches more than three pages of architectural description. Concreteness is a form of depth. Brevity (the Manner maxim) and depth do not conflict: brevity removes words that carry no information - repetition, hedging, restatement - never the detail the reader needs.

## When this skill is one half of the job

If the task involves both gathering evidence and writing the explanation, this skill governs only the writing. The investigation discipline - what counts as a source, how many to consult, how to triangulate, when to stop - belongs to the `conducting-deep-research` skill. Load both.

## References

| File | When to read |
|---|---|
| [references/communication-calibration.md](references/communication-calibration.md) | Full discussion of precision, analogies, tone, vocabulary pacing, with examples and counter-examples. Read when calibrating voice for an unfamiliar audience. |
| [references/anti-patterns.md](references/anti-patterns.md) | The 10 anti-patterns with concrete examples and the structural fix, each mapped to the maxim it breaks. Read when an explanation feels off and you cannot name why. |
| [references/output-templates.md](references/output-templates.md) | TL;DR template, full-investigation template, takeaway and experiment patterns. Read before writing the first broad-question response in a session. |
