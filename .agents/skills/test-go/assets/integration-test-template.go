// Template for an env-gated integration test file. Drop into a new
// adapter package and rename:
//
//   - package name (`example` → the real package, e.g. `jira`, `stripe`)
//   - env-var prefix (`MYAPP` → the project's prefix, e.g. `ACME`)
//   - integration name (`INTEGRATION` → the adapter name, e.g. `STRIPE`,
//     `GITHUB`, `S3`)
//
// The placeholder names are deliberately uppercase / generic so the file
// compiles as-is; substitute everywhere they appear before committing.
package example

import (
	"os"
	"testing"
)

// skipUnlessIntegration skips the current test when the gate variable
// is not set to "1", so disabled integration tests are reported as
// skipped rather than silently passing.
func skipUnlessIntegration(t *testing.T) {
	t.Helper()
	if os.Getenv("MYAPP_INTEGRATION_TEST") != "1" {
		t.Skip("skipping integration test: set MYAPP_INTEGRATION_TEST=1 to enable")
	}
}

// requireEnv reads an environment variable and fails the test when empty.
func requireEnv(t *testing.T, key string) string {
	t.Helper()
	v := os.Getenv(key)
	if v == "" {
		t.Fatalf("required environment variable %s is not set", key)
	}
	return v
}

// integrationConfig builds the adapter config map from environment variables.
// Replace the env-var keys (MYAPP_INTEGRATION_*) with the project's actual names.
func integrationConfig(t *testing.T) map[string]any {
	t.Helper()
	return map[string]any{
		// TODO: populate from requireEnv calls, e.g.
		//   "endpoint": requireEnv(t, "MYAPP_INTEGRATION_ENDPOINT"),
		//   "api_key":  requireEnv(t, "MYAPP_INTEGRATION_API_KEY"),
	}
}

func TestIntegration_SmokeFetch(t *testing.T) {
	skipUnlessIntegration(t)

	cfg := integrationConfig(t)
	_ = cfg
	// TODO: create adapter, exercise a basic operation, assert on result
}
