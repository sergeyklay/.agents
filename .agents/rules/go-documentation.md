
# Go Documentation and Comments

## Package Comments

- Every package must have a `// Package <name>` comment.
- Place the package doc comment in the file named after the package (e.g. `config.go` for package `config`, `prompt.go` for package `prompt`). When no such file exists, use the primary entry-point file. Never place it in `errors.go` or other secondary files.
- Only one file per package may carry the `// Package` doc comment - duplicates cause godoc to pick one arbitrarily.
- State what the package provides and its role within the architecture.
- Mention key types or functions the caller should start with.
- Do not reference internal architecture doc sections - package comments are public API surface.

## Doc Comment Formatting

- Use `//` line comments for doc comments, never `/* */` block comments. This matches the standard library and keeps every doc comment in one consistent form.
- Leave a blank line before a doc comment so it reads as a distinct block. Leave no blank line between the comment and the declaration it documents - godoc only associates a comment with a declaration when they are adjacent, and a blank line there silently turns the doc comment into an ordinary comment.

## Exported Symbol Comments

### Structure

Every exported symbol (function, method, type, constant, variable) must have a godoc comment. The comment follows a strict two-part structure:

**First sentence - mandatory summary.**
Begin with the symbol name as the grammatical subject and end at the first period. This sentence must be self-contained: `go doc -short` and the pkg.go.dev index display only this line.

```go
// Dispatch submits an issue for agent processing and records the running entry.
func (o *Orchestrator) Dispatch(ctx context.Context, issue domain.Issue) error {
```

**Continuation paragraph - conditional.**
Add a second paragraph only when the first sentence does not fully convey the contract: error behavior, nil/zero-input semantics, concurrency safety, or non-obvious preconditions. Keep it to 3–4 sentences maximum. A third paragraph is only justified when it addresses a completely separate semantic topic (e.g., a usage example after describing error behavior).

```go
// WithIssue derives a new logger with issue_id and issue_identifier fields attached.
//
// If log is nil, WithIssue uses [slog.Default] as the base. The returned logger
// is safe for concurrent use.
func WithIssue(log *slog.Logger, issueID, identifier string) *slog.Logger {
```

### Tone and phrasing

Use declarative, present-tense statements. Name what the symbol does or reports, not how to call it.

```go
// ✅ Declarative.
// Validate reports whether the configuration is self-consistent.
// IsRunning reports whether an agent is currently processing the given issue ID.
// Entries returns all running entries ordered by start time, oldest first.

// ❌ Imperative - tells the caller what to do, not what the symbol does.
// Call Validate to check if the configuration is self-consistent.
// Use IsRunning to check whether an agent is running.
```

### What to document

| Topic | Document? |
|---|---|
| What the function returns or does | Always |
| Behavior on nil or zero input | When non-obvious (e.g., returns nil, panics, uses a default) |
| Error conditions | When the set of errors is meaningful to the caller |
| Concurrency safety | Always when relevant ("safe for concurrent use", "must not be called concurrently") |
| Resource or memory ownership | When the caller must close, release, or free something the function returns |
| Preconditions and post-conditions | When they are not self-evident from the signature |
| Implementation details (how it works internally) | Never - belongs in inline comments inside the function body |

For an interface, document the behavior an implementation must provide, not the method signature. A caller reading the interface needs to know what a conforming implementation guarantees, not a restatement of the parameter and return types already visible in the declaration.

### Substance, not restatement

A doc comment that only restates the identifier's name is worse than no comment at all: it looks documented, so nobody adds the sentence that would actually help, and no reader stops to ask the question the comment appears to have already answered.

```go
// ❌ Restates the name; tells the reader nothing pkg.go.dev could not
// already show them.
// User represents a user.
type User struct {

// ✅ States the contract: what the zero value means and how to build one.
// User is an authenticated principal. The zero value is not usable;
// construct it with NewUser.
type User struct {
```

### Cross-references

Use `[Symbol]` bracket syntax (Go 1.19+) to link to related types and functions. Do not spell out package paths in prose when a link suffices.

```go
// Setup initialises the default slog handler. Call [WithIssue] to attach
// issue context to a derived logger.
```

### Code examples

Include a short example only when the composition pattern is genuinely non-obvious. Place it in a `// Example:` block or an `_test.go` example function, not inline in the comment prose.

If the explanation would run a full paragraph, it is not a comment anymore - write an example function instead. Name it `Example<Type>_<Method>` (e.g. `ExampleClient_Do`) in the package's `_test.go` file. An example function compiles, runs under `go test`, and renders on pkg.go.dev - an executable example is always more trustworthy than prose making the same claim.

## What to Avoid

- Do not restate the signature in prose. If the parameter is named `timeout time.Duration`, do not write "timeout is the duration of the timeout".
- Do not use `@param`, `@return`, or any JSDoc-style markup - godoc does not parse it.
- Do not use Markdown formatting (bold, headers, bullet lists) in `//` comments. pkg.go.dev renders a limited subset; inline `//` comments render none.
- Do not reference `docs/architecture.md`, `docs/decisions/`, section numbers, ADR numbers, or internal project tracker tickets (e.g., `SORT-42`) in any comment - godoc or inline. Those belong in specs and plans, not in source files.
- Upstream external references (Go issue tracker `golang/go#NNNNN`, third-party GitHub issues, RFC numbers, CVE IDs) are permitted when they explain a non-obvious workaround that cannot be fully described in prose alone. The reference must accompany an explanation, not replace it.
- Do not write tutorial-style or conversational comments ("This is a helper that…", "We use this to…").
- Do not add comments to unexported symbols unless the logic is genuinely non-obvious.
- Do not add inline comments that merely repeat what the code already says.

## Adapter Packages (`internal/tracker/*`, `internal/agent/*`)

- The package comment must name the external system and the domain interface it implements (e.g. "Package jira implements [domain.TrackerAdapter] for Atlassian Jira Cloud REST API v3").
- Document which normalization rules the adapter applies (label casing, priority mapping, state mapping) so reviewers can verify conformance without reading the spec.
- Do not expose adapter-specific types or terminology in exported symbol names - all public surface uses domain vocabulary.

## Inline Comments

- Reserve inline comments for **why**, not **what**.
- Acceptable: explaining a non-obvious invariant, a safety constraint, or a workaround.
- Unacceptable: narrating control flow (`// loop over items`, `// return error`).

## Lint Suppression (`//nolint`)

- Write it as `//nolint`, with no space after `//`. A space turns it into an ordinary comment, and the linter no longer recognizes it as a suppression.
- Always specify the linter name: `//nolint:errcheck`, never bare `//nolint`.
- Always include a justification on the same line: `//nolint:errcheck // best-effort cleanup in defer`.
- Prefer fixing the code over suppressing the diagnostic. Suppression is a last resort when the linter is provably wrong or the fix would harm readability.
- Never suppress `govet` or `staticcheck` - those catch real bugs.

## Style

- **Identifiers** (exported and unexported): American English, matching stdlib conventions (`Initialize`, `Normalize`, `Color`). Never use British spelling in symbol names.
- **Prose** (comments, doc strings, error messages): American English for consistency (`initialize`, `normalize`, `behavior`).
- **Package comments** may span multiple paragraphs when the package is a major architectural component (see `encoding/json`, `net/http` in stdlib). Use judgement - breadth of the package justifies breadth of the doc.
- **Function and type comments** are one short paragraph plus at most one continuation paragraph. If more space is needed to describe the function, the function is doing too much - simplify before expanding the doc.
