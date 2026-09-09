
# Go Code Style

This file covers naming, comment structure, control flow, and Go idioms. For godoc and exported symbol comments see that file; for structured logging see Go Structured Logging instructions.

## Inline Comment Structure

Never prefix inline comments with labels, sequence numbers, or hierarchical markers. Write the comment content directly.

```go
// ❌ Labeled - the number is noise; the reason is what matters.
// Rule 1: required fields.
if issue.ID == "" || issue.Identifier == "" {
    return false
}

// ❌ Step / Section / Phase / Check variants.
// Step 1: dispatch preflight validation.
validation := ValidateDispatchConfig(params)

// ❌ Bare numeric prefixes.
// 1. Session started.
// 2. First token usage.
```

```go
// ✅ Reason first - state the invariant or constraint being enforced.
// Issues with missing required fields are not eligible for dispatch.
if issue.ID == "" || issue.Identifier == "" {
    return false
}

// ✅ Describe what validation accomplishes, not its sequence position.
// Preflight triggers a defensive Reload() so the config snapshot below
// reflects the latest disk state.
validation := ValidateDispatchConfig(params)
```

The label (`Rule 4:`, `Step 2:`, `Section 3.5:`) carries no information the code does not already provide. A reader following the code does not need a counter; they need the **reason** for the guard.

**Prohibited patterns:**

| Pattern | Examples |
|---|---|
| Rule labels | `// Rule N:`, `// Rule Nb:` |
| Step labels | `// Step N:`, `// Step N.N:` |
| Section labels | `// Section N.N:` |
| Bare numbers | `// N.`, `// N:`, `// 1.`, `// 2.` |
| Phase / Check | `// Phase N:`, `// Check N:` |

When a sequence genuinely matters (e.g., a three-phase commit), use a prose description of *what* each phase does rather than numbering it.

### No Internal References in Comments

Never cite `docs/architecture.md`, `docs/decisions/`, section numbers, ADR numbers, or internal project tracker tickets (e.g., `SORT-42`) in any comment. Source files must stand alone; internal references create maintenance debt and break when documents are reorganized or the tracker migrates.

Upstream external references - Go issue tracker (`golang/go#NNNNN`), GitHub issues in third-party repos, RFC numbers, CVE IDs - are permitted when they explain a non-obvious workaround or constraint that cannot be fully described in prose alone. The reference must accompany an explanation, not replace it.

```go
// ❌ Section reference - useless if the doc is renamed or restructured.
// Section 3.4: continuation turns must produce shorter output than first turns.
if turn > 1 && len(output) >= len(prev) {

// ❌ ADR reference - meaningless to someone reading the code cold.
// ADR-0003: use modernc.org/sqlite to avoid CGo.
db, err := sql.Open("sqlite", path)

// ❌ Internal ticket - rots when the tracker migrates.
// SORT-42: workaround for upstream pagination off-by-one.
offset := 0

// ❌ Upstream reference with no explanation - the link alone is useless.
// golang/go#22315
n := runtime.NumCPU()

// ✅ State the invariant directly - no internal document required.
// Continuation turns must be shorter than the first turn; longer output
// indicates the model is re-summarizing instead of continuing.
if turn > 1 && len(output) >= len(prev) {

// ✅ Name the constraint in the code itself.
// modernc.org/sqlite is the only permitted SQLite driver - CGo breaks
// the single-binary zero-dependency deployment model.
db, err := sql.Open("sqlite", path)

// ✅ Describe the workaround and cite the upstream root cause.
// Upstream pagination returns one extra item on the last page; discard
// the duplicate on receipt.
offset := 0

// ✅ Upstream reference paired with an explanation.
// strings.Clone forces a heap allocation so the GC can collect the
// original large buffer; without it the substring pins the whole input.
// See golang/go#40200 for the compiler limitation that makes this necessary.
s = strings.Clone(large[:n])
```

### Rewrite the Code Instead of Explaining It

A comment needed to explain what a block inside a function does is a symptom of unclear code, not a documentation gap. Clear is better than clever: if the code requires prose to be understood, rewrite the code rather than add the prose. Extract the block into a function with a name that states its purpose, rename the variables that raised the question, remove nesting with an early return, or split a function that has grown too long. When in doubt, ask whether this comment would appear in `net/http`.

```go
// ❌ The comment carries meaning the code should carry itself.
// Only allow the request through if the user is authenticated and has
// not exceeded their quota for the current billing period.
if u.Authenticated && u.RequestCount < u.Quota && time.Now().Before(u.QuotaResetAt) {
    allow(u)
}

// ✅ The function name carries the meaning; no comment is needed.
if canProceed(u) {
    allow(u)
}
```

### What Inline Comments May Explain

An inline comment inside a function body is warranted only for something the code cannot say on its own:

- Why a specific algorithm was chosen, or why a simpler one does not work.
- A workaround for a bug in a dependency, the runtime, or a protocol - see "No Internal References in Comments" above for how to cite the upstream source.
- A business constraint or specification requirement - external references only, per the same section.
- A concurrency invariant: what a mutex protects, the order locks must be acquired in, which goroutine owns a channel, or who closes it.
- A non-obvious consequence: an allocation on a hot path, a required call order, or a context cancellation requirement.

Struct fields protected by a mutex follow the standard library convention of naming the guard in a trailing comment:

```go
type pool struct {
    mu    sync.Mutex
    conns map[string]*conn // guarded by mu
}
```

### Other Prohibited Comment Patterns

| Pattern | Examples |
|---|---|
| Commented-out code | `// count := oldCounter()` |
| Name-duplicating comment | `// Name is the name.` |
| Banner or frame decoration | `// ========`, `/* **** Validation **** */` |
| Bare TODO | `// TODO` with no owner or issue |
| Apology comment | `// hack`, `// this is ugly but works` |

Git preserves history, so delete code instead of commenting it out. A name-duplicating comment adds nothing a reader could not already see. Banners and hand-aligned columns are not something gofmt formats, and the reader does not need the decoration. A bare `TODO` has no owner and no way to know if it is still relevant - use `// TODO(username): description` or link an issue. An apology comment admits a problem without fixing it; either fix the code or cite the real constraint.

### Compiler Directives Are Not Comments

`//go:generate`, `//go:embed`, and `//go:build` are instructions to the toolchain, not comments for the reader. Write them with no space after `//`, and separate them from any doc comment above with a blank line so they do not become part of the rendered documentation.

```go
// ❌ Space after // and no blank line: not recognized as a directive, and
// it renders as part of the doc comment on pkg.go.dev.
// Client wraps the upstream API.
// go:generate mockgen -source=client.go -destination=mock_client.go
type Client struct{}

// ✅ No space after //, and a blank line keeps it out of the doc comment.
// Client wraps the upstream API.

//go:generate mockgen -source=client.go -destination=mock_client.go
type Client struct{}
```

`//go:build` carries a second meaning the other two do not: it decides which platforms compile the file at all. Put only platform-dependent code behind a tag and move everything else into an untagged file. Code sharing a tagged file is absent from the excluded builds rather than skipped in them, so those builds report neither a failure nor a skip.

```go
// ❌ One tag over the whole file. On Windows the key sanitizer's test is
// not built, and nothing in the "go test" output says so.
// workspace_test.go
//go:build unix

func TestSymlinkResolution(t *testing.T) { ... }
func TestSanitizeKey(t *testing.T)       { ... }

// ✅ Only what depends on the platform sits behind the tag. The tag line
// does that work, not the name: "unix" is a build tag and no GOOS, so a
// "_unix.go" suffix constrains nothing, while "_windows.go" does.
// workspace_unix_test.go
//go:build unix

func TestSymlinkResolution(t *testing.T) { ... }

// ✅ No tag, so every platform runs it.
// workspace_test.go
func TestSanitizeKey(t *testing.T) { ... }
```

## Naming

### Variables

Prefer names proportional to scope. Short names (`i`, `err`, `ok`, `n`, `id`) are appropriate inside short blocks. Use longer names at package scope or when a short name would be ambiguous.

Never use `data`, `info`, `val`, `item`, `obj`, or `result` as variable names. Name the thing.

```go
// ❌ Generic - tells nothing about what is being iterated or processed.
for _, item := range issues {
    data := fetch(item)
}

// ✅ Names match domain vocabulary.
for _, issue := range issues {
    detail, err := fetch(issue.ID)
}
```

### Acronyms

Treat acronyms as words in mixed-case identifiers, consistent with the Go standard library:

```go
// ✅ Correct.
issueID    string
sessionID  string
apiURL     string
httpClient *http.Client

// ❌ Incorrect - breaks Go stdlib convention.
issueId    string
sessionId  string
apiUrl     string
httpClient *http.Client // Http instead of HTTP
```

### Booleans

Name booleans as affirmative predicates. Negative names produce double negations in conditions.

```go
// ✅ Readable in conditions: if isRunning { ... }
var isRunning bool
var hasAvailableSlots bool

// ❌ Produces double negation: if !notRunning { ... }
var notRunning bool
var noSlotsAvailable bool
```

## Control Flow

### Early Return

Return (or `continue`) at guard clauses and error conditions. Do not nest the happy path inside conditionals.

```go
// ❌ Nested happy path - every guard adds one indentation level.
func process(issue domain.Issue) error {
    if issue.ID != "" {
        if !state.IsRunning(issue.ID) {
            return dispatch(issue)
        }
    }
    return nil
}

// ✅ Flat - guards are at the top, happy path at the bottom.
func process(issue domain.Issue) error {
    if issue.ID == "" {
        return nil
    }
    if state.IsRunning(issue.ID) {
        return nil
    }
    return dispatch(issue)
}
```

### No Else After Return

When an `if` block ends with `return`, `continue`, or `break`, the `else` clause is unnecessary.

```go
// ❌ Redundant else.
if err != nil {
    return err
} else {
    doWork()
}

// ✅ Flat.
if err != nil {
    return err
}
doWork()
```

### Switch Over Long If-Else Chains

Use `switch` when comparing a single expression against three or more values.

```go
// ❌ Chain - hard to scan.
if state == "open" {
    ...
} else if state == "in_progress" {
    ...
} else if state == "done" {
    ...
}

// ✅ Switch - each case aligns.
switch state {
case "open":
    ...
case "in_progress":
    ...
case "done":
    ...
}
```

## Error Messages

Error strings are lowercase with no trailing punctuation. Callers wrap them; the chain reads left-to-right.

```go
// ✅ Lowercase, no period.
fmt.Errorf("failed to open workspace: %w", err)
fmt.Errorf("issue %s not found", id)

// ❌ Capital letter or trailing punctuation - breaks wrapping.
fmt.Errorf("Failed to open workspace: %w", err)
fmt.Errorf("issue %s not found.", id)
```

Include the resource identifier being operated on so the wrapped chain is useful:

```go
// ✅ Caller can identify which workspace and why it failed.
fmt.Errorf("prepare workspace for issue %s: %w", issue.ID, err)

// ❌ No context - caller cannot tell which workspace.
fmt.Errorf("prepare workspace: %w", err)
```

## Struct Initialization

Initialize only non-zero fields. Explicitly setting zero values adds noise and implies they were chosen deliberately when they were not.

```go
// ✅ Only meaningful fields - intent is unambiguous.
entry := RunningEntry{
    Identifier: issue.Identifier,
    StartedAt:  time.Now(),
}

// ❌ Redundant zero values - reader must verify these are intentional.
entry := RunningEntry{
    Identifier: issue.Identifier,
    SessionID:  "",
    StartedAt:  time.Now(),
    ExitCode:   0,
}
```

Use field names in any literal whose struct has two fields of the same type, adjacent or not. A positional literal binds values by position alone, so swapping two same-type values compiles and changes meaning in silence.

Nothing mechanical catches it. `go vet`'s `composites` analyzer exempts anonymous structs, which is the usual table-test shape, and every type declared in the package under analysis, counting that package's external `_test` package as the same package. `go test` does not run `composites` at all.

```go
// ❌ Positional - Name, Headers and Body are all strings, so any two of
// them swap without a complaint from the compiler or from vet.
cases := []Reply{
    {"json payload", 200, "Content-Type: application/json", "{}"},
}

// ✅ Named - the pairing is stated rather than inferred from position.
cases := []Reply{
    {
        Name:    "json payload",
        Status:  200,
        Headers: "Content-Type: application/json",
        Body:    "{}",
    },
}
```

Table-driven test cases are where this costs most, because a case that still passes after a silent swap has stopped testing what its name claims. The rule is about the hazard rather than the location: it applies wherever a struct has two fields of one type.

## Type Assertions

Always use the two-result form in production code. The single-result form panics on type mismatch.

```go
// ✅ Safe.
v, ok := x.(SomeInterface)
if !ok {
    return fmt.Errorf("unexpected type %T for x", x)
}

// ❌ Panics if x is not SomeInterface.
v := x.(SomeInterface)
```

Exception: inside a `switch x.(type)` block, single-result assertions on case branches are idiomatic and safe.

## Imports

Group imports into three blocks separated by blank lines: stdlib, external modules, internal packages. `goimports` enforces this automatically via `make fmt`.

```go
import (
    "context"
    "fmt"
    "time"

    "golang.org/x/sync/errgroup"

    "example.com/project/internal/domain"
    "example.com/project/internal/logging"
)
```

Never use dot imports (`. "pkg"`). Never use blank imports (`_ "pkg"`) in non-`main` packages without a comment explaining the side effect being triggered.

## Go 1.22+ Idioms

This project targets Go 1.26. Use the modern forms below; without explicit instruction, Copilot defaults to pre-1.22 patterns.

### Loop variable scoping

Go 1.22 gives each loop iteration its own copy of the loop variables. The `v := v` shadowing workaround is no longer needed and should not be written.

```go
// ❌ Stale - unnecessary and misleading since Go 1.22.
for _, url := range urls {
    url := url
    go func() { fetch(url) }()
}

// ✅ Correct in Go 1.22+.
for _, url := range urls {
    go func() { fetch(url) }()
}
```

### Range over integers

```go
// ❌ C-style three-clause loop.
for i := 0; i < n; i++ { ... }

// ✅ Go 1.22+.
for i := range n { ... }
```

### Built-in `min` and `max`

Never write helper functions for min/max. The builtins accept any ordered type and two or more arguments.

```go
// ❌ Unnecessary helper.
func maxInt(a, b int) int { if a > b { return a }; return b }

// ✅ Built-in since Go 1.21.
hi := max(a, b)
clamped := max(lo, min(hi, v))
```

### `slices` and `maps` packages

Use the standard-library `slices` and `maps` packages for collection operations. Do not write helpers that duplicate their functionality.

```go
import ("maps"; "slices")

// ❌ Hand-rolled contains check and sort.
found := false
for _, v := range allowed { if v == role { found = true; break } }
sort.Slice(users, func(i, j int) bool { return users[i].Name < users[j].Name })

// ✅ slices/maps equivalents.
found := slices.Contains(allowed, role)
slices.SortFunc(users, func(a, b User) int { return cmp.Compare(a.Name, b.Name) })
for k, v := range slices.Sorted(maps.All(m)) { ... } // sorted map iteration
```

### `strings.Cut`

Use `strings.Cut` to split a string on a delimiter. Do not use `strings.SplitN(s, sep, 2)`.

```go
// ❌ SplitN - does not signal whether the delimiter was found.
parts := strings.SplitN(line, "=", 2)
key, value := parts[0], parts[1]

// ✅ Cut - returns a found flag and handles the missing-delimiter case cleanly.
key, value, ok := strings.Cut(line, "=")
if !ok { ... }
```

### `cmp.Or` for fallback chains

```go
// ❌ Verbose if-chain.
name := envName
if name == "" { name = configName }
if name == "" { name = "default" }

// ✅ cmp.Or returns the first non-zero value.
name := cmp.Or(envName, configName, "default")
```
