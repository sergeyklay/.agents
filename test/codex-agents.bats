# Codex role files are whole TOML documents rendered from the canonical agent
# bodies; the checks here compare the installed result against the canonical
# source and the Codex template so a dropped field fails before any Codex run.

load 'test_helper'

# Compares an installed Codex role file against its canonical body and the
# Claude template (the behavioral reference), so a field dropped from the
# Codex template cannot hide behind the renderer that reads the same file.
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

# The Codex template contributes one comparable setting: its effort pin. The
# skills and features blocks are checked through the rendered file, whose
# expectations come from the Claude reference alone.
def codex_template_effort(path):
    for line in path.read_text().splitlines():
        if line.startswith("model_reasoning_effort:"):
            return line.split(":", 1)[1].strip()
    return None

# The Claude template is the behavioral reference: its tools and effort
# decide what the Codex role must pin.
def parse_claude_template(path):
    text = path.read_text().splitlines()
    tools = []
    skills = []
    effort = None
    j = 0
    while j < len(text):
        line = text[j]
        if line.startswith("tools:"):
            j += 1
            while j < len(text) and (
                text[j].startswith("  - ") or text[j].strip().startswith("#") or not text[j].strip()
            ):
                if text[j].startswith("  - "):
                    tools.append(text[j][4:].strip())
                j += 1
            j -= 1
        elif line.startswith("skills:"):
            j += 1
            while j < len(text) and (
                text[j].startswith("  - ") or text[j].strip().startswith("#") or not text[j].strip()
            ):
                if text[j].startswith("  - "):
                    skills.append(text[j][4:].strip())
                j += 1
            j -= 1
        elif line.startswith("effort:"):
            effort = line.split(":", 1)[1].strip()
        j += 1
    return tools, skills, effort

name = src_path.stem
claude_tools, claude_skills, claude_effort = parse_claude_template(
    root / "templates/.claude/agents" / f"{name}.yaml"
)
effort = codex_template_effort(tmpl_path)

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

# Reasoning effort mirrors the Claude pin; the ladder is the one measured for
# the pinned gpt-5.6-sol on codex-cli 0.154.0.
assert claude_effort is not None, (
    f"{role_path}: the Claude reference pins no effort to mirror"
)
assert effort == claude_effort, (
    f"{role_path}: codex effort {effort!r} != Claude reference {claude_effort!r}"
)
ladder = {"low", "medium", "high", "xhigh", "max", "ultra"}
assert effort in ladder, (
    f"{role_path}: effort {effort!r} is outside the pinned model's ladder"
)
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

# Claude grants no Bash exactly to the agents whose Codex role must drop the
# shell, and grants no plugin-like surface to the agents whose Codex catalog it
# enumerates; codex cannot split search from the shell, so those roles lose
# codex-side search too - narrower than Claude, never wider.
if "Skill" not in claude_tools:
    expected_features = {"plugins": False}
    if "Bash" not in claude_tools:
        expected_features["shell_tool"] = False
    assert doc.get("features", {}) == expected_features, (
        f"{role_path}: features {doc.get('features')} != the Claude-derived"
        f" disables {expected_features}"
    )
else:
    assert "features" not in doc, f"{role_path}: unexpected features block"

# Claude agents holding the Skill tool load any skill on demand, so their
# Codex catalog stays unrestricted; the others see exactly Claude's preload
# list, and agents with neither see no catalog at all.
if "Skill" in claude_tools:
    assert "skills" not in doc, (
        f"{role_path}: Claude allows on-demand skills but the codex role narrows"
    )
elif claude_skills:
    installed = {p.name for p in (root / ".agents/skills").iterdir() if p.is_dir()}
    assert set(claude_skills) <= installed, (
        f"{role_path}: Claude preload names uninstalled skills: "
        f"{sorted(set(claude_skills) - installed)}"
    )
    assert doc.get("skills", {}).get("bundled", {}).get("enabled") is False, (
        f"{role_path}: bundled skills stay visible outside the allow-list"
    )
    disabled = {entry["name"] for entry in doc.get("skills", {}).get("config", [])}
    expected_disabled = installed - set(claude_skills)
    assert disabled == expected_disabled, (
        f"{role_path}: disable rules {sorted(disabled)} != complement "
        f"{sorted(expected_disabled)}"
    )
    for entry in doc.get("skills", {}).get("config", []):
        assert entry["enabled"] is False, (
            f"{role_path}: enable rule survives the renderer"
        )
else:
    assert doc.get("skills", {}).get("include_instructions") is False, (
        f"{role_path}: skills catalog block must be dropped"
    )
    assert "config" not in doc.get("skills", {}), (
        f"{role_path}: `none` must not carry per-skill rules"
    )
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
  grep -v '^model_reasoning_effort = ' "$role" >"$role.new" && mv "$role.new" "$role"
  src="$ROOT/.agents/agents/go-tester.md"
  run assert_codex_role "$role" "$src" "$ROOT/templates/.codex/agents/go-tester.yaml"
  [ "$status" -ne 0 ]
  assert_contains "$output" "reasoning effort"
}

@test "the content check detects dropped instructions" {
  run install_into --agents --codex
  [ "$status" -eq 0 ]
  role="$TEST_HOME/.codex/agents/sleuth.toml"
  grep -v '^You are an investigator' "$role" >"$role.new" && mv "$role.new" "$role"
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
  awk '/^name = "test-go"$/ { print; getline; sub(/enabled = false/, "enabled = true"); print; next }
       { print }' "$role" >"$role.new" && mv "$role.new" "$role"
  src="$ROOT/.agents/agents/planner.md"
  run assert_codex_role "$role" "$src" "$ROOT/templates/.codex/agents/planner.yaml"
  [ "$status" -ne 0 ]
  assert_contains "$output" "enable rule survives the renderer"
}

# Renderer and comparator both read the Codex template, so a dropped template
# field would hide if the expectation came from the same file; it comes from
# the Claude reference instead, and this control proves that catches the drop.
@test "the content check catches a template that dropped the Claude effort" {
  repo="$BATS_TEST_TMPDIR/effort-drop"
  mkdir -p "$repo/scripts"
  cp -R "$ROOT/.agents" "$repo/.agents"
  cp -R "$ROOT/templates" "$repo/templates"
  cp "$INSTALLER" "$repo/scripts/install.sh"
  broken="$repo/templates/.codex/agents/arch-review.yaml"
  grep -v '^model_reasoning_effort: ' "$broken" >"$broken.new" && mv "$broken.new" "$broken"
  run install_from "$repo" --agents --codex
  [ "$status" -eq 0 ]
  run assert_codex_role "$TEST_HOME/.codex/agents/arch-review.toml" \
    "$ROOT/.agents/agents/arch-review.md" "$broken"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Claude reference"
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
