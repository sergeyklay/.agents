load 'test_helper'

isolated_codex() {
  isolated_home env CODEX_HOME="$TEST_HOME/.codex" "$@"
}

teardown() {
  if [ -n "${HTTP_SERVER_PID:-}" ]; then
    kill "$HTTP_SERVER_PID" 2>/dev/null || true
    wait "$HTTP_SERVER_PID" 2>/dev/null || true
  fi
}

require_codex() {
  CODEX=$(command -v codex 2>/dev/null) || {
    if [ -n "${CI:-}" ]; then
      fail 'no Codex CLI on PATH; CI must install the pinned host under test'
    fi
    skip 'no Codex CLI on PATH; runtime Codex checks did not run'
  }
  run "$CODEX" --version
  [ "$status" -eq 0 ]
  if [ "$output" != 'codex-cli 0.154.0' ]; then
    if [ -n "${CI:-}" ]; then
      fail "expected codex-cli 0.154.0, found: $output"
    fi
    skip "expected codex-cli 0.154.0, found: $output; runtime checks did not run"
  fi
  PYTHON=$(python3 -c 'import sys; print(sys.executable)')
}

assert_permission_probe_available() {
  case $output in
  *'synthetic bubblewrap mount registry'*) blocked=1 ;;
  *) blocked=0 ;;
  esac
  if [ "$status" -eq 101 ] && [ "$blocked" -eq 1 ]; then
    if [ -n "${CI:-}" ]; then
      fail "nested Codex sandbox unavailable in unconfined CI:\n$output"
    fi
    skip "outer sandbox blocks nested Codex bubblewrap; runtime permission result is unrun:\n$output"
  fi
}

run_model_command() {
  isolated_codex "$PYTHON" "$ROOT/test/codex_mcp_probe.py" command "$CODEX" "$@"
}

start_http_server() {
  HTTP_PORT_FILE="$BATS_TEST_TMPDIR/http-port"
  python3 - "$HTTP_PORT_FILE" <<'PY' &
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"network-sentinel\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w", encoding="utf-8") as port_file:
    port_file.write(str(server.server_port))
server.serve_forever()
PY
  HTTP_SERVER_PID=$!
  export HTTP_SERVER_PID
  attempt=0
  while [ "$attempt" -lt 50 ]; do
    [ -s "$HTTP_PORT_FILE" ] && break
    sleep 0.1
    attempt=$((attempt + 1))
  done
  [ -s "$HTTP_PORT_FILE" ] || fail 'local HTTP server did not publish its port'
  HTTP_PORT=$(cat "$HTTP_PORT_FILE")
}

run_network_read() {
  isolated_codex "$CODEX" sandbox -P full-access -C "$1" -- \
    "$PYTHON" -c 'import sys, urllib.request; print(urllib.request.urlopen(sys.argv[1], timeout=5).read().decode())' \
    "http://127.0.0.1:$HTTP_PORT/"
}

list_installed_mcp() {
  (
    cd "$1" || return 1
    isolated_codex "$CODEX" mcp list --json
  )
}

assert_required_mcp_names() {
  python3 - "$1" "$ROOT/.claude/settings.json" <<'PY'
import json
import re
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
with open(sys.argv[2], encoding="utf-8") as settings_file:
    claude = json.load(settings_file)

allowed = claude["permissions"]["allow"]
allowed_servers = {
    match.group(1)
    for item in allowed
    if (match := re.fullmatch(r"mcp__([a-z0-9-]+)__\*", item))
}
expected = {"atlassian", "context7", "snyk"}
assert expected <= allowed_servers
assert set(config["mcp_servers"]) == expected
PY
}

@test "a weakened Codex dotenv guard permits the protected read" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace"
  printf '%s\n' 'dotenv-negative-control' >"$workspace/.env"

  python3 - "$TEST_HOME/.codex/config.toml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = path.read_text(encoding="utf-8")
replacements = {
    ".env": '".env" = "read"',
    "**/.env": '"**/.env-disabled" = "deny"',
}
for pattern, replacement in replacements.items():
    old = f'"{pattern}" = "deny"'
    assert config.count(old) == 1
    config = config.replace(old, replacement)
path.write_text(config, encoding="utf-8")
PY
  assert_file_contains "$TEST_HOME/.codex/config.toml" '".env" = "read"'
  assert_file_contains "$TEST_HOME/.codex/config.toml" '"**/.env-disabled" = "deny"'

  run run_model_command "$workspace" 'cat .env'
  assert_permission_probe_available
  [ "$status" -eq 0 ]
  assert_contains "$output" 'Process exited with code 0'
  assert_contains "$output" 'dotenv-negative-control'
}

@test "a disabled Codex network profile blocks the local probe" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace"
  start_http_server

  python3 - "$TEST_HOME/.codex/config.toml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = path.read_text(encoding="utf-8")
old = "[permissions.full-access.network]\nenabled = true"
assert config.count(old) == 1
path.write_text(config.replace(old, old.replace("true", "false")), encoding="utf-8")
PY
  assert_file_contains "$TEST_HOME/.codex/config.toml" '[permissions.full-access.network]'
  assert_file_contains "$TEST_HOME/.codex/config.toml" 'enabled = false'
  run run_network_read "$workspace"
  assert_permission_probe_available
  [ "$status" -ne 0 ]
  assert_contains "$output" 'Operation not permitted'
  assert_not_contains "$output" 'network-sentinel'
}

@test "a weakened Codex execpolicy rule permits the model command" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  weakened="$TEST_HOME/.codex/rules/default.rules"
  perl -0pi -e 's/(pattern = \["shutdown"\],\n    decision = ")forbidden(".*?shutdown is explicitly prohibited)/${1}allow${2}/s' "$weakened"
  assert_file_contains "$weakened" 'decision = "allow"'

  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace"
  run run_model_command "$workspace" 'shutdown --help'
  [ "$status" -eq 0 ]
  assert_contains "$output" 'Process exited with code 0'
  assert_contains "$output" 'shutdown [OPTIONS...]'
}

@test "an interactive Codex approval policy reaches the approval path" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  python3 - "$TEST_HOME/.codex/config.toml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = path.read_text(encoding="utf-8")
old = 'approval_policy = "never"'
assert config.count(old) == 1
path.write_text(config.replace(old, 'approval_policy = "on-request"'), encoding="utf-8")
PY
  assert_file_contains "$TEST_HOME/.codex/config.toml" 'approval_policy = "on-request"'
  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace"
  run run_model_command "$workspace" 'printf approval-policy-probe' --escalate --expect-approval
  [ "$status" -eq 0 ]
  assert_contains "$output" 'approval_requests=1'
  assert_contains "$output" 'turn_completed=false'
}

@test "the MCP name check rejects a renamed required server" {
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  config="$TEST_HOME/.codex/config.toml"
  python3 - "$config" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
content = path.read_text(encoding="utf-8")
old = "[mcp_servers.context7]"
assert content.count(old) == 1
path.write_text(content.replace(old, "[mcp_servers.context-seven]"), encoding="utf-8")
PY
  assert_file_contains "$config" '[mcp_servers.context-seven]'

  run assert_required_mcp_names "$config"
  [ "$status" -ne 0 ]
}

@test "Codex settings install the required MCP server names" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  assert_required_mcp_names "$TEST_HOME/.codex/config.toml"

  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace"
  run list_installed_mcp "$workspace"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c '
import json
import sys

payload = "\n".join(line for line in sys.stdin if not line.startswith("WARNING:"))
servers = json.loads(payload)
assert {server["name"] for server in servers} == {"atlassian", "context7", "snyk"}
'
}

@test "Codex runtime ignores an inherited CODEX_HOME" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  foreign="$BATS_TEST_TMPDIR/foreign-codex"
  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$foreign" "$workspace"
  printf 'invalid config sentinel\n' >"$foreign/config.toml"
  cp "$foreign/config.toml" "$BATS_TEST_TMPDIR/foreign-original.toml"

  CODEX_HOME="$foreign" run list_installed_mcp "$workspace"
  [ "$status" -eq 0 ]
  assert_contains "$output" 'context7'
  assert_same "$BATS_TEST_TMPDIR/foreign-original.toml" "$foreign/config.toml"
  [ "$(ls -A "$foreign")" = config.toml ]
}

@test "Codex permits ordinary reads and denies dotenv reads" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace"
  printf '%s\n' 'ordinary-operation' >"$workspace/ordinary.txt"
  printf '%s\n' 'dotenv-must-not-escape' >"$workspace/.env"

  run run_model_command "$workspace" 'cat ordinary.txt'
  assert_permission_probe_available
  [ "$status" -eq 0 ]
  assert_contains "$output" 'Process exited with code 0'
  assert_contains "$output" 'ordinary-operation'

  run run_model_command "$workspace" 'cat .env'
  [ "$status" -eq 0 ]
  assert_contains "$output" 'Process exited with code 1'
  assert_contains "$output" 'Permission denied'
  assert_not_contains "$output" 'dotenv-must-not-escape'
}

@test "Codex permits network access through the installed profile" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace"
  start_http_server

  run run_network_read "$workspace"
  assert_permission_probe_available
  [ "$status" -eq 0 ]
  assert_contains "$output" 'network-sentinel'
}

@test "Codex rejects the model command through automatically loaded rules" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace"
  run run_model_command "$workspace" 'shutdown --help'
  [ "$status" -eq 0 ]
  assert_contains "$output" 'shutdown is explicitly prohibited'
  assert_not_contains "$output" 'Process exited with code 0'
  assert_contains "$output" 'approval_requests=0'
}

@test "Codex execpolicy matches every prohibited prefix" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  for command in sudo su shutdown reboot rm; do
    if [ "$command" = rm ]; then
      set -- rm -rf /
    else
      set -- "$command" --help
    fi
    run isolated_codex "$CODEX" execpolicy check \
      --rules "$TEST_HOME/.codex/rules/default.rules" -- "$@"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | python3 -c '
import json
import sys

lines = [line for line in sys.stdin if line.startswith("{")]
assert json.loads(lines[-1])["decision"] == "forbidden"
'
  done
}

@test "Codex calls an MCP sentinel only after installer transport" {
  require_codex
  workspace="$BATS_TEST_TMPDIR/workspace"
  sentinel_log="$BATS_TEST_TMPDIR/sentinel.log"
  mkdir -p "$workspace"

  run isolated_codex "$PYTHON" "$ROOT/test/codex_mcp_probe.py" \
    call "$CODEX" "$workspace" sentinel pre-install-sentinel
  [ "$status" -ne 0 ]
  assert_contains "$output" "unknown MCP server 'sentinel'"
  assert_absent "$sentinel_log"

  fixture="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$fixture/.codex/rules"
  cp -R "$ROOT/scripts" "$fixture/scripts"
  cp "$ROOT/.codex/rules/default.rules" "$fixture/.codex/rules/default.rules"
  cat >"$fixture/.codex/config.toml" <<TOML
approval_policy = "never"

[mcp_servers.sentinel]
command = "$PYTHON"
args = ["$ROOT/test/codex_mcp_probe.py", "serve", "$sentinel_log"]
required = true
TOML
  run install_from "$fixture" --settings --codex
  [ "$status" -eq 0 ]

  run list_installed_mcp "$workspace"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c '
import json
import sys

payload = "\n".join(line for line in sys.stdin if not line.startswith("WARNING:"))
servers = json.loads(payload)
assert [server["name"] for server in servers] == ["sentinel"]
'

  run isolated_codex "$PYTHON" "$ROOT/test/codex_mcp_probe.py" \
    call "$CODEX" "$workspace" sentinel post-install-sentinel
  [ "$status" -eq 0 ]
  assert_contains "$output" 'post-install-sentinel'
  assert_file_contains "$sentinel_log" 'post-install-sentinel'
}

@test "Codex applies the installed noninteractive approval policy" {
  require_codex
  run install_into --settings --codex
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_HOME/.codex/config.toml" 'approval_policy = "never"'
  workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$workspace"

  cp "$TEST_HOME/.codex/config.toml" "$BATS_TEST_TMPDIR/installed-config.toml"
  run run_model_command "$workspace" 'printf approval-policy-probe'
  [ "$status" -eq 0 ]
  assert_contains "$output" 'approval_requests=0'
  assert_contains "$output" 'turn_completed=true'
  assert_contains "$output" 'Process exited with code 0'
  assert_contains "$output" 'approval-policy-probe'

  run run_model_command "$workspace" 'printf approval-policy-probe' --escalate
  [ "$status" -eq 0 ]
  assert_contains "$output" 'approval_requests=0'
  assert_contains "$output" 'turn_completed=true'
  assert_contains "$output" 'approval policy is Never'
  assert_not_contains "$output" 'Process exited with code 0'
  assert_same "$BATS_TEST_TMPDIR/installed-config.toml" "$TEST_HOME/.codex/config.toml"
}
