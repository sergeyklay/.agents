# Spec-{SLUG}

**Tracker ref:** {ID or URL, or "N/A"} \
**Feature:** {One-sentence summary of the feature or change.}

**Status:** working document, not a deliverable. Gitignored, local to one machine, discarded days after the work lands. It is a prompt for the planner, coder, and tester agents; nobody publishes it, commits it, or reads it afterwards.

**Authority:** binding on scope and design, so do not improvise past it and do not add behavior it does not ask for. Not authoritative on fact: an agent wrote it and it can be wrong about the codebase. Where the two disagree the codebase wins, and the drift gets reported rather than implemented.

<!--
How to use this template.

The reader is an agent, not a person. It does not skim, re-read, or infer what you meant; it consumes the document once and acts on it. Two consequences:

1. DELETE any section this feature does not need. Do not write "N/A", "None", or "Not applicable" under a heading to keep the shape intact. An empty section costs the reader attention and returns nothing. Sections 2, 3.1 to 3.6 and 5 are all deletable when the feature does not reach them; sections 1, 3, 4, 6 and 7 and the Compliance check are structural and stay.
2. WRITE ONCE. Every fact belongs in exactly one section. When a later section needs it, name it rather than restating it. The validator reports the size of this document on every run; if it is over budget, the fix is almost never compression, it is splitting a spec that covers two shippable goals.

Delete this comment when filling the template.
-->

## Compliance check

Report the analysis protocol (Phase 2) by exception. The agent's reasoning trace holds the full nine verdicts; the spec records only what a downstream agent needs: the flagged extensions and the prerequisites verdict. Do not write a nine-row table of GO verdicts; nobody consumes them, and they double the document's opening.

Format:

- The verdict line, always: `All nine checks: GO.` when no check produced FLAG, or one bullet per flagged check in the form `FLAG - {check name}: {what the extension is, and why it is required despite the absence of a source}`. Cite the source or name the decision needing ratification. A reader must be able to tell from this section alone whether the analysis passed, so one of these two forms is present in every delivered spec.
- Additionally, one bullet for Check 9 (Prerequisites) when it names a pending dependency: `Prerequisites: {what must complete first, and the milestone or ticket}`. This bullet supplements the verdict line; it does not replace it.
- A `STOP` MUST NOT appear in a delivered spec (a `STOP` halts drafting until the user resolves it).

## 1. Business goal and value

Concise summary of what is being solved and why. Reference the project's product or PRD document by feature name when applicable. State the target users, the in-scope behavior, and the explicit out-of-scope boundaries. Any deviation from the project's documented "Always / Ask First / Never" rules (or equivalent) MUST be called out in prose; cite the rule by source and quote the relevant text.

## 2. User experience strategy

For features with a user-facing surface. Omit when the feature is purely internal.

Describe the user flow as a numbered sequence. Identify which screens or interfaces are affected. Reference existing components or screens from the project's design or architecture documents. Where the user crosses an asynchronous boundary (saves, loads, errors), state the feedback contract: what the user sees, when, and what state replaces it.

For projects that distinguish between rendering modes, server vs client work, or static vs dynamic surfaces, fill the table below; otherwise omit it.

| Component | Mode | Justification |
|-----------|------|---------------|
| ... | ... | ... |

## 3. Technical architecture

This section defines `WHAT` the implementation MUST do. Do not write runnable code.

### 3.1 Data shape

Define new or modified data shapes using the project's actual schema language: Prisma model, SQL DDL, Mongoose schema, SQLAlchemy model, Protobuf message, OpenAPI component, Pydantic model, Go struct, TypeScript interface, JSON Schema, or whatever the project ships. The schema is the contract.

```{schema-language}
// New or modified data shapes go here.
```

If the project does not centralize shape definitions, define each shape inline next to the interface that uses it.

### 3.2 Public interfaces

For every new or modified function, method, endpoint, action, or RPC the feature introduces. Use the project's actual type language. Signatures only; no implementation bodies.

```{language}
// Examples:
// function createWidget(input: WidgetInput): Promise<WidgetResult>
// POST /api/widgets  request: WidgetInput  response: Widget
// service WidgetService { rpc CreateWidget(WidgetInput) returns (Widget); }
```

For each interface, state:

- Inputs and their validation rules.
- Outputs and their error variants.
- Side effects (writes, external calls, events emitted).
- Idempotency contract, if applicable.

### 3.3 Logic

Describe non-trivial logic as numbered pseudo-code, not prose. Line-oriented, indented for nesting, no narrative filler between steps.

```
function reconcile(state, snapshot):
  for each item in state.running:
    if item not in snapshot:
      cancel(item)
      release(item)
```

For state machines, use a transition table:

| From | Event | To | Action |
|------|-------|----|--------|
| ... | ... | ... | ... |

For cross-component interactions, use a numbered list of `actor -> actor: action` lines:

```
1. Orchestrator -> Adapter: StartSession(workspace, config)
2. Adapter -> Subprocess: launch
3. Subprocess -> Adapter: initialize result
4. Adapter -> Orchestrator: Session{ID, AgentPID}
```

Do not emit Mermaid or ASCII diagrams. Tables and numbered actor-action lines carry the same information without the rendering layer, and a single format eliminates the drift surface between pseudo-code, prose, and a separate visual.

### 3.4 Integration points

List every external system the feature touches (databases, message queues, third-party APIs, internal services). For each:

- Direction of the call (the feature reads, writes, or both).
- Authentication mechanism, citing the project's documented approach.
- Failure mode and retry policy.
- Quota or rate-limit assumption.

### 3.5 State and concurrency

For features with non-trivial state: name what state lives where (client, server, cache, database, external store), who owns it, how it is mutated, and how concurrent mutations are coordinated.

For features that introduce concurrency: name the primitive (channel, queue, lock, transaction, scheduler) and the project's documented usage pattern for it.

### 3.6 Error and failure model

Define typed errors or error variants following the project's error-handling conventions. For each error:

- The condition that produces it.
- The visibility (logged, surfaced to user, returned to caller).
- The recovery path, if any.

For features behind a request boundary, distinguish between client errors (caller fault) and server errors (system fault) using the project's conventions.

State verification as properties, not as a roster of named test cases. A property ("the matcher is called at most once per dispatcher pass") is a contract any reader can check; a test roster ("unit test 7: missing amount skips with one warn") duplicates the implementation plan's test steps and drifts from them. The plan owns the enumeration of test steps.

## 4. Risk assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| ... | Critical/Major/Minor | ... |

Budgeted at eight rows. Every row names an observable failure (data loss, leak, wrong write, user-visible degradation), never an absence of change ("no budget impact" is not a risk). Every mitigation is phrased as a requirement on the implementation, because downstream verification treats each mitigation as a MUST.

## 5. Open questions

Every question that blocked a design decision in Phase 2, up to a maximum of five. Questions that were resolved with a recommendation are decisions, not open questions; record them in the body of Section 3, not here. For each:

- The question.
- Why it matters (which design decision depends on it).
- What information would resolve it.
- A proposed default if the question goes unanswered.

Those four bullets are the whole entry. Do not add option catalogues, recommendations, or trade-off prose: the question is open precisely because this document cannot settle it. Budget for the section is 400 words, enforced by `scripts/validate_spec.py`.

A spec with no open questions is suspicious in any non-trivial feature. Either the design is genuinely complete, or the questions are hidden.

## 6. File structure summary

Tree view of every new or modified file, or an equivalent table. This is the only file listing in the spec: Section 3 names modules in prose and MUST NOT repeat a tree here. Annotate each entry with its role, inside the listing. Use whichever role markers the project documents; the example below is illustrative.

Prose around the listing is budgeted at 80 words and enforced by `scripts/validate_spec.py`. Everything a reader needs about *why* a file changes is already in section 3; repeating it per file doubles the document and adds nothing.

```
src/
  feature-name/
    index.{ext}              [public]   new
    handler.{ext}            [handler]  new
    service.{ext}            [service]  new
schema/
  feature.{ext}              [schema]   modified
```

## 7. Acceptance criteria

If a tracker reference was provided, list every acceptance criterion from it here verbatim and map each criterion to the section of this spec that addresses it. If no tracker reference was provided, derive acceptance criteria from the user prompt and the architecture document; state that explicitly.

Each criterion MUST be testable: a reviewer reading the criterion and the implementation MUST be able to decide whether the criterion is met.

The mapping is a pointer, not a summary. Write `AC-3 -> section 3.3` and stop; do not restate what section 3.3 says. The reader can open the section, and a restatement here is a second copy that drifts from the first. A criterion with no section to point at is the finding: either the design is incomplete or the criterion is out of scope, and both belong in section 5 rather than in a paraphrase.
