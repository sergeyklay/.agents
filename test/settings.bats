# Repository values win settings merge conflicts. JSON merges skip existing
# host-local files when jq is unavailable.
load 'test_helper'

assert_disabled_once() {
  jq -e --arg skill "$1" \
    '[.skills.disabled[] | select(. == $skill)] | length == 1' \
    "$TEST_HOME/.gemini/settings.json" >/dev/null
}

assert_codex_settings() {
  python3 - "$1" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)

marketplace = config["marketplaces"]["diagram-design"]
assert marketplace["source_type"] == "git"
assert marketplace["source"] == "https://github.com/cathrynlavery/diagram-design.git"
assert config["model"] == "gpt-5.6-sol"
assert config["model_reasoning_effort"] == "high"
assert config["approval_policy"] == "never"
assert config["default_permissions"] == "full-access"
filesystem = config["permissions"]["full-access"]["filesystem"]
assert filesystem[":root"] == "read"
assert filesystem["~"] == "write"
assert filesystem[":slash_tmp"] == "write"
assert filesystem[":workspace_roots"][".env"] == "deny"
assert filesystem[":workspace_roots"]["**/.env"] == "deny"
assert config["permissions"]["full-access"]["network"]["enabled"] is True
mcp_servers = config["mcp_servers"]
assert set(mcp_servers) >= {"atlassian", "bpdb", "context7", "snyk"}
assert mcp_servers["atlassian"] == {"url": "https://mcp.atlassian.com/v2/mcp"}
assert mcp_servers["context7"] == {"url": "https://mcp.context7.com/mcp"}
assert mcp_servers["snyk"] == {
    "command": "npx",
    "args": ["-y", "snyk@1.1307.2", "mcp", "-t", "stdio"],
}
assert mcp_servers["bpdb"]["command"] == "sh"
assert mcp_servers["bpdb"]["args"] == [
    "-c",
    'exec "${CODEX_HOME:-$HOME/.codex}/mcp/bpdb/run.sh"',
]
assert "DATABASE_URL" in mcp_servers["bpdb"]["env_vars"]
assert config["plugins"]["diagram-design@diagram-design"]["enabled"] is True
assert config["tui"]["status_line"] == [
    "model",
    "context-used",
    "context-window-size",
    "five-hour-limit",
    "weekly-limit",
]
assert config["tui"]["status_line_use_colors"] is True
PY
}

@test "Claude settings deny .env reads" {
  run install_into --settings --claude
  [ "$status" -eq 0 ]
  jq -e '
    .permissions.defaultMode == "bypassPermissions" and
    (.permissions.deny | index("Read(**/.env)") != null) and
    (.permissions.deny | index("Read(**/.env.*)") == null)
  ' "$TEST_HOME/.claude/settings.json" >/dev/null
}

@test "Codex settings install native thread status visibility" {
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  config="$TEST_HOME/.codex/config.toml"
  assert_file "$config"
  assert_same "$ROOT/.codex/config.toml" "$config"
  assert_toml_parses "$config"
  assert_codex_settings "$config"
  assert_same "$ROOT/.codex/rules/default.rules" "$TEST_HOME/.codex/rules/default.rules"
  assert_same "$ROOT/.codex/mcp/bpdb/run.sh" "$TEST_HOME/.codex/mcp/bpdb/run.sh"
  [ -x "$TEST_HOME/.codex/mcp/bpdb/run.sh" ]
  assert_same "$ROOT/mcps/postgres.ts" "$TEST_HOME/.codex/mcp/bpdb/postgres.ts"

  cp "$config" "$BATS_TEST_TMPDIR/clean-config.toml"
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  assert_same "$BATS_TEST_TMPDIR/clean-config.toml" "$config"
}

@test "Codex settings replace the default policy and preserve other rules" {
  mkdir -p "$TEST_HOME/.codex/rules"
  printf 'stale default policy\n' >"$TEST_HOME/.codex/rules/default.rules"
  printf 'host-local rule\n' >"$TEST_HOME/.codex/rules/custom.rules"

  run install_into --settings --codex
  [ "$status" -eq 0 ]
  assert_same "$ROOT/.codex/rules/default.rules" "$TEST_HOME/.codex/rules/default.rules"
  assert_file_contains "$TEST_HOME/.codex/rules/custom.rules" 'host-local rule'
}

@test "Codex settings merge preserves host-local state" {
  cat >"$TEST_HOME/.codex/config.toml" <<'TOML'
model = "host-model"
model_reasoning_effort = "low"

[projects."/tmp/local-project"]
trust_level = "trusted"

[notice.model_migrations]
"old-model" = "new-model"

[permissions.host-local.filesystem]
"/host-only" = "read"

[mcp_servers.host-local]
command = "host-mcp"
args = ["serve"]

[marketplaces.diagram-design]
last_updated = "2026-09-15T16:53:24Z"
last_revision = "host-revision"
source_type = "directory"
source = "/tmp/host-plugin"

[plugins."diagram-design@diagram-design"]
enabled = false

[tui]
status_line = ["model-name"]

[tui.model_availability_nux]
"gpt-5.6-sol" = 4
TOML

  run install_into --settings --codex
  [ "$status" -eq 0 ]
  config="$TEST_HOME/.codex/config.toml"
  assert_toml_parses "$config"
  assert_codex_settings "$config"
  python3 - "$config" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)

assert config["model"] == "gpt-5.6-sol"
assert config["model_reasoning_effort"] == "high"
assert config["projects"]["/tmp/local-project"]["trust_level"] == "trusted"
assert config["notice"]["model_migrations"] == {"old-model": "new-model"}
assert config["permissions"]["host-local"]["filesystem"] == {"/host-only": "read"}
assert config["mcp_servers"]["host-local"] == {
    "command": "host-mcp",
    "args": ["serve"],
}
assert config["tui"]["model_availability_nux"] == {"gpt-5.6-sol": 4}
assert config["marketplaces"]["diagram-design"]["last_updated"] == "2026-09-15T16:53:24Z"
assert config["marketplaces"]["diagram-design"]["last_revision"] == "host-revision"
PY

  cp "$config" "$BATS_TEST_TMPDIR/expected-config.toml"
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  assert_same "$BATS_TEST_TMPDIR/expected-config.toml" "$config"
}

@test "Gemini settings merge preserves host-local keys" {
  printf '{"general": {"vimMode": true}}\n' >"$TEST_HOME/.gemini/settings.json"
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  # Under `default` a stage agent gets no write tool (measured on 0.58.0: 2 tools
  # against 4 under `auto_edit`) and the pipeline reports success writing nothing.
  # `general.defaultApprovalMode` is the only settings fix; `"yolo"` is discarded.
  jq -e '.general.defaultApprovalMode == "auto_edit"' \
    "$TEST_HOME/.gemini/settings.json" >/dev/null
  # The merge is a deep merge, so a host-local sibling key survives it.
  jq -e '.general.vimMode == true' "$TEST_HOME/.gemini/settings.json" >/dev/null
}

@test "Gemini settings merge unions skills.disabled and dedupes on reinstall" {
  printf '{"skills": {"disabled": ["host-only-skill", "scan-security"]}}\n' \
    >"$TEST_HOME/.gemini/settings.json"
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  assert_disabled_once host-only-skill
  assert_disabled_once scan-security

  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  assert_disabled_once host-only-skill
  assert_disabled_once scan-security
}

# A union here would strand a withdrawn `deny` rule; replacement is the revoke.
@test "the settings merge replaces an array with no union strategy" {
  printf '{"context": {"fileName": ["HOST.md"]}}\n' \
    >"$TEST_HOME/.gemini/settings.json"
  printf '{"permissions": {"deny": ["Read(**/.env.*)"]}}\n' \
    >"$TEST_HOME/.claude/settings.json"
  run install_into --settings --claude --gemini
  [ "$status" -eq 0 ]
  jq -e '.context.fileName | index("HOST.md") == null' \
    "$TEST_HOME/.gemini/settings.json" >/dev/null
  jq -e '.permissions.deny | index("Read(**/.env.*)") == null' \
    "$TEST_HOME/.claude/settings.json" >/dev/null
}

# The policy engine honors a singular `[[rule]]` table with a `decision`
# field; the plural table and the `action` field are discarded without
# diagnostic.
@test "Gemini policy uses the singular rule table" {
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  policy="$TEST_HOME/.gemini/policies/safe-commands.toml"
  assert_file_contains "$policy" '[[rule]]'
  assert_file_contains "$policy" 'decision ='
  if grep -q '^\[\[rules\]\]' "$policy"; then
    fail 'unexpected plural [[rules]] table in installed policy'
  fi
  if grep -q '^action[[:space:]]*=' "$policy"; then
    fail 'unexpected action key in installed policy'
  fi
}

# `buildArgsPatterns` prefix-anchors by concatenating `"command":"` with the
# pattern, so a top-level alternation anchors only its first branch (measured:
# `echo sudo hello` was denied). Every commandRegex must open with a group.
@test "every installed commandRegex anchors its alternation" {
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  policy="$TEST_HOME/.gemini/policies/safe-commands.toml"
  # The shape check below filters matching lines, so a missing key would pass
  # vacuously.
  if ! grep -q '^commandRegex = ' "$policy"; then
    fail 'no commandRegex in installed policy'
  fi
  if grep '^commandRegex = ' "$policy" | grep -qv '^commandRegex = "(?:'; then
    fail 'commandRegex without a leading group in installed policy'
  fi
}

# commandPrefix anchors each entry and appends a word boundary, keeping
# `sudo` off `sudoku`.
@test "dangerous commands are denied by whole-word prefix" {
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_HOME/.gemini/policies/safe-commands.toml" \
    'commandPrefix = ["sudo", "su", "shutdown", "reboot", "eval"]'
}

# The repo's .gemini/settings.json is the workspace scope for sessions in
# this repo, and workspace beats user: a `false` here disarms the agents and
# skills shipped into it. Both keys default to true, so absence is correct.
@test "the repository Gemini settings keep agents and skills enabled" {
  jq -e '.experimental.enableAgents != false' "$ROOT/.gemini/settings.json" >/dev/null
  jq -e '.skills.enabled != false' "$ROOT/.gemini/settings.json" >/dev/null
}

# settings.user.json was consolidated into settings.json, the same file the
# workspace scope reads; assert a key only the consolidated file carries.
@test "Gemini settings carry the consolidated-file keys" {
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  jq -e '.advanced.ignoreLocalEnv == true' "$TEST_HOME/.gemini/settings.json" >/dev/null
  jq -e '.skills.disabled | index("scan-security") != null' \
    "$TEST_HOME/.gemini/settings.json" >/dev/null
}

# The secrets policy has no install step of its own; it rides the policies rsync.
@test "the secrets policy is shipped" {
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_HOME/.gemini/policies/secrets.toml" 'decision = "deny"'
}

# Reading a key back out of a file this repository wrote proves only that it
# wrote it: on 0.58.0 an invented key merges with `errors: []` and nobody reads
# it (settings-validation.ts builds the settings object with `.passthrough()`).
settings_key_verdicts() {
  isolated_home "$NODE" "$ROOT/test/settings_keys.mjs" \
    "$BUNDLE" "$TEST_HOME/.gemini/settings.json" "$BATS_TEST_TMPDIR/workspace"
}

@test "every installed Gemini settings key is one the host acts on" {
  require_gemini
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  mkdir -p "$BATS_TEST_TMPDIR/workspace"

  run settings_key_verdicts
  [ "$status" -eq 0 ] || fail "the settings schema walk failed:
$output"

  # An all-`known` report of zero lines passes vacuously, and keyVerdicts yields
  # at least one line per top-level key, so the installed key count is a floor.
  local walked floor
  walked=$(printf '%s\n' "$output" | grep -c '^known') || true
  floor=$(jq 'keys | length' "$TEST_HOME/.gemini/settings.json")
  [ "$walked" -ge "$floor" ] ||
    fail "walked $walked key paths under $floor top-level keys:
$output"

  local unrecognized
  unrecognized=$(printf '%s\n' "$output" | grep -v '^known') || true
  [ -z "$unrecognized" ] || fail "the host acts on none of these:
$unrecognized"
}
