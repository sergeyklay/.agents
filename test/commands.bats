# The Gemini prompt sigil and path traversal guards live in gemini-guard.bats.
load 'test_helper'

# Orchestrator commands must fork, and the fork must survive past the invoking
# turn or it never receives the subagent's completion notification.
@test "orchestrator commands fork without pinning the turn" {
  run install_into --commands --claude
  [ "$status" -eq 0 ]
  for command in specify implement; do
    assert_file "$TEST_HOME/.claude/commands/$command.md"
    assert_frontmatter "$TEST_HOME/.claude/commands/$command.md" 'context: fork'
    assert_no_frontmatter_key "$TEST_HOME/.claude/commands/$command.md" 'background'
  done
  assert_frontmatter "$TEST_HOME/.claude/commands/specify.md" 'agent: composer'
  assert_frontmatter "$TEST_HOME/.claude/commands/implement.md" 'agent: conductor'
}

# Gemini CLI 0.58.0 keeps invoke_agent only in the primary session, so the
# orchestrator protocol ships as a command with `agent: <name>` inlining the
# canonical agent body into the generated prompt.
@test "Gemini command TOML inlines the canonical orchestrator body" {
  run install_into --commands --gemini
  [ "$status" -eq 0 ]
  for pair in specify:composer implement:conductor; do
    command=${pair%:*}
    agent=${pair#*:}
    toml="$TEST_HOME/.gemini/commands/$command.toml"
    assert_file "$toml"
    assert_toml_parses "$toml"
    # Derived from the canonical file so it cannot drift; distinct per agent
    # so inlining the wrong body still fails.
    assert_file_contains "$toml" "$(first_body_line "$ROOT/.agents/agents/$agent.md")"
    assert_file_contains "$toml" '{{args}}'
    # Unknown keys in the TOML command schema are stripped without warning;
    # an `agent` key would look present and do nothing.
    if grep -q '^agent[[:space:]]*=' "$toml"; then
      fail "unexpected agent key in $toml"
    fi
  done
}

@test "Gemini review command TOML inlines the arch-review body" {
  run install_into --commands --gemini
  [ "$status" -eq 0 ]
  for command in vet-impl vet-spec; do
    toml="$TEST_HOME/.gemini/commands/$command.toml"
    assert_file "$toml"
    assert_toml_parses "$toml"
    assert_file_contains "$toml" "$(first_body_line "$ROOT/.agents/agents/arch-review.md")"
    assert_file_contains "$toml" '{{args}}'
    if grep -qF -- '@arch-review' "$toml"; then
      fail "inert bare mention left in $toml"
    fi
    if grep -q '^name: arch-review$' "$toml"; then
      fail "agent frontmatter leaked into $toml"
    fi
  done
}

# Copilot CLI 1.0.83 discovers personal assets only under ~/.copilot/skills and
# ~/.agents/skills. A prompts/ directory is not a discovery root and there is no
# personal commands/ root, so a command written anywhere else never loads.
@test "Copilot commands install into the personal skills root" {
  run install_into --commands --copilot
  [ "$status" -eq 0 ]
  for command in specify vet-spec; do
    skill="$TEST_HOME/.copilot/skills/$command/SKILL.md"
    assert_file "$skill"
    # Derived from the canonical file so the assertion cannot drift, and distinct
    # per command so installing the wrong body still fails.
    canonical="$ROOT/.agents/commands/$command.md"
    assert_frontmatter "$skill" "$(grep -m1 '^description: ' "$canonical")"
    assert_file_contains "$skill" "$(first_body_line "$canonical")"
  done
  assert_absent "$TEST_HOME/.copilot/prompts"
}

# Copilot takes the invocation name from `name:` and falls back to the directory
# name. The directory carries the canonical kebab-case name every other host
# uses, so the key stays out and one spelling serves all five hosts.
@test "Copilot command views leave the invocation name to the directory" {
  run install_into --commands --copilot
  [ "$status" -eq 0 ]
  checked=0
  for f in "$ROOT"/.agents/commands/*.md; do
    # An unmatched glob arrives as its own literal and would count as a file.
    [ -f "$f" ] || continue
    command=$(basename -- "$f" .md)
    case $command in
    *[!a-z0-9-]*) fail "canonical command name is not kebab-case: $command" ;;
    esac
    skill="$TEST_HOME/.copilot/skills/$command/SKILL.md"
    assert_file "$skill"
    assert_no_frontmatter_key "$skill" 'name'
    checked=$((checked + 1))
  done
  [ "$checked" -gt 0 ] || fail "no command sources under .agents/commands to check"
}

# Measured on 1.0.83: neither key changes anything on a SKILL.md, and neither
# produces a diagnostic. A key that looks like it selects an agent or a model
# and selects neither is worse than its absence.
@test "Copilot command views carry no key the loader ignores" {
  run install_into --commands --copilot
  [ "$status" -eq 0 ]
  checked=0
  for f in "$ROOT"/.agents/commands/*.md; do
    [ -f "$f" ] || continue
    skill="$TEST_HOME/.copilot/skills/$(basename -- "$f" .md)/SKILL.md"
    assert_file "$skill"
    assert_no_frontmatter_key "$skill" 'agent'
    assert_no_frontmatter_key "$skill" 'model'
    # A VS Code prompt-file input variable. Copilot substitutes nothing, so the
    # placeholder would reach the model as its own source text.
    if grep -qF -- "\${input:" "$skill"; then
      fail "unexpanded VS Code input variable left in $skill"
    fi
    checked=$((checked + 1))
  done
  [ "$checked" -gt 0 ] || fail "no command sources under .agents/commands to check"
}

# With `agent:` inert, the orchestrator protocol only reaches the session if the
# installer inlines it, the same way Gemini's command schema already forces.
@test "Copilot command SKILL.md inlines the canonical agent body" {
  run install_into --commands --copilot
  [ "$status" -eq 0 ]
  for pair in specify:composer implement:conductor vet-spec:arch-review vet-impl:arch-review; do
    command=${pair%:*}
    agent=${pair#*:}
    skill="$TEST_HOME/.copilot/skills/$command/SKILL.md"
    assert_file "$skill"
    # Derived from the canonical file so it cannot drift; distinct per agent so
    # inlining the wrong body still fails.
    assert_file_contains "$skill" "$(first_body_line "$ROOT/.agents/agents/$agent.md")"
  done
  # A command with no agent must not pick one up.
  assert_no_frontmatter_key "$TEST_HOME/.copilot/skills/make-pr/SKILL.md" 'agent'
  run grep -cF -- "$(first_body_line "$ROOT/.agents/agents/composer.md")" \
    "$TEST_HOME/.copilot/skills/make-pr/SKILL.md"
  [ "$status" -ne 0 ] || fail "composer body leaked into the make-pr view"
}

# Every machine that ever ran --commands still holds the prompt views, plus a
# `pr` view orphaned by the rename to `make-pr`. The CLI never read any of them.
@test "installing commands removes the Copilot prompt views it once wrote" {
  mkdir -p "$TEST_HOME/.copilot/prompts"
  for f in "$ROOT"/.agents/commands/*.md; do
    [ -f "$f" ] || continue
    stale="$TEST_HOME/.copilot/prompts/$(basename -- "$f" .md).prompt.md"
    printf -- '---\n%s\n---\n\nold body\n' "$(grep -m1 '^description: ' "$f")" >"$stale"
  done
  # The rename orphan carries make-pr's description under its own filename.
  printf -- '---\n%s\n---\n\nold body\n' \
    "$(grep -m1 '^description: ' "$ROOT/.agents/commands/make-pr.md")" \
    >"$TEST_HOME/.copilot/prompts/pr.prompt.md"
  # A prompt file the operator wrote. Removal is keyed on the description, so
  # this one has to survive or the cleanup is a directory sweep.
  mine="$TEST_HOME/.copilot/prompts/mine.prompt.md"
  printf -- '---\ndescription: An operator prompt this installer never wrote\n---\n\nmine\n' >"$mine"

  run install_into --commands --copilot
  [ "$status" -eq 0 ]

  assert_absent "$TEST_HOME/.copilot/prompts/specify.prompt.md"
  assert_absent "$TEST_HOME/.copilot/prompts/pr.prompt.md"
  assert_file "$mine"
}

# ALL_ACTIONS runs skills after commands, and the skills mirror deletes whatever
# it does not own, so the two share one destination root.
@test "installing skills keeps the Copilot command views" {
  run install_into --commands --skills --copilot
  [ "$status" -eq 0 ]
  assert_file "$TEST_HOME/.copilot/skills/specify/SKILL.md"
  assert_file "$TEST_HOME/.copilot/skills/research-it/SKILL.md"
}

# sync_copilot_skills excludes the command names from the skills mirror, so a
# canonical skill that took a command's name would stop reaching Copilot without
# a word from the installer.
@test "no canonical skill takes a command name" {
  checked=0
  for f in "$ROOT"/.agents/commands/*.md; do
    # An unmatched glob arrives as its own literal and would count as a file.
    [ -f "$f" ] || continue
    name=$(basename -- "$f" .md)
    checked=$((checked + 1))
    if [ -d "$ROOT/.agents/skills/$name" ]; then
      fail "skill and command both named $name; the Copilot skills mirror would drop the skill"
    fi
  done
  [ "$checked" -gt 0 ] || fail "no command sources under .agents/commands to check"
}

copilot_skill_list() {
  (
    cd "$1" &&
      HOME="$TEST_HOME" TERM=dumb NO_COLOR=1 "$NODE" "$LOADER" skill list --json </dev/null
  )
}

# The assertions above describe the installed file. This one is the only thing
# tying that shape to the host: a correct-looking file Copilot stopped reading
# would pass every one of them. `skill list --json` needs no auth and no network.
@test "the Copilot CLI discovers every command view under its canonical name" {
  require_copilot
  run install_into --commands --copilot
  [ "$status" -eq 0 ]

  # Copilot finds project skills by walking the working directory's ancestors,
  # so a cwd under the operator's home pulls in their real ones and the listing
  # stops being about $TEST_HOME. BATS_TEST_TMPDIR sits outside it.
  probe="$BATS_TEST_TMPDIR/copilot-cwd"
  mkdir -p "$probe"
  run copilot_skill_list "$probe"
  [ "$status" -eq 0 ] || fail "copilot skill list failed:
$output"

  # The builtin skills ship inside the CLI and appear in every run. Without them
  # a missing command is indistinguishable from a listing that loaded nothing.
  assert_contains "$output" '"name": "github-pr-media"'

  checked=0
  for f in "$ROOT"/.agents/commands/*.md; do
    [ -f "$f" ] || continue
    assert_contains "$output" "\"name\": \"$(basename -- "$f" .md)\""
    checked=$((checked + 1))
  done
  [ "$checked" -gt 0 ] || fail "no command sources under .agents/commands to check"
}
