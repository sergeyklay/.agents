# Output Templates

## Contents

- When to use which shape
- Length budgets
- Narrow question template
- Broad question template
- TL;DR pattern
- Behaviour-altitude template
- "Try it" pattern
- Citation patterns
- Diagnostic question template

Two shapes apply to almost every explanation produced under this skill, plus a third for answers pitched at behaviour altitude. This file gives the templates, the length budgets they run under, and the small patterns that go inside them.

Read this file before writing the first broad-question response in a session.

## When to use which shape

| Question shape | Output shape |
|---|---|
| Narrow, targeted ("what is the default timeout?") | Direct answer, no preamble |
| Comparative ("X vs Y for use case Z") | Direct comparison, then tradeoff summary |
| Mechanism ("how does X work?") | TL;DR + full investigation |
| Conceptual ("what is X?") | TL;DR + full investigation |
| Architectural ("when should I use X?") | Direct recommendation, then conditions and reversal triggers |
| Diagnostic ("why is X behaving this way?") | Hypothesis-led - most likely cause first, then alternatives, then verification step |
| Consequence ("what does this change for our users?", "explain this proposal to me") | Behaviour-altitude template |

The last row is set by the reader's role rather than the question's grammar, so it can pair with any of the rows above it. "How does X work?" from someone who will approve X and never open it is a behaviour-altitude question wearing a mechanism-question's clothes. Read the role, not only the wording (`SKILL.md`, *Output format*).

## Length budgets

Name a ceiling in Phase 1, before drafting, and check the finished draft against it by counting rendered lines including blank ones. That is the unit the reader experiences. Estimating instead of counting defeats the exercise, because the drift this guards against is invisible from inside the draft.

| Answer | Default ceiling | Rationale |
|---|---|---|
| Narrow question | under 10 lines | the answer plus the one sentence that makes it actionable |
| Behaviour altitude | about 70 lines | roughly a screen and a half; past that a reader who wanted the short version has stopped |
| Mechanism altitude, broad | no fixed ceiling, but state one | the ceiling exists to be checked against, not to be uniform |

Three rules govern the ceiling:

1. **A ceiling from the reader replaces the default and is a hard limit.** Not a target to approach, and not a suggestion to round up from. Coming in under it is a good outcome, never a shortfall to pad.
2. **Cut extraneous load first, then scope, then depth.** When a draft runs over, the repair order is fixed: delete restatement, hedging and filler; then narrow the question being answered; only then reduce depth. Reducing depth first produces a vague answer of the right length, which is the worst available trade (see *Cognitive load* in `communication-calibration.md`).
3. **Name what you cut.** One sentence offering the omitted material ("the mechanism behind this is a separate pass; ask if you want it") costs a line and turns a truncated answer into a scoped one.

## Narrow question template

Answer directly. No preamble. Add the smallest amount of supporting context needed for the answer to be useful, then stop.

> **Q.** What is the default goroutine stack size in Go 1.22?
>
> **A.** 8 KB. The runtime grows the stack on demand up to a configurable
> maximum (default 1 GB on 64-bit systems, set with `runtime/debug.SetMaxStack`).
> Source: `runtime/stack.go` in the Go 1.22 source tree.

Notes on the example:

- No "Great question!"
- No restatement of the question.
- Direct numeric answer first.
- One sentence of supporting mechanism so the answer is actionable.
- Citation to the source of the fact.

## Broad question template

```markdown
## TL;DR

[3–5 sentences. What it is, the problem it solves, the core mechanism in plain terms.
Enough for orientation; not a substitute for the full explanation that follows.]

## Why this exists

[2–3 sentences. The problem that motivated the thing. The first concrete situation
in which someone would reach for it.]

## [First concept along the aha path]

[Bridge to adjacent knowledge in the first sentence. Define the concept. Give a
concrete example before introducing the next concept.]

## [Second concept along the aha path]

[Definition, example, then the mechanism by which it relates to the first concept.]

## How it actually works

[Worked example. Real code from real sources. Trace an execution path step by step.
What happens? What data structures? What triggers what?]

## Tradeoffs and where it breaks

[What this sacrifices for what it gains. Where it stops working. What practitioners
learn the hard way. When to use, when not to use.]

## Try it

[A minimal, concrete experiment the reader can run in <5 minutes to see the concept
in action. Include the exact command or code, the expected output, and the one
observation that confirms understanding.]
```

## TL;DR pattern

The TL;DR is not a summary of the article. It is a **standalone orientation** for a reader who may stop reading after it.

Three sentences typically suffice:

1. **What it is.** A precise one-sentence identification - not a category ("a JavaScript framework"), but a specific function ("a JavaScript framework for building UIs from declarative components").
2. **What problem it solves.** The motivation, in one sentence.
3. **The core mechanism.** The one idea that, if grasped, makes the rest of the article easier to read.

If the topic genuinely needs five sentences, use five. Never more. If you need a sixth, the article is too broad and should be split.

### Worked TL;DR

> **TL;DR.** React's reconciliation is the algorithm that decides which DOM
> nodes to update when application state changes. The problem it solves is
> that re-creating the entire DOM on every state change would be far too
> slow for interactive UIs. React solves this by maintaining an in-memory
> tree of "what the UI should look like", diffing it against the previous
> version, and applying only the minimal set of DOM mutations needed -
> using component identity and `key` props as hints to match nodes between
> the old and new trees.

Three sentences. Each carries a load. Together they orient the reader.

## Behaviour-altitude template

For a reader who will decide, review, approve or use the thing rather than change it. Same standard of precision as the broad template, different subject matter: what happens, not what runs.

```markdown
## What is broken now

[The situation as the reader would encounter it, not as the code produces it. One
concrete scenario, with the numbers that make it real: how often, how long, how
many, how much. This is the section that earns the rest.]

## What changes

[The same scenario after the change, told as observable events. The reader should be
able to check this claim by watching the system, not by reading the diff.]

## What it costs

[The trade. Every change buys one property with another - latency for freshness,
storage for speed, flexibility for a smaller surface. Name what is given up and the
situation in which giving it up would be the wrong call.]

## What you will see

[The behaviour-altitude counterpart of "Try it": the observation that confirms the
change landed. A screen that loads differently, a number that moves, an error that
stops arriving. Name the before and after values.]
```

Identifiers appear in this template only when the reader will type, click or search for them (the identifier test in `communication-calibration.md`). An internal name that fails the test is replaced by what it does, never by an analogy.

## "Try it" pattern

At mechanism altitude, every broad-question response about a software topic ends with a runnable experiment. At behaviour altitude the closing move is "What you will see" above: the reader is not going to run anything, and handing them a command is the altitude slipping at the last paragraph. The experiment must satisfy four constraints:

1. **Runnable in under five minutes** with tools the reader already has, or with one obvious install command.
2. **Concrete enough to copy-paste** - exact commands, exact code, exact inputs.
3. **The expected output is named** - so the reader can confirm success without further investigation.
4. **One observation confirms understanding** - name what to look for, not "play around with it".

### Worked "Try it"

> **Try it.** Save this as `gc.go` and run with `GODEBUG=gctrace=1 go run gc.go`:
>
> ```go
> package main
>
> import "runtime"
>
> func main() {
>     for i := 0; i < 10; i++ {
>         _ = make([]byte, 10<<20) // 10 MiB
>         runtime.GC()
>     }
> }
> ```
>
> You should see ten `gc N @…s …%` lines in stderr. The middle column shows
> the heap size *before* and *after* each GC cycle - confirm that the
> "after" number drops back to a small baseline each time. That drop is the
> sweep phase reclaiming the 10 MiB allocation.

Notes:

- Exact code.
- One command to run.
- The expected output is named ("ten `gc N @…s …%` lines").
- One specific observation confirms understanding ("the 'after' number drops").

## Citation patterns

Every implementation claim earns a citation. Three acceptable forms:

| Pattern | Use when | Example |
|---|---|---|
| Inline source pointer | Pointing at a file in a known repo | "Source: `runtime/stack.go` in the Go 1.22 tree." |
| Linked authoritative doc | Pointing at official documentation | "See the [Go memory model](https://go.dev/ref/mem)." |
| Direct quote with link | The exact wording matters | "The Anthropic engineering team writes that *'token usage by itself explains 80% of the variance'*: [How we built our multi-agent research system](https://www.anthropic.com/engineering/built-multi-agent-research-system)." |

Do **not** cite training data. If the only justification for a claim is "I remember reading this somewhere", the claim does not belong in the explanation until it has been verified.

## Diagnostic question template

For "why is X behaving this way?" questions, lead with the most probable cause, then enumerate alternatives in descending probability, then name the verification step.

```markdown
## Most likely

[The top-probability cause, in one paragraph. State the mechanism by which
this cause would produce the observed behaviour.]

## Other possibilities

- **[Alternative 1].** [One sentence on the mechanism. One sentence on what
  would distinguish it from the most likely cause.]
- **[Alternative 2].** [Same shape.]

## How to confirm

[A single concrete diagnostic command, query, or observation that
distinguishes the alternatives. Name the expected output for each branch.]
```

This shape forces honesty about uncertainty without abandoning the reader to a list of equiprobable hypotheses.
