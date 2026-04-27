// Template for adapter test helpers. Drop into a new package and rename:
//
//   - package name (`example` → the real package, e.g. `jira`, `stripe`)
//   - adapter type (`Adapter`, `NewAdapter` → the concrete type from your
//     package, e.g. `JiraAdapter` / `NewJiraAdapter`)
//
// The placeholder names compile as-is; substitute them everywhere they
// appear before committing.
package example

import (
	"os"
	"testing"
)

// mustAdapter creates a configured adapter or fatals the test.
func mustAdapter(t *testing.T, config map[string]any) *Adapter {
	t.Helper()
	a, err := NewAdapter(config)
	if err != nil {
		t.Fatalf("NewAdapter: %v", err)
	}
	return a.(*Adapter)
}

// validConfig returns a baseline valid config. Tests override specific fields.
func validConfig(endpoint string) map[string]any {
	return map[string]any{
		// TODO: fill in required fields with sensible test defaults
	}
}

// loadFixture reads a file from the package's testdata/ directory.
func loadFixture(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile("testdata/" + name)
	if err != nil {
		t.Fatalf("reading fixture %s: %v", name, err)
	}
	return data
}

// closeResource closes a resource and reports errors without fataling.
func closeResource(t *testing.T, c interface{ Close() error }) {
	t.Helper()
	if err := c.Close(); err != nil {
		t.Errorf("Close: %v", err)
	}
}
