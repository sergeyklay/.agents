package example

import (
	"os"
	"testing"
)

func mustAdapter(t *testing.T, config map[string]any) *Adapter {
	t.Helper()
	a, err := NewAdapter(config)
	if err != nil {
		t.Fatalf("NewAdapter: %v", err)
	}
	return a.(*Adapter)
}

func validConfig(endpoint string) map[string]any {
	return map[string]any{
		"endpoint": endpoint,
	}
}

func loadFixture(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile("testdata/" + name)
	if err != nil {
		t.Fatalf("reading fixture %s: %v", name, err)
	}
	return data
}

func closeResource(t *testing.T, c interface{ Close() error }) {
	t.Helper()
	if err := c.Close(); err != nil {
		t.Errorf("Close: %v", err)
	}
}
