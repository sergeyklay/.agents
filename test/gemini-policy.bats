# Resolution of `.gemini/policies/safe-commands.toml` by the policy engine that
# ships inside the installed Gemini CLI. The rules are regexes the CLI rewrites
# before it compiles them, so the text of a rule says nothing about what it
# matches; every assertion here is the decision the engine returns.

load 'test_helper'

POLICY="$ROOT/.gemini/policies/safe-commands.toml"

# `command -v gemini` is a version-manager shim on some hosts, and readlink
# resolves a shim to itself rather than to the bundle it execs; ask the version
# manager when the first resolution is not the bundle entry point.
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

# The CI workflow installs the Gemini CLI, so a skip there means the install
# step regressed and the job would go green having asserted nothing. On a
# developer machine without the CLI a skip is the right answer.
ci_fail_or_skip() {
  if [ -n "${CI:-}" ]; then
    fail "$1 (CI is set, and the workflow installs the Gemini CLI)"
  fi
  skip "$1"
}

# The `node` on PATH can be a version-manager shim, which picks its version by
# walking up from the working directory and exits 126 in a scratch directory
# that has no version file. The interpreter that owns the installed CLI sits a
# fixed distance from the bundle, so take that one and fall back to PATH.
gemini_node() {
  local prefix=${1%/lib/node_modules/*}
  if [ "$prefix" != "$1" ] && [ -x "$prefix/bin/node" ]; then
    printf '%s\n' "$prefix/bin/node"
    return 0
  fi
  command -v node
}

# The engine under test ships with the CLI, so there is nothing to assert
# against when the CLI is absent.
require_gemini() {
  BUNDLE=$(gemini_bundle_entry) ||
    ci_fail_or_skip 'no Gemini CLI bundle on PATH; it carries the policy engine under test'
  NODE=$(gemini_node "$BUNDLE") ||
    ci_fail_or_skip 'no node to load the Gemini CLI bundle with'
}

# The CLI itself, invoked through the bundle entry point its package manifest
# names as the `gemini` binary, from a scratch directory with HOME pointed at
# it so the run leaves nothing in the operator's own state roots.
gemini_cli() {
  (
    cd "$TEST_HOME" &&
      HOME="$TEST_HOME" "$NODE" "$BUNDLE" "$@" </dev/null
  )
}

# One engine run for every case, with HOME pointed at the per-test directory so
# the CLI's own state roots stay untouched.
policy_decisions() {
  HOME="$TEST_HOME" "$NODE" "$ROOT/test/policy_decision.mjs" \
    "$BUNDLE" "$POLICY" "$@"
}

# Each argument is "<expected decision><tab><command>". Comparing the whole
# block at once means a decision that moves in either direction shows up.
assert_decisions() {
  local expected line
  local commands=()
  expected=$(printf '%s\n' "$@")
  for line in "$@"; do
    commands+=("${line#*"$(printf '\t')"}")
  done
  run policy_decisions "${commands[@]}"
  [ "$status" -eq 0 ] || fail "policy engine run failed:
$output"
  [ "$output" = "$expected" ] || fail "expected:
$expected
got:
$output"
}

# A rule the loader rejects is dropped with no error and the engine runs on
# whatever survived, so every decision below would resolve to the default and
# pass a test that only listed ask_user. Pin the compiled pattern instead.
@test "the destructive-command rule compiles and is in force" {
  require_gemini
  run policy_decisions --rules
  [ "$status" -eq 0 ] || fail "policy load failed:
$output"
  count=$(printf '%s\n' "$output" | sed -n 's/^rules'"$(printf '\t')"'//p')
  [ -n "$count" ] || fail "no rule count in:
$output"
  [ "$count" -gt 0 ] || fail "the policy compiled $count rules"
  assert_contains "$output" 'pattern'"$(printf '\t')"'"command":"(?:rm -rf \/|rm -[-A-Za-z0-9_=. ]* \/[\s"]|mkfs|dd if=|:\(\)\{)'
}

# The rule is anchored at the first character of the command, so the plain
# `rm -rf /` branch only fires when the path follows the flags immediately.
# Every command here has `/` as a whole argument.
@test "rm is denied when its target is root and a flag stands in between" {
  require_gemini
  assert_decisions \
    "$(printf 'deny\trm -rf --no-preserve-root /')" \
    "$(printf 'deny\trm --no-preserve-root -rf /')" \
    "$(printf 'deny\trm -fr /')" \
    "$(printf 'deny\trm -r -f /')" \
    "$(printf 'deny\trm -v build dist /')"
}

@test "the destructive-command rule still denies what it already caught" {
  require_gemini
  assert_decisions \
    "$(printf 'deny\trm -rf /')" \
    "$(printf 'deny\trm -rf /tmp/foo')" \
    "$(printf 'deny\tmkfs.ext4 /dev/sda1')" \
    "$(printf 'deny\tdd if=/dev/zero of=/dev/sda')" \
    "$(printf 'deny\t:(){ :|:& };:')" \
    "$(printf 'deny\tsudo rm foo')" \
    "$(printf 'deny\tcd /tmp && rm -rf /')"
}

# `deny` is a hard block, not a prompt. Every case here is a relative path with
# a slash in it, reached past a flag: the shape an earlier revision of the rule
# denied outright, including the one carrying the safe `--preserve-root`.
@test "a flagged relative path with a slash keeps its decision" {
  require_gemini
  assert_decisions \
    "$(printf 'ask_user\trm -rf -v build/dist')" \
    "$(printf 'ask_user\trm -rf -v dist/assets/js')" \
    "$(printf 'ask_user\trm -rf -v node_modules/.cache')" \
    "$(printf 'ask_user\trm -rf -i target/debug')" \
    "$(printf 'ask_user\trm -rf --verbose build/dist')" \
    "$(printf 'ask_user\trm -rf --one-file-system build/dist')" \
    "$(printf 'ask_user\trm -rf --preserve-root build/dist')" \
    "$(printf 'ask_user\trm -rf -- build/dist')" \
    "$(printf 'ask_user\tcd frontend && rm -rf -v dist/js')" \
    "$(printf 'ask_user\trm -rf -v build/')" \
    "$(printf 'ask_user\trm -rf -v dist/ obj/')"
}

# A deny on the whole command returns before `checkShellCommand` splits it, so
# a run that crosses a shell operator blocks the entire line. In every case
# here the slash is an operand of the *second* command, not of the rm.
@test "a slash belonging to a later sub-command keeps its decision" {
  require_gemini
  # The command substitutions below are the payload the rule must not match,
  # not code to run; single quotes are what keeps them literal.
  # shellcheck disable=SC2016
  assert_decisions \
    "$(printf 'ask_user\trm -rf build && cd /')" \
    "$(printf 'ask_user\trm -rf dist && du -sh /')" \
    "$(printf 'ask_user\trm -rf build ; df -h /')" \
    "$(printf 'ask_user\trm -rf build || ls /')" \
    "$(printf 'ask_user\trm -rf build | tee /')" \
    "$(printf 'ask_user\trm -rf build & cd /')" \
    "$(printf 'ask_user\trm -f log && grep -r foo /')" \
    "$(printf 'ask_user\trm -rf -v out && cd /')" \
    "$(printf 'ask_user\trm -rf build > /tmp/log')" \
    "$(printf 'ask_user\t(rm -rf build) && cd /')" \
    "$(printf 'ask_user\trm -rf $(cat list) /')" \
    "$(printf 'ask_user\trm -rf `cat list` /')" \
    "$(printf 'ask_user\trm -rf %s' "'a b' /")" \
    "$(printf 'ask_user\trm -rf build\ncd /')"
}

# The rule this one replaced spelled `rm -rf /|sudo|...` as a bare alternation
# and denied both of the middle two; `sudoku` is the word boundary the
# commandPrefix form supplies.
@test "ordinary developer commands keep the decisions they had" {
  require_gemini
  assert_decisions \
    "$(printf 'ask_user\trm -rf ./build')" \
    "$(printf 'ask_user\trm -rf build')" \
    "$(printf 'ask_user\trm -rf -v ./build')" \
    "$(printf 'ask_user\trm -f /tmp/lock')" \
    "$(printf 'ask_user\tsudoku')" \
    "$(printf 'allow\tgit commit -m "remove rf files"')" \
    "$(printf 'allow\techo sudo hello')"
}

# The bridge above calls the loader directly. This one runs the CLI, which
# reaches a policy file through its own settings merge and tier resolution, and
# it does so without a credential: policy files load at startup and the run
# stops later, at the auth check.
@test "the installed CLI loads the shipped policy without a diagnostic" {
  require_gemini
  run gemini_cli --prompt x --policy "$POLICY"
  assert_not_contains "$output" 'Policy file error'

  # Positive control. A probe that has never seen the diagnostic it is looking
  # for cannot distinguish a clean policy from a blind probe.
  broken="$BATS_TEST_TMPDIR/broken-policy.toml"
  printf '%s\n' \
    '[[rule]]' \
    'toolName = "run_shell_command"' \
    'commandRegex = "(?:rm (?:-\\S+ )*/)"' \
    'decision = "deny"' \
    'priority = 200' >"$broken"
  run gemini_cli --prompt x --policy "$broken"
  assert_contains "$output" 'Policy file error'
  assert_contains "$output" 'Unsafe regex pattern'
}

# GEMINI_MODEL pins an identifier that Google retires on its own schedule, and
# the CLI does not check one locally: a bogus model and a live one produce the
# same error when the key is bad, so only a real call tells them apart. This is
# the one test that spends a request, and the only one that needs a credential.
@test "the pinned Gemini model is still served" {
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
