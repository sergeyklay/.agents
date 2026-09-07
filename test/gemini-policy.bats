load 'test_helper'

POLICY="$ROOT/.gemini/policies/safe-commands.toml"
DESTRUCTIVE_PATTERN='"command":"(?:rm -rf \/|rm -[-A-Za-z0-9_=./ ]* \/[\s"]|mkfs|dd if=|:\(\)\{)'

# Every @test runs in its own subshell, so a dotenv test may point $POLICY here
# without disturbing the safe-commands cases.
SECRETS_POLICY="$ROOT/.gemini/policies/secrets.toml"
DOTENV_PATTERN='\.env(?![a-zA-Z])(?![^"]*\.(example|sample|template|dist)")'
DOTENV_DENIAL='Tool execution denied by policy. Reading dotenv files is denied by policy. Read the .env.example instead.'

gemini_cli() {
  (
    cd "$TEST_HOME" &&
      HOME="$TEST_HOME" "$NODE" "$BUNDLE" "$@" </dev/null
  )
}

policy_decisions() {
  HOME="$TEST_HOME" "$NODE" "$ROOT/test/policy_decision.mjs" \
    "$BUNDLE" "$POLICY" "$@"
}

assert_decisions() {
  local expected lines=() specs=()
  while [ "$#" -gt 0 ]; do
    lines+=("$(printf '%s\t%s' "$1" "$2")")
    specs+=("$2")
    shift 2
  done
  expected=$(printf '%s\n' "${lines[@]}")
  run policy_decisions "${specs[@]}"
  [ "$status" -eq 0 ] || fail "policy engine run failed:
$output"
  [ "$output" = "$expected" ] || fail "expected:
$expected
got:
$output"
}

@test "the destructive-command rule reaches the engine compiled, not dropped" {
  require_gemini
  run policy_decisions --rules
  [ "$status" -eq 0 ] || fail "policy load failed:
$output"
  count=$(printf '%s\n' "$output" | sed -n 's/^rules'"$(printf '\t')"'//p')
  [ -n "$count" ] || fail "no rule count in:
$output"
  [ "$count" -gt 0 ] || fail "the policy compiled $count rules"
  assert_contains "$output" "$(printf 'pattern\t')$DESTRUCTIVE_PATTERN"
}

@test "rm is denied when its target is root, whatever operand precedes it" {
  require_gemini
  assert_decisions \
    deny 'rm -rf --no-preserve-root /' \
    deny 'rm --no-preserve-root -rf /' \
    deny 'rm -fr /' \
    deny 'rm -r -f /' \
    deny 'rm -v build dist /' \
    deny 'rm -rf build/dist /' \
    deny 'rm -rf ./build /' \
    deny 'rm -rf dist/ /'
}

@test "the destructive-command rule still denies what it already caught" {
  require_gemini
  assert_decisions \
    deny 'rm -rf /' \
    deny 'rm -rf /tmp/foo' \
    deny 'mkfs.ext4 /dev/sda1' \
    deny 'dd if=/dev/zero of=/dev/sda' \
    deny ':(){ :|:& };:' \
    deny 'sudo rm foo' \
    deny 'cd /tmp && rm -rf /'
}

@test "a flagged relative path with a slash keeps its decision" {
  require_gemini
  assert_decisions \
    ask_user 'rm -rf -v build/dist' \
    ask_user 'rm -rf -v dist/assets/js' \
    ask_user 'rm -rf -v node_modules/.cache' \
    ask_user 'rm -rf -i target/debug' \
    ask_user 'rm -rf --verbose build/dist' \
    ask_user 'rm -rf --one-file-system build/dist' \
    ask_user 'rm -rf --preserve-root build/dist' \
    ask_user 'rm -rf -- build/dist' \
    ask_user 'cd frontend && rm -rf -v dist/js' \
    ask_user 'rm -rf -v build/' \
    ask_user 'rm -rf -v dist/ obj/'
}

@test "a slash the destructive-command rule cannot reach keeps its decision" {
  require_gemini
  # shellcheck disable=SC2016
  assert_decisions \
    ask_user 'rm -rf build && cd /' \
    ask_user 'rm -rf dist && du -sh /' \
    ask_user 'rm -rf build ; df -h /' \
    ask_user 'rm -rf build || ls /' \
    ask_user 'rm -rf build | tee /' \
    ask_user 'rm -rf build & cd /' \
    ask_user 'rm -f log && grep -r foo /' \
    ask_user 'rm -rf -v out && cd /' \
    ask_user 'rm -rf build > /tmp/log' \
    ask_user '(rm -rf build) && cd /' \
    ask_user 'rm -rf $(cat list) /' \
    ask_user 'rm -rf `cat list` /' \
    ask_user "rm -rf 'a b' /" \
    ask_user 'rm -rf build
cd /'
}

@test "ordinary developer commands keep the decisions they had" {
  require_gemini
  assert_decisions \
    ask_user 'rm -rf ./build' \
    ask_user 'rm -rf build' \
    ask_user 'rm -rf -v ./build' \
    ask_user 'rm -f /tmp/lock' \
    ask_user 'sudoku' \
    allow 'git commit -m "remove rf files"' \
    allow 'echo sudo hello'
}

@test "the installed CLI loads the shipped policy without a diagnostic" {
  require_gemini
  run gemini_cli --prompt x --policy "$POLICY"
  assert_not_contains "$output" 'Policy file error'

  local policy_with_unsafe_regex="$BATS_TEST_TMPDIR/unsafe-regex.toml"
  printf '%s\n' \
    '[[rule]]' \
    'toolName = "run_shell_command"' \
    'commandRegex = "(?:rm (?:-\\S+ )*/)"' \
    'decision = "deny"' \
    'priority = 200' >"$policy_with_unsafe_regex"
  run gemini_cli --prompt x --policy "$policy_with_unsafe_regex"
  assert_contains "$output" 'Policy file error'
  assert_contains "$output" 'Unsafe regex pattern'
}

@test "GEMINI_MODEL still names a model the API serves" {
  require_gemini
  if [ -z "${GEMINI_MODEL:-}" ]; then
    [ -z "${CI:-}" ] ||
      fail 'GEMINI_MODEL is empty; default.mk declares it and exports it'
    skip 'GEMINI_MODEL is unset; it reaches the suite through "make install-test"'
  fi
  [ -n "${GEMINI_API_KEY:-}" ] ||
    skip "no GEMINI_API_KEY; nothing else in this suite calls the API"

  run gemini_cli --model "$GEMINI_MODEL" --prompt 'Reply with one word.' --skip-trust
  [ "$status" -eq 0 ] || fail "$GEMINI_MODEL did not answer:
$output"
  [ -n "$output" ] || fail "$GEMINI_MODEL answered with nothing"
}

# The engine matches the serialized arguments and never opens the file, so any
# absolute path stands in for a workspace.
read_file_in_repo() {
  printf '{"name":"read_file","args":{"file_path":"/repo/%s"}}' "$1"
}

# The loader expands the rule's two-name toolName list into one rule per name.
@test "the dotenv rule reaches the engine compiled, not dropped" {
  require_gemini
  POLICY=$SECRETS_POLICY
  run policy_decisions --rules
  [ "$status" -eq 0 ] || fail "policy load failed:
$output"
  count=$(printf '%s\n' "$output" | sed -n 's/^rules'"$(printf '\t')"'//p')
  [ "$count" = 2 ] || fail "the dotenv policy compiled $count rules:
$output"
  assert_contains "$output" "$(printf 'pattern\t')$DOTENV_PATTERN"
  assert_contains "$output" "$(printf 'denial\t')$DOTENV_DENIAL"
}

# WorkspaceContext.isPathWithinWorkspace already refuses a bare `.env` segment
# with no configuration, so `.env` here is depth; the rest is what the rule buys.
@test "the dotenv family the built-in guard misses is denied" {
  require_gemini
  POLICY=$SECRETS_POLICY
  assert_decisions \
    deny "$(read_file_in_repo .env)" \
    deny "$(read_file_in_repo .env.local)" \
    deny "$(read_file_in_repo .env.production)" \
    deny "$(read_file_in_repo app.env)" \
    deny "$(read_file_in_repo .env_backup)" \
    deny "$(read_file_in_repo .env-prod)" \
    deny "$(read_file_in_repo .env2)"
}

@test "the checked-in example files stay readable" {
  require_gemini
  POLICY=$SECRETS_POLICY
  assert_decisions \
    ask_user "$(read_file_in_repo .env.example)" \
    ask_user "$(read_file_in_repo .env.sample)" \
    ask_user "$(read_file_in_repo .env.template)" \
    ask_user "$(read_file_in_repo .env.dist)"
}

# The `(?![a-zA-Z])` lookahead draws this line, and `.envrc` lands on the
# permitted side, so direnv secrets stay open. `.ENV.local` is reached by
# neither guard: the pattern is case-sensitive and the built-in one only
# lowercases a whole segment.
@test "a name the dotenv rule cannot reach keeps its decision" {
  require_gemini
  POLICY=$SECRETS_POLICY
  assert_decisions \
    ask_user "$(read_file_in_repo .environment)" \
    ask_user "$(read_file_in_repo config.environment.json)" \
    ask_user "$(read_file_in_repo .envrc)" \
    ask_user "$(read_file_in_repo .ENV.local)" \
    ask_user "$(read_file_in_repo README.md)"
}

# The exemption lookahead scans forward from the match to the closing quote, so
# an example suffix exempts and an example directory further up the path cannot.
@test "the example exemption is read forward from the match" {
  require_gemini
  POLICY=$SECRETS_POLICY
  assert_decisions \
    ask_user "$(read_file_in_repo .env.local.example)" \
    deny "$(read_file_in_repo config.example/.env.local)"
}

# That closing quote also separates array elements, so one dotenv entry denies
# the whole call. `exclude` is matched too, though a call excluding a dotenv
# path would never read it.
@test "read_many_files is covered element by element" {
  require_gemini
  POLICY=$SECRETS_POLICY
  assert_decisions \
    ask_user '{"name":"read_many_files","args":{"include":["src/**/*.ts"]}}' \
    ask_user '{"name":"read_many_files","args":{"include":[".env.example"]}}' \
    deny '{"name":"read_many_files","args":{"include":[".env.local"]}}' \
    deny '{"name":"read_many_files","args":{"include":["src/**/*.ts",".env.local"]}}' \
    deny '{"name":"read_many_files","args":{"include":[".env.local","docs/x.example"]}}' \
    deny '{"name":"read_many_files","args":{"include":["**/*.ts"],"exclude":[".env"]}}'
}
