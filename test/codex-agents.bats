# Codex role files are whole TOML documents rendered from the canonical agent
# bodies; the checks here compare the installed result against the canonical
# source and the Codex template so a dropped field fails before any Codex run.

load 'test_helper'

# Compares one installed Codex role file against its canonical body and Codex
# template, and refuses keys the 0.154.0 loader accepts but silently ignores,
# so a template can never promise a restriction the host does not enforce.
assert_codex_role() {
  local role=$1
  local src=$2
  local tmpl=$3
  python3 - "$role" "$src" "$tmpl" "$ROOT" <<'PY'
import pathlib
import sys
import tomllib

role_path, src_path, tmpl_path, root = (pathlib.Path(p) for p in sys.argv[1:])

# The installer's split_frontmatter: the body is everything after the
# closing `---` line.
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

# The template format is the fixed shape the renderer reads.
effort = None
skills = None
features = {}
tmpl_lines = tmpl_path.read_text().splitlines()
j = 0
while j < len(tmpl_lines):
    line = tmpl_lines[j]
    if line.startswith("model_reasoning_effort:"):
        effort = line.split(":", 1)[1].strip()
    elif line.startswith("skills:"):
        inline = line.split(":", 1)[1].strip()
        if inline:
            skills = inline
        else:
            listed = []
            j += 1
            while j < len(tmpl_lines) and (
                tmpl_lines[j].startswith("  - ") or not tmpl_lines[j].strip()
            ):
                if tmpl_lines[j].startswith("  - "):
                    listed.append(tmpl_lines[j][4:].strip())
                j += 1
            skills = listed
            j -= 1
    elif line.startswith("features:"):
        j += 1
        while j < len(tmpl_lines) and (
            tmpl_lines[j].startswith("  ") or not tmpl_lines[j].strip()
        ):
            entry = tmpl_lines[j].strip()
            if ":" in entry:
                key, value = entry.split(":", 1)
                features[key.strip()] = value.strip()
            j += 1
        j -= 1
    j += 1

with open(role_path, "rb") as f:
    doc = tomllib.load(f)

expected = frontmatter["name"]
assert doc["name"] == expected, f"{role_path}: name {doc['name']!r} != {expected!r}"
assert doc["description"] == frontmatter["description"], (
    f"{role_path}: description drifted from the canonical frontmatter"
)
assert doc["developer_instructions"] == body, (
    f"{role_path}: developer_instructions is not the canonical body"
)

if effort is None:
    assert "model_reasoning_effort" not in doc, (
        f"{role_path}: reasoning effort present without a template pin"
    )
else:
    assert doc.get("model_reasoning_effort") == effort, (
        f"{role_path}: reasoning effort {doc.get('model_reasoning_effort')!r}"
        f" != template {effort!r}"
    )

# The global config pins one model; a per-role pin would fork the fleet.
assert "model" not in doc, f"{role_path}: per-role model pin breaks the global pin"

# sandbox_mode, approval_policy, permissions, and mcp_servers are accepted by
# the 0.154.0 role loader but never applied to the spawned agent; carrying one
# would advertise a restriction that is not in force.
for inert in (
    "sandbox_mode",
    "approval_policy",
    "permissions",
    "default_permissions",
    "mcp_servers",
    "tools",
    "instructions",
):
    assert inert not in doc, f"{role_path}: inert key {inert} promises an unenforced setting"

if features.get("shell_tool") == "false":
    assert doc.get("features", {}).get("shell_tool") is False, (
        f"{role_path}: template disables the shell but the role file does not"
    )
else:
    assert "features" not in doc, f"{role_path}: unexpected features block"

if skills is None:
    assert "skills" not in doc, f"{role_path}: unexpected skills block"
elif skills == "none":
    assert doc.get("skills", {}).get("include_instructions") is False, (
        f"{role_path}: skills catalog block must be dropped"
    )
    assert "config" not in doc.get("skills", {}), (
        f"{role_path}: `none` must not carry per-skill rules"
    )
else:
    installed = {p.name for p in (root / ".agents/skills").iterdir() if p.is_dir()}
    assert set(skills) <= installed, (
        f"{role_path}: allow-list names uninstalled skills: "
        f"{sorted(set(skills) - installed)}"
    )
    got = doc.get("skills", {})
    assert got.get("bundled", {}).get("enabled") is False, (
        f"{role_path}: bundled skills stay visible outside the allow-list"
    )
    disabled = {entry["name"] for entry in got.get("config", [])}
    expected_disabled = installed - set(skills)
    assert disabled == expected_disabled, (
        f"{role_path}: disable rules {sorted(disabled)} != complement "
        f"{sorted(expected_disabled)}"
    )
    for entry in got.get("config", []):
        assert entry["enabled"] is False, f"{role_path}: enable rule survives the renderer"
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
    assert_codex_role "$TEST_HOME/.codex/agents/$name.toml" "$src" \
      "$ROOT/templates/.codex/agents/$name.yaml"
  done
}

# The loader refuses a malformed role file only once Codex runs, so the
# comparator must catch drift first; corrupting an installed file proves the
# comparator can go red.
@test "the content check detects a dropped reasoning effort" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  role="$TEST_HOME/.codex/agents/go-tester.toml"
  sed -i '/^model_reasoning_effort = /d' "$role"
  src="$ROOT/.agents/agents/go-tester.md"
  run assert_codex_role "$role" "$src" "$ROOT/templates/.codex/agents/go-tester.yaml"
  [ "$status" -ne 0 ]
  assert_contains "$output" "reasoning effort"
}

@test "the content check detects dropped instructions" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  role="$TEST_HOME/.codex/agents/sleuth.toml"
  sed -i '/^You are an investigator/d' "$role"
  src="$ROOT/.agents/agents/sleuth.md"
  run assert_codex_role "$role" "$src" "$ROOT/templates/.codex/agents/sleuth.yaml"
  [ "$status" -ne 0 ]
  assert_contains "$output" "developer_instructions"
}

@test "the content check detects a widened skills catalog" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  role="$TEST_HOME/.codex/agents/planner.toml"
  # Re-enabling one disabled skill widens the catalog beyond the allow-list;
  # an enable rule is a no-op the spawned role never sees.
  sed -i '/^name = "test-go"$/ {n; s/enabled = false/enabled = true/}' "$role"
  src="$ROOT/.agents/agents/planner.md"
  run assert_codex_role "$role" "$src" "$ROOT/templates/.codex/agents/planner.yaml"
  [ "$status" -ne 0 ]
  assert_contains "$output" "enable rule survives the renderer"
}

# Codex discovers $CODEX_HOME/agents/*.toml recursively; the installer writes
# one file per canonical agent and must leave everything else alone.
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
