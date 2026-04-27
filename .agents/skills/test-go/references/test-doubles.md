# Test Doubles

This project avoids external mocking frameworks. Test doubles are hand-written implementations of domain interfaces, ranging from zero-behavior stubs to registered fake adapters.

> See SKILL.md → "Placeholders" for the meaning of `{integration}` used below. Substitute with the project's real adapter name when applying these patterns.

## Hierarchy

Use the lightest double that validates the behavior under test.

### 1. Compile-Time Interface Check (Zero-Cost)

Proves a type satisfies an interface at compile time. Place in `_test.go`:

```go
var _ domain.TrackerAdapter = (*mockTrackerAdapter)(nil)
var _ domain.AgentAdapter = (*mockAgentAdapter)(nil)
```

### 2. Stub (Fixed Returns)

Minimal implementation returning hardcoded values. Use for tests where the double's behavior is irrelevant to the assertion.

```go
type stubTracker struct{}

func (s *stubTracker) FetchIssuesByStates(_ context.Context, _ []string) ([]domain.Issue, error) {
    return nil, nil
}
// ... all interface methods return zero values
```

### 3. Fake (Working Implementation)

Simplified but functional implementation. Projects following this pattern typically register one or more first-class fakes in the adapter registry — for example:

- A file-backed tracker fake (`internal/tracker/file/` or similar) that reads issues from JSON fixtures on disk and registers under a name like `"file"`.
- A mock agent fake (`internal/agent/mock/` or similar) that generates configurable canned events and registers under a name like `"mock"`. Make it thread-safe via mutex.

Check the actual project layout for the real package paths and registry names. A configurable mock agent fake typically accepts:
- `session_id`, `agent_pid` — identity
- `start_error` — simulate launch failure
- `turn_outcomes` — sequence of outcomes per turn
- `events_per_turn`, `input_tokens_per_turn`, `output_tokens_per_turn` — load simulation
- `turn_delay_ms` — timing simulation
- `stop_error` — simulate stop failure

### 4. Spy (Interaction Recording)

Use `httptest.NewServer` handlers with `atomic` counters or captured request data:

```go
var callCount int64
srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    atomic.AddInt64(&callCount, 1)
    // capture r.URL.Query(), r.Header, etc.
    w.Write(loadFixture(t, "response.json"))
}))
```

## Naming Conventions

| Prefix | Meaning | Behavior |
|---|---|---|
| `mock*` | Minimal stub implementing an interface | Zero or fixed returns |
| `stub*` | Returns predetermined data | Fixed returns, no logic |
| `spy*` | Records calls for later assertion | Captures inputs |
| `fake*` | Working simplified implementation | Has real logic |

In practice, this project uses `mock` as the common prefix for simple stubs in domain test files. The registered fakes use their adapter kind name (`"mock"`, `"file"`).

## Default Parameter Builders

Tests that create domain objects repeatedly should define a builder helper:

```go
func defaultParams() domain.RunTurnParams {
    return domain.RunTurnParams{
        Prompt:    "test prompt",
        SessionID: "sess-001",
        // ... all required fields with sensible defaults
    }
}
```

Callers override only the fields relevant to their test case.
