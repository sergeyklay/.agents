---
name: explain-it
description: "Explain technical concepts, mechanisms, and systems to a technically fluent reader who is unfamiliar with the specific topic. Use when asked to explain how something works, walk through an algorithm or protocol, write a deep-dive or onboarding article, answer \"what is X\", \"why does X behave this way\", \"how does X work\", \"break down X\", or when synthesising findings from research into a written explanation. Builds understanding progressively along the reader's \"aha path\" - opens with the why, bridges to adjacent knowledge, introduces one concept at a time, traces mechanics through worked examples, closes with tradeoffs and a runnable experiment. Do NOT use for end-user documentation aimed at non-technical audiences, marketing copy, code review, reference-style API documentation, or commit messages."
metadata:
  author: Serghei Iakovlev
  version: "1.0"
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
| **Bridge** to adjacent knowledge | Connect to something the reader likely already knows before introducing the first new concept. The bridge does not need to be perfect - it needs to be a handhold. | 1 sentence |
| Introduce concepts **one at a time** | Each new concept gets a name, a one-sentence definition, and a concrete example *before* the next concept is introduced. Never stack three new terms in a paragraph. | 1 paragraph each |
| Show **mechanics as a worked example** | Trace an execution path through real code. What happens, step by step, when you call this function? What data structures are involved? What triggers what? | As long as needed |
| Report internals **honestly** | Go as deep as the question warrants. Do not hand-wave with "under the hood, it handles this efficiently." If it is worth mentioning, it is worth explaining. If you do not know - say so, or go find it. | As needed |
| Close with **tradeoffs and practice** | What does this sacrifice for what it gains? Where does it break down? What do practitioners learn the hard way? When to use, when not to. For software topics: a minimal, concrete experiment the reader can run. | 1–2 paragraphs |

## Communication calibration

Four dimensions calibrate every paragraph. Brief summary here; load [references/communication-calibration.md](references/communication-calibration.md) when an explanation is going off the rails or for the full rationale.

- **Precision.** Call things by their actual names. Define each new term once, then reuse it consistently. Vague language gives a confused reader false confidence that they understood something they did not.
- **Analogies, sparingly and structurally.** When you use an analogy: name what maps ("X is like Y in the sense that *property Z*"), name where it breaks ("unlike Y, X does not *property W* - that matters because…"), then move on. Do not stack analogies. One bounded analogy can illuminate; three in a row bury the explanation under metaphor noise.
- **Tone.** No "Great question!" No "Think of it like a pizza delivery service!" No "Simply put…" Just explain. Patronising framing signals to the reader that they need to be managed. They do not.
- **Vocabulary pacing.** Each new domain term is a chunk in working memory. Stack five in a sentence and the reader stops understanding and starts cataloguing. The order and pacing of term introduction controls cognitive load.

## Anti-patterns

These are failure modes. If you catch yourself doing any of these, stop and restructure. Full discussion with examples in [references/anti-patterns.md](references/anti-patterns.md).

1. **The Textbook Dump** - Definition → History → Features → Comparison, in mechanical Wikipedia order. Encyclopaedic structure, not explanatory structure.
2. **The Expert Blind Spot** - "And then it does Y, which naturally follows from X." Did you verify the inferential gap is actually small for someone seeing this for the first time?
3. **The Allegory Cascade** - Three metaphors in sequence dilute each other.
4. **The Confidence Bluff** - Stating implementation details you have not verified.
5. **The Jargon Wall** - Combining unexplained terms teaches nothing.
6. **The Kindergarten Trap** - Patronising the reader.
7. **The Scope Creep** - Answering a question larger than the one asked.
8. **The Unverified Survey** - Listing frameworks, tools, or APIs from training data without checking they apply to the current version.

## Output format

Two shapes apply, depending on the question. Templates live in [references/output-templates.md](references/output-templates.md).

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

**Depth is not length.** A precisely traced execution path through 20 lines of real code teaches more than three pages of architectural description. Concreteness is a form of depth.

## When this skill is one half of the job

If the task involves both gathering evidence and writing the explanation, this skill governs only the writing. The investigation discipline - what counts as a source, how many to consult, how to triangulate, when to stop - belongs to the `conducting-deep-research` skill. Load both.

## References

| File | When to read |
|---|---|
| [references/communication-calibration.md](references/communication-calibration.md) | Full discussion of precision, analogies, tone, vocabulary pacing, with examples and counter-examples. Read when calibrating voice for an unfamiliar audience. |
| [references/anti-patterns.md](references/anti-patterns.md) | Each of the 8 anti-patterns with concrete examples and the structural fix. Read when an explanation feels off and you cannot name why. |
| [references/output-templates.md](references/output-templates.md) | TL;DR template, full-investigation template, takeaway and experiment patterns. Read before writing the first broad-question response in a session. |
