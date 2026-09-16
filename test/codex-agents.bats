load 'test_helper'

assert_codex_role() {
  local role=$1
  local src=$2
  python3 - "$role" "$src" <<'PY'
import pathlib
import sys
import tomllib

role_path, src_path = (pathlib.Path(p) for p in sys.argv[1:])

raw = src_path.read_text()
lines = raw.splitlines(keepends=True)
assert lines[0].rstrip("\n") == "---", f"{src_path}: no frontmatter"
i = 1
while i < len(lines) and lines[i].rstrip("\n") != "---":
    i += 1
body = "".join(lines[i + 1 :])

frontmatter = {}
for line in lines[1:i]:
    for key in ("name", "description"):
        if line.startswith(f"{key}:"):
            value = line[len(key) + 1 :].strip()
            if value[:1] in "'\"":
                value = value[1:-1]
            frontmatter[key] = value

name = src_path.stem
expected_effort = {
    "arch-review": "high",
    "architect": "high",
    "composer": "medium",
    "conductor": "medium",
    "go-coder": "medium",
    "go-tester": "medium",
    "planner": "high",
    "sleuth": "high",
    "ts-coder": "medium",
    "ts-tester": "medium",
}[name]

with open(role_path, "rb") as f:
    doc = tomllib.load(f)

expected = {
    "name": frontmatter["name"],
    "description": frontmatter["description"],
    "model_reasoning_effort": expected_effort,
    "developer_instructions": body,
}
for key, value in expected.items():
    assert doc.get(key) == value, f"{role_path}: {key} differs from the canonical expectation"
assert set(doc) == set(expected), f"{role_path}: role has unexpected settings"
PY
}

@test "--agents installs a Codex role file for every canonical agent" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  assert_absent "$TEST_HOME/.claude/agents"
  assert_absent "$TEST_HOME/.codex/skills"
  assert_absent "$TEST_HOME/.codex/config.toml"
  for src in "$ROOT"/.agents/agents/*.md; do
    assert_file "$TEST_HOME/.codex/agents/$(basename "$src" .md).toml"
  done
}

@test "every Codex role file matches its canonical body and template" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  for src in "$ROOT"/.agents/agents/*.md; do
    name=$(basename "$src" .md)
    assert_codex_role "$TEST_HOME/.codex/agents/$name.toml" "$src"
  done
}

@test "the content check detects a dropped reasoning effort" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  role="$TEST_HOME/.codex/agents/go-tester.toml"
  grep -v '^model_reasoning_effort = ' "$role" >"$role.new" && mv "$role.new" "$role"
  src="$ROOT/.agents/agents/go-tester.md"
  run assert_codex_role "$role" "$src"
  [ "$status" -ne 0 ]
  assert_contains "$output" "model_reasoning_effort"
}

@test "the content check detects dropped instructions" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  role="$TEST_HOME/.codex/agents/sleuth.toml"
  grep -v '^You are an investigator' "$role" >"$role.new" && mv "$role.new" "$role"
  src="$ROOT/.agents/agents/sleuth.md"
  run assert_codex_role "$role" "$src"
  [ "$status" -ne 0 ]
  assert_contains "$output" "developer_instructions"
}

@test "role files the repo does not own survive the install" {
  mkdir -p "$TEST_HOME/.codex/agents"
  printf 'name = "my-custom"\ndescription = "User role."\ndeveloper_instructions = "x"\n' \
    >"$TEST_HOME/.codex/agents/my-custom.toml"
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.codex/agents/my-custom.toml"
  assert_file "$TEST_HOME/.codex/agents/architect.toml"
  grep -q 'name = "my-custom"' "$TEST_HOME/.codex/agents/my-custom.toml"
}

@test "a codex-only agents run leaves the other hosts byte-identical" {
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
    diff -r "$copy" "$live" >/dev/null ||
      fail "codex-only run modified $live"
  done
}

@test "the Codex agents install is idempotent" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  before=$(find "$TEST_HOME/.codex/agents" -type f | sort | xargs md5sum)
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  after=$(find "$TEST_HOME/.codex/agents" -type f | sort | xargs md5sum)
  [ "$before" = "$after" ] || fail "second install changed the role files"
}

@test "an unselected codex host installs no role files" {
  run install_into --agents --claude
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.claude/agents/architect.md"
  assert_absent "$TEST_HOME/.codex/agents"
}
