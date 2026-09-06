load 'test_helper'

POLICY="$ROOT/.gemini/policies/safe-commands.toml"
DESTRUCTIVE_PATTERN='"command":"(?:rm -rf \/|rm -[-A-Za-z0-9_=. ]* \/[\s"]|mkfs|dd if=|:\(\)\{)'

gemini_bundle_entry() {
  local candidate
  for candidate in "$(command -v gemini 2>/dev/null)" \
    "$(asdf which gemini 2>/dev/null)"; do
    [ -n "$candidate" ] || continue
    candidate=$(readlink -f -- "$candidate" 2>/dev/null) || continue
    case $candidate in
    *.js)
      printf '%s\n' "$candidate"
      return 0
      ;;
    esac
  done
  return 1
}

node_beside_bundle() {
  local prefix=${1%/lib/node_modules/*}
  if [ "$prefix" != "$1" ] && [ -x "$prefix/bin/node" ]; then
    printf '%s\n' "$prefix/bin/node"
    return 0
  fi
  command -v node
}

fail_on_ci_else_skip() {
  if [ -n "${CI:-}" ]; then
    fail "$1 (CI is set, and the workflow installs the Gemini CLI)"
  fi
  skip "$1"
}

require_gemini() {
  BUNDLE=$(gemini_bundle_entry) ||
    fail_on_ci_else_skip 'no Gemini CLI bundle on PATH; it carries the policy engine under test'
  NODE=$(node_beside_bundle "$BUNDLE") ||
    fail_on_ci_else_skip 'no node to load the Gemini CLI bundle with'
}

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
  local expected lines=() commands=()
  while [ "$#" -gt 0 ]; do
    lines+=("$(printf '%s\t%s' "$1" "$2")")
    commands+=("$2")
    shift 2
  done
  expected=$(printf '%s\n' "${lines[@]}")
  run policy_decisions "${commands[@]}"
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

@test "rm is denied when its target is root and a flag stands in between" {
  require_gemini
  assert_decisions \
    deny 'rm -rf --no-preserve-root /' \
    deny 'rm --no-preserve-root -rf /' \
    deny 'rm -fr /' \
    deny 'rm -r -f /' \
    deny 'rm -v build dist /'
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

@test "a slash belonging to a later sub-command keeps its decision" {
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
