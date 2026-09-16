load 'test_helper'

assert_codex_role() {
  python3 - "$1" "$2" <<'PY'
import json
import pathlib
import sys
import tomllib

role_path, source_path = (pathlib.Path(value) for value in sys.argv[1:])
payload = role_path.read_bytes()
assert not payload.startswith(b"#")
lines = source_path.read_text().splitlines(keepends=True)
closing = next(index for index, line in enumerate(lines[1:], 1) if line.rstrip("\n") == "---")
frontmatter = {}
for line in lines[1:closing]:
    key, value = line.split(":", 1)
    frontmatter[key] = json.loads(value.strip()) if value.strip().startswith('"') else value.strip()
assert tomllib.loads(payload.decode()) == {
    "name": frontmatter["name"],
    "description": frontmatter["description"],
    "developer_instructions": "".join(lines[closing + 1:]),
}
PY
}

copy_repo() {
  local repo=$BATS_TEST_TMPDIR/repo
  mkdir -p "$repo/scripts"
  cp -R "$ROOT/.agents" "$repo/.agents"
  cp -R "$ROOT/templates" "$repo/templates"
  cp "$INSTALLER" "$repo/scripts/install.sh"
  cp "$ROOT/scripts/install_codex_agents.py" "$repo/scripts/install_codex_agents.py"
  printf '%s\n' "$repo"
}

@test "--agents installs canonical Codex roles" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  assert_absent "$TEST_HOME/.claude/agents"
  assert_absent "$TEST_HOME/.codex/skills"
  assert_absent "$TEST_HOME/.codex/config.toml"
  for source in "$ROOT"/.agents/agents/*.md; do
    role="$TEST_HOME/.codex/agents/$(basename "$source" .md).toml"
    assert_codex_role "$role" "$source"
  done
  manifest="$TEST_HOME/.codex/.agents-install-state.json"
  assert_file "$manifest"
  python3 - "$manifest" <<'PY'
import json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert set(manifest) == {"state", "roles"}
assert manifest["state"] == "stable"
assert manifest["roles"]
PY
}

@test "a malformed manifest blocks the install before sync" {
  mkdir -p "$TEST_HOME/.codex"
  printf '{broken\n' >"$TEST_HOME/.codex/.agents-install-state.json"
  run install_into --agents --codex
  [ "$status" -ne 0 ]
  assert_contains "$output" "Codex agent installation failed"
  assert_absent "$TEST_HOME/.codex/agents/architect.toml"
}

@test "manifest symlinks block the install before sync" {
  for target in valid missing; do
    rm -rf "$TEST_HOME/.codex"
    mkdir -p "$TEST_HOME/.codex"
    if [ "$target" = valid ]; then
      printf '{"state":"stable","roles":{}}\n' >"$TEST_HOME/manifest.json"
      link_target="$TEST_HOME/manifest.json"
    else
      link_target="$TEST_HOME/missing.json"
    fi
    ln -s "$link_target" "$TEST_HOME/.codex/.agents-install-state.json"
    run install_into --agents --codex
    [ "$status" -ne 0 ]
    assert_contains "$output" "ownership manifest is not a regular file"
    assert_absent "$TEST_HOME/.codex/agents/architect.toml"
  done
}

@test "lock symlinks block the install before sync" {
  for target in valid missing; do
    rm -rf "$TEST_HOME/.codex"
    mkdir -p "$TEST_HOME/.codex"
    if [ "$target" = valid ]; then
      touch "$TEST_HOME/lock"
      link_target="$TEST_HOME/lock"
    else
      link_target="$TEST_HOME/missing-lock"
    fi
    ln -s "$link_target" "$TEST_HOME/.codex/.agents-install.lock"
    run install_into --agents --codex
    [ "$status" -ne 0 ]
    assert_contains "$output" "transaction lock is not a regular file"
    assert_absent "$TEST_HOME/.codex/agents/architect.toml"
  done
}

@test "a tampered manifest digest blocks the install before sync" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  manifest="$TEST_HOME/.codex/.agents-install-state.json"
  python3 - "$manifest" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text())
manifest["roles"]["architect.toml"] = ["0" * 64]
path.write_text(json.dumps(manifest))
PY
  before=$(mktemp)
  cp "$TEST_HOME/.codex/agents/architect.toml" "$before"
  run install_into --agents --codex
  [ "$status" -ne 0 ]
  assert_contains "$output" "refusing to replace modified Codex role"
  assert_same "$before" "$TEST_HOME/.codex/agents/architect.toml"
}

@test "an interrupted role update rolls forward safely" {
  repo=$(copy_repo)
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  printf '\nChanged upstream.\n' >>"$repo/.agents/agents/architect.md"
  run isolated_home env AGENTS_INSTALL_FAIL_PHASE=write AGENTS_INSTALL_FAIL_INDEX=2 \
    sh "$repo/scripts/install.sh" --agents --codex
  [ "$status" -ne 0 ]
  assert_file_contains "$TEST_HOME/.codex/.agents-install-state.json" '"state": "pending"'
  interrupted="$TEST_HOME/.codex/agents/architect.toml"
  assert_file_contains "$interrupted" 'Changed upstream.'
  before_edit=$(mktemp)
  cp "$interrupted" "$before_edit"
  printf '\nlocal_edit = true\n' >>"$interrupted"
  edited=$(mktemp)
  cp "$interrupted" "$edited"
  run install_from "$repo" --agents --codex
  [ "$status" -ne 0 ]
  assert_same "$edited" "$interrupted"
  cp "$before_edit" "$interrupted"
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_HOME/.codex/agents/architect.toml" 'Changed upstream.'
  assert_file_contains "$TEST_HOME/.codex/.agents-install-state.json" '"state": "stable"'
}

@test "an interrupted stale removal rolls forward safely" {
  repo=$(copy_repo)
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  rm "$repo/.agents/agents/architect.md"
  run isolated_home env AGENTS_INSTALL_FAIL_PHASE=remove AGENTS_INSTALL_FAIL_INDEX=1 \
    sh "$repo/scripts/install.sh" --agents --codex
  [ "$status" -ne 0 ]
  assert_absent "$TEST_HOME/.codex/agents/architect.toml"
  assert_file_contains "$TEST_HOME/.codex/.agents-install-state.json" '"state": "pending"'
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  assert_absent "$TEST_HOME/.codex/agents/architect.toml"
  assert_file_contains "$TEST_HOME/.codex/.agents-install-state.json" '"state": "stable"'
}

@test "missing managed roles reconcile from stable state" {
  repo=$(copy_repo)
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  rm "$TEST_HOME/.codex/agents/architect.toml"
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.codex/agents/architect.toml"

  rm "$repo/.agents/agents/architect.md"
  rm "$TEST_HOME/.codex/agents/architect.toml"
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  assert_absent "$TEST_HOME/.codex/agents/architect.toml"
  assert_not_contains "$(<"$TEST_HOME/.codex/.agents-install-state.json")" 'architect.toml'
}

@test "concurrent installs serialize reconciliation" {
  repo=$(copy_repo)
  ready="$BATS_TEST_TMPDIR/ready"
  release="$BATS_TEST_TMPDIR/release"
  first_out="$BATS_TEST_TMPDIR/first.out"
  isolated_home env AGENTS_INSTALL_READY="$ready" \
    AGENTS_INSTALL_RELEASE="$release" sh "$repo/scripts/install.sh" \
    --agents --codex >"$first_out" 2>&1 &
  first_pid=$!
  while [ ! -e "$ready" ]; do sleep 0.01; done
  printf '\nChanged upstream.\n' >>"$repo/.agents/agents/architect.md"
  second_out="$BATS_TEST_TMPDIR/second.out"
  install_from "$repo" --agents --codex >"$second_out" 2>&1 &
  second_pid=$!
  sleep 0.05
  assert_not_contains "$(<"$second_out")" "Installation complete"
  touch "$release"
  wait "$first_pid"
  wait "$second_pid"
  assert_file_contains "$TEST_HOME/.codex/agents/architect.toml" 'Changed upstream.'
  python3 - "$TEST_HOME/.codex" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
manifest = json.loads((root / ".agents-install-state.json").read_text())
assert manifest["state"] == "stable"
for name, digests in manifest["roles"].items():
    assert digests == [hashlib.sha256((root / "agents" / name).read_bytes()).hexdigest()]
PY
}

@test "a missing Python runtime reports the requirement" {
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  for command in awk basename cat cp dirname grep head mkdir mktemp mv pwd readlink rm rsync sed tail; do
    path=$(command -v "$command")
    [ -n "$path" ] && ln -s "$path" "$bin/$command"
  done
  run env PATH="$bin" HOME="$TEST_HOME" NO_COLOR=1 TERM=xterm \
    /bin/sh "$INSTALLER" --agents --codex
  [ "$status" -ne 0 ]
  assert_contains "$output" "Python with tomllib is required to install Codex agents"
}

@test "an unknown same-name role blocks the install before sync" {
  mkdir -p "$TEST_HOME/.codex/agents"
  role="$TEST_HOME/.codex/agents/architect.toml"
  printf 'name = "architect"\ndescription = "Mine"\ndeveloper_instructions = "Keep"\n' >"$role"
  before=$(mktemp)
  cp "$role" "$before"
  run install_into --agents --codex
  [ "$status" -ne 0 ]
  assert_contains "$output" "refusing to replace unrecognized Codex role"
  assert_same "$before" "$role"
  assert_absent "$TEST_HOME/.codex/agents/planner.toml"
}

@test "recognized roles update and foreign roles survive" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  role="$TEST_HOME/.codex/agents/architect.toml"
  before=$(mktemp)
  cp "$role" "$before"
  foreign="$TEST_HOME/.codex/agents/foreign.toml"
  printf 'name = "foreign"\ndescription = "Mine"\ndeveloper_instructions = "Keep"\n' >"$foreign"
  repo=$(copy_repo)
  printf '\nChanged upstream.\n' >>"$repo/.agents/agents/architect.md"
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  run cmp -s "$before" "$role"
  [ "$status" -ne 0 ]
  assert_file_contains "$role" 'Changed upstream.'
  assert_file_contains "$foreign" 'developer_instructions = "Keep"'
}

@test "stale owned roles are removed" {
  repo=$(copy_repo)
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  stale="$TEST_HOME/.codex/agents/architect.toml"
  assert_file "$stale"
  rm "$repo/.agents/agents/architect.md"
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  assert_absent "$stale"
}

@test "locally modified owned roles block reconciliation" {
  repo=$(copy_repo)
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  role="$TEST_HOME/.codex/agents/architect.toml"
  printf '\nlocal_edit = true\n' >>"$role"
  before=$(mktemp)
  cp "$role" "$before"
  rm "$repo/.agents/agents/architect.md"
  run install_from "$repo" --agents --codex
  [ "$status" -ne 0 ]
  assert_contains "$output" "refusing to remove modified Codex role"
  assert_same "$before" "$role"
}

@test "quoted and backslashed metadata renders valid TOML" {
  repo=$(copy_repo)
  source="$repo/.agents/agents/quoted.md"
  printf '%s\n' '---' 'name: quoted' 'description: "Quote: \"x\" and path C:\\tmp"' '---' '' "Use ''' and the path." >"$source"
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  python3 - "$TEST_HOME/.codex/agents/quoted.toml" <<'PY'
import pathlib, tomllib, sys
payload = pathlib.Path(sys.argv[1]).read_text()
assert tomllib.loads(payload)["description"] == 'Quote: "x" and path C:\\tmp'
PY
}

@test "renderer rejects malformed canonical inputs before sync" {
  for defect in blank-name blank-description blank-body control unsupported mismatch; do
    rm -rf "$BATS_TEST_TMPDIR/repo"
    repo=$(copy_repo)
    source="$repo/.agents/agents/probe.md"
    case $defect in
    blank-name) printf '%s\n' '---' 'name:' 'description: valid' '---' '' 'Body' >"$source" ;;
    blank-description) printf '%s\n' '---' 'name: probe' 'description:' '---' '' 'Body' >"$source" ;;
    blank-body) printf '%s\n' '---' 'name: probe' 'description: valid' '---' '' >"$source" ;;
    control)
      printf '%s\n' '---' 'name: probe' 'description: valid' '---' >"$source"
      printf '\001' >>"$source"
      ;;
    unsupported) printf '%s\n' '---' 'name: probe' 'description: valid' 'model: fixed' '---' '' 'Body' >"$source" ;;
    mismatch) printf '%s\n' '---' 'name: other' 'description: valid' '---' '' 'Body' >"$source" ;;
    esac
    run install_from "$repo" --agents --codex
    [ "$status" -ne 0 ]
    assert_absent "$TEST_HOME/.codex/agents/probe.toml"
  done
}

@test "NUL metadata and unsupported templates fail before sync" {
  rm -rf "$BATS_TEST_TMPDIR/repo"
  repo=$(copy_repo)
  source="$repo/.agents/agents/probe.md"
  printf '%s\n' '---' 'name: probe' >"$source"
  printf 'description: bad\000value\n---\n\nBody\n' >>"$source"
  run install_from "$repo" --agents --codex
  [ "$status" -ne 0 ]
  assert_absent "$TEST_HOME/.codex/agents/probe.toml"

  repo=$(copy_repo)
  mkdir -p "$repo/templates/.codex"
  printf 'model: fixed\n' >"$repo/templates/.codex/agents.yaml"
  run install_from "$repo" --agents --codex
  [ "$status" -ne 0 ]
  assert_contains "$output" "unsupported Codex agent template"
  assert_absent "$TEST_HOME/.codex/agents/architect.toml"
}

@test "a codex-only agents run leaves other hosts byte-identical" {
  run install_into --agents
  [ "$status" -eq 0 ]
  before="$BATS_TEST_TMPDIR/before"
  mkdir -p "$before"
  for host_dir in "$TEST_HOME/.claude/agents" "$TEST_HOME/.copilot/agents" \
    "$TEST_HOME/.gemini/agents" "$TEST_HOME/.config/opencode/agents"; do
    cp -R "$host_dir" "$before/$(basename "$(dirname "$host_dir")")-agents"
  done
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  for copy in "$before"/*; do
    base=$(basename "$copy")
    case $base in
    claude-agents) live="$TEST_HOME/.claude/agents" ;;
    copilot-agents) live="$TEST_HOME/.copilot/agents" ;;
    gemini-agents) live="$TEST_HOME/.gemini/agents" ;;
    opencode-agents) live="$TEST_HOME/.config/opencode/agents" ;;
    esac
    diff -r "$copy" "$live" >/dev/null || fail "codex-only run modified $live"
  done
}

@test "the Codex agents install is idempotent" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  before="$BATS_TEST_TMPDIR/before-agents"
  cp -R "$TEST_HOME/.codex/agents" "$before"
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  run diff -r "$before" "$TEST_HOME/.codex/agents"
  [ "$status" -eq 0 ]
}

@test "an unselected codex host installs no role files" {
  run install_into --agents --claude
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.claude/agents/architect.md"
  assert_absent "$TEST_HOME/.codex/agents"
}
