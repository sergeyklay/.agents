# Gemini prompt guards. A Gemini command prompt is a TOML literal string the
# CLI expands before it runs: ''' closes the string early, !{...} executes a
# command, @{...} reads a file.

load 'test_helper'

# A pristine repo copy built once per file; each planted sigil mutates a
# fresh copy of it.
setup_file() {
  GUARD_PRISTINE="$BATS_FILE_TMPDIR/pristine"
  mkdir -p "$GUARD_PRISTINE"
  cp -R -- "$ROOT/.agents" "$GUARD_PRISTINE/.agents"
  cp -R -- "$ROOT/templates" "$GUARD_PRISTINE/templates"
  export GUARD_PRISTINE
}

new_guard_repo() {
  GUARD_REPO="$BATS_TEST_TMPDIR/repo"
  rm -rf -- "$GUARD_REPO"
  mkdir -p "$GUARD_REPO/scripts"
  cp -R -- "$GUARD_PRISTINE/.agents" "$GUARD_REPO/.agents"
  cp -R -- "$GUARD_PRISTINE/templates" "$GUARD_REPO/templates"
  cp -- "$INSTALLER" "$GUARD_REPO/scripts/install.sh"
}

new_guard_home() {
  TEST_HOME="$BATS_TEST_TMPDIR/home-$(printf '%s%s' "$1" "$2" | cksum | cut -d' ' -f1)"
  mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/.codex" "$TEST_HOME/.copilot" \
    "$TEST_HOME/.gemini" "$TEST_HOME/.config/opencode"
}

assert_guard_rejects() {
  local target=$1 sigil=$2 command=$3
  new_guard_repo
  printf -- 'Planted %s here.\n' "$sigil" >>"$GUARD_REPO/$target"
  new_guard_home "$target" "$sigil"
  run install_from "$GUARD_REPO" --commands --gemini
  [ "$status" -ne 0 ] || fail "installer accepted $sigil in $target"
  assert_contains "$output" 'refusing to inline'
  assert_contains "$output" "$target"
  assert_absent "$TEST_HOME/.gemini/commands/$command.toml"
}

# All three counts are 0 in the canonical sources, so planted fragments are
# what prove the guard fires. Four fragments are concatenated into the TOML
# literal, and every one of them is a place a sigil can enter.
@test "refuses a sigil in the inlined agent body" {
  for sigil in "'''" '!{echo pwned}' '@{/etc/passwd}'; do
    assert_guard_rejects '.agents/agents/composer.md' "$sigil" specify
  done
}

@test "refuses a sigil in the command preamble" {
  for sigil in "'''" '!{echo pwned}' '@{/etc/passwd}'; do
    assert_guard_rejects 'templates/.gemini/commands/vet-impl.preamble.md' "$sigil" vet-impl
  done
}

@test "refuses a sigil in the command body" {
  for sigil in "'''" '!{echo pwned}' '@{/etc/passwd}'; do
    assert_guard_rejects '.agents/commands/vet-impl.md' "$sigil" vet-impl
  done
}

@test "refuses a sigil in the body suffix" {
  for sigil in "'''" '!{echo pwned}' '@{/etc/passwd}'; do
    assert_guard_rejects 'templates/.gemini/commands/vet-impl.body.md' "$sigil" vet-impl
  done
}

# A lone `@` is not the `@{` sigil; a guard matching it would reject prose that
# names an agent. No shipped fragment carries one, so the case is planted.
@test "a bare @mention is not the @{ sigil" {
  new_guard_repo
  printf -- 'Findings go to @arch-review.\n' \
    >>"$GUARD_REPO/templates/.gemini/commands/vet-impl.preamble.md"
  new_guard_home bare-mention vet-impl
  run install_from "$GUARD_REPO" --commands --gemini
  [ "$status" -eq 0 ] || fail "installer rejected a bare @mention"
  assert_file_contains "$TEST_HOME/.gemini/commands/vet-impl.toml" '@arch-review'
}

# A traversing agent value resolves to an existing file outside the canonical
# directory; the existence check passes and untracked content reaches the
# shipped prompt.
@test "refuses a traversing agent name" {
  repo="$BATS_TEST_TMPDIR/agent-path-repo"
  mkdir -p "$repo/scripts" "$repo/private"
  cp -R -- "$ROOT/.agents" "$repo/.agents"
  cp -R -- "$ROOT/templates" "$repo/templates"
  cp -- "$INSTALLER" "$repo/scripts/install.sh"
  printf 'planted body outside the agents directory\n' >"$repo/private/notes.md"
  printf 'agent: ../../private/notes\n' \
    >"$repo/templates/.gemini/commands/specify.yaml"
  run install_from "$repo" --commands --gemini
  [ "$status" -ne 0 ]
  assert_contains "$output" 'refusing to inline agent'
  assert_absent "$TEST_HOME/.gemini/commands/specify.toml"
}
