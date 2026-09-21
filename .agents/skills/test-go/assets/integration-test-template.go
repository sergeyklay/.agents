package example

import (
	"context"
	"os"
	"testing"
)

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

func integrationConfig(t *testing.T) map[string]any {
	t.Helper()
	return map[string]any{
		"endpoint": requireEnv(t, "MYAPP_INTEGRATION_ENDPOINT"),
		"api_key":  requireEnv(t, "MYAPP_INTEGRATION_API_KEY"),
	}
}

func TestIntegration_SmokeFetch(t *testing.T) {
	skipUnlessIntegration(t)

	adapter := mustAdapter(t, integrationConfig(t))
	if _, err := adapter.FetchIssuesByStates(context.Background(), []string{"To Do"}); err != nil {
		t.Fatalf("FetchIssuesByStates: %v", err)
	}
}
