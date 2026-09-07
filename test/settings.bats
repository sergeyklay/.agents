# Settings merges and the Gemini policy engine. Repository values win
# conflicts; without jq, existing host-local files are skipped.

load 'test_helper'

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

# Gemini declares `mergeStrategy: "union"` for `skills.disabled`
# (settingsSchema.ts, 0.58.0), so a hand-added entry must survive the merge
# instead of being replaced by the repository array.
@test "Gemini settings merge unions a host-local skills.disabled entry" {
  printf '{"skills": {"disabled": ["host-only-skill"]}}\n' \
    >"$TEST_HOME/.gemini/settings.json"
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  jq -e '.skills.disabled | index("host-only-skill") != null' \
    "$TEST_HOME/.gemini/settings.json" >/dev/null
  jq -e '.skills.disabled | index("scan-security") != null' \
    "$TEST_HOME/.gemini/settings.json" >/dev/null
}

# Gemini declares no union strategy for `context.fileName`, so the repository
# array replaces the host's. Claude Code does combine a list key across its
# settings files, but this installer owns ~/.claude/settings.json outright, so
# rewriting that file is the repository's only way to withdraw an entry, and a
# `deny` a union stranded there could not be lifted anywhere: deny is evaluated
# before allow at every level. A host-local entry belongs in a file the
# installer never writes, such as .claude/settings.local.json, where Claude
# Code's own cross-file merge already keeps it.
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

# The dotenv policy rides the existing policies rsync, so assert it landed.
@test "the secrets policy is shipped" {
  run install_into --settings --gemini
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_HOME/.gemini/policies/secrets.toml" 'decision = "deny"'
}
