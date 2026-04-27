# Integration Testing Protocol

Integration tests validate adapter behavior against real external services. They are separated from unit tests by file naming and environment gating.

> See SKILL.md → "Placeholders" for the meaning of `{PROJECT}` and `{integration}`. Substitute with the project's real names when applying these patterns.

## File Naming

Integration tests live in `integration_test.go` within the adapter package:

```
internal/tracker/{integration}/integration_test.go
internal/agent/{integration}/integration_test.go
```

## Environment Gates

Each adapter has its own gate variable. The test must skip — not fail — when the variable is absent.

| Adapter           | Gate Variable                  | Required Env Vars                                                                                       |
| ----------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `{integration}`   | `{PROJECT}_{INTEGRATION}_TEST=1` | `{PROJECT}_{INTEGRATION}_ENDPOINT`, `{PROJECT}_{INTEGRATION}_API_KEY`, plus any adapter-specific values |

Optional vars (e.g. `{PROJECT}_{INTEGRATION}_ACTIVE_STATES`) enhance coverage but must not cause failure when absent.

## Skip Helper Pattern

Every integration test file must define and use a skip helper. The example below uses literal sample names; rename `MYAPP` and `INTEGRATION` to fit the project being worked on:

```go
// Replace MYAPP with the project's env-var prefix and INTEGRATION
// with the adapter name (e.g. STRIPE, GITHUB, S3).
func skipUnlessIntegration(t *testing.T) {
    t.Helper()
    if os.Getenv("MYAPP_INTEGRATION_TEST") != "1" {
        t.Skip("skipping integration test: set MYAPP_INTEGRATION_TEST=1 to enable")
    }
}

func requireEnv(t *testing.T, key string) string {
    t.Helper()
    v := os.Getenv(key)
    if v == "" {
        t.Fatalf("required environment variable %s is not set", key)
    }
    return v
}
```

Call `skipUnlessIntegration(t)` as the first line of every integration test function. Call `requireEnv` only after the skip check passes.

## Config Builder

Build adapter config from env vars in a dedicated helper:

```go
// Rename MYAPP_INTEGRATION_* to the actual env-var names used by the project.
func integrationConfig(t *testing.T) map[string]any {
    t.Helper()
    endpoint := requireEnv(t, "MYAPP_INTEGRATION_ENDPOINT")
    apiKey := requireEnv(t, "MYAPP_INTEGRATION_API_KEY")
    project := requireEnv(t, "MYAPP_INTEGRATION_PROJECT")

    cfg := map[string]any{
        "endpoint": endpoint,
        "api_key":  apiKey,
        "project":  project,
    }
    // Add optional vars without fataling when absent.
    if states := os.Getenv("MYAPP_INTEGRATION_ACTIVE_STATES"); states != "" {
        // parse and add
    }
    return cfg
}
```

## Running Integration Tests

```bash
# Run integration tests for a specific adapter
{PROJECT}_{INTEGRATION}_TEST=1 make test PKG=./internal/tracker/{integration}/... RUN=Integration
```

## CI Behavior

- Without env vars: integration tests report as **skipped** (visible in output)
- With env vars: integration tests run and failures fail the job
- Integration tests never block the default `make test` pipeline

## Test Isolation

- Use isolated test identifiers and workspaces
- Clean up tracker artifacts when practical
- Do not rely on pre-existing external state — create what you need, verify, clean up

## Adding a New Integration Test Suite

When implementing a new adapter:

1. Create `integration_test.go` in the adapter package
2. Define `{PROJECT}_{INTEGRATION}_TEST` gate variable, substituting the real project prefix and adapter name
3. Implement `skipUnlessIntegration`, `requireEnv`, and config builder helpers
4. Document required env vars in the test file header comment
5. Add the run command to this reference doc
