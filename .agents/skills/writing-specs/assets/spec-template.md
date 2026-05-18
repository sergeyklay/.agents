# Spec-{SLUG}

**Created at:** {ISO timestamp} \
**Tracker ref:** {ID or URL, or "N/A"} \
**Feature:** {One-sentence summary of the feature or change.}

## Compliance check

Findings from the analysis protocol (Phase 2). Fill one row per check using the verdicts from the agent's reasoning trace. `GO` means no issue; `FLAG` means a documented extension that this spec carries; `STOP` MUST NOT appear in a delivered spec (a `STOP` halts drafting until the user resolves it).

| Check | Verdict | Notes (cite source) |
|-------|---------|---------------------|
| 1. Convention compliance | GO / FLAG | ... |
| 2. Architectural layer | GO / FLAG | ... |
| 3. Interface boundary | GO / FLAG | ... |
| 4. Security and trust boundary | GO / FLAG | ... |
| 5. Resource budget | GO / FLAG | ... |
| 6. Data model | GO / FLAG | ... |
| 7. Runtime model | GO / FLAG | ... |
| 8. Requirements source | GO / FLAG | ... |
| 9. Prerequisites | GO / FLAG | ... |

A row with `GO - N/A` is acceptable when the check does not apply to this feature.

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

### 3.5 Component or module tree

Hierarchical listing of new or modified components or modules. Use the project's actual file layout and annotate each entry with its role. Use whichever role markers the project documents; the example below is illustrative.

```
src/
  feature-name/
    index.{ext}             [public]
    handler.{ext}           [request handling]
    service.{ext}           [business logic]
    repository.{ext}        [data access]
  schema/
    feature.{ext}           [schema]
```

### 3.6 State and concurrency

For features with non-trivial state: name what state lives where (client, server, cache, database, external store), who owns it, how it is mutated, and how concurrent mutations are coordinated.

For features that introduce concurrency: name the primitive (channel, queue, lock, transaction, scheduler) and the project's documented usage pattern for it.

### 3.7 Error and failure model

Define typed errors or error variants following the project's error-handling conventions. For each error:

- The condition that produces it.
- The visibility (logged, surfaced to user, returned to caller).
- The recovery path, if any.

For features behind a request boundary, distinguish between client errors (caller fault) and server errors (system fault) using the project's conventions.

## 4. Risk assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| ... | Critical/Major/Minor | ... |

Cover at minimum: security risk, resource-budget impact, external-quota impact, data-migration risk, user-facing degradation if the feature fails open.

## 5. Open questions

Every question that blocked a design decision in Phase 2. For each:

- The question.
- Why it matters (which design decision depends on it).
- What information would resolve it.
- A proposed default if the question goes unanswered.

A spec with no open questions is suspicious in any non-trivial feature. Either the design is genuinely complete, or the questions are hidden.

## 6. File structure summary

Tree view of every new or modified file. Annotate each entry with its role. Use whichever role markers the project documents; the example below is illustrative.

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
