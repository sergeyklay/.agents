# Repository values win merge conflicts; without jq, existing host-local
# files are skipped.
load 'test_helper'

assert_disabled_once() {
  jq -e --arg skill "$1" \
    '[.skills.disabled[] | select(. == $skill)] | length == 1' \
    "$TEST_HOME/.gemini/settings.json" >/dev/null
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

@test "Gemini settings merge preserves host-local keys" {
  printf '{"general": {"vimMode": true}}\n' >"$TEST_HOME/.gemini/settings.json"
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  # Under the default approval mode a stage agent receives no write tool
  # (measured on 0.58.0: 2 tools under `default`, 4 under `auto_edit`), and
  # the pipeline reports success without writing anything.
  # `general.defaultApprovalMode` is the only mitigation a settings file can
  # hold; `"yolo"` there is discarded.
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
# The shape check filters matching lines, so a missing key passes vacuously;
# assert the key exists before testing what it holds.
@test "every installed commandRegex anchors its alternation" {
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  policy="$TEST_HOME/.gemini/policies/safe-commands.toml"
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
# This asks the host instead, over every installed key at once, so a ninth key
# cannot arrive unguarded.
settings_key_verdicts() {
  HOME="$TEST_HOME" "$NODE" "$ROOT/test/settings_keys.mjs" \
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

  # A walk that reached nothing reports nothing, and an all-`known` report of
  # zero lines passes vacuously. Every top-level key yields at least one line,
  # so the installed file's own key count is a floor that rises with it.
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
