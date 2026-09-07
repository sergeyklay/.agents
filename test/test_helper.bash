ROOT=$(CDPATH="" cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/scripts/install.sh"
# Consumed by the .bats files via `load`; shellcheck cannot follow that.
# shellcheck disable=SC2034
CONTEXT="$ROOT/.agents/AGENTS.md"

bats_require_minimum_version 1.5.0

# bats-support's `fail` is not bundled; this local equivalent keeps the
# suite dependency-free: print the message and return non-zero.
fail() {
  printf '%s\n' "$*" >&2
  return 1
}

# writing-specs validator output bands (see skills.bats).
# shellcheck disable=SC2034
BUDGET_WARNING='if it covers more than one independently shippable goal'
# shellcheck disable=SC2034
SPLIT_GUIDANCE='Ask the user whether to split it into two'

setup() {
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/.codex" "$TEST_HOME/.copilot" \
    "$TEST_HOME/.gemini" "$TEST_HOME/.config/opencode"
}

# Runs the installer against $TEST_HOME; use under `run` to capture output.
install_into() {
  NO_COLOR=1 TERM=xterm HOME="$TEST_HOME" sh "$INSTALLER" "$@"
}

# Runs the installer from a copied repository whose sources the test mutates.
install_from() {
  local repo=$1
  shift
  NO_COLOR=1 TERM=xterm HOME="$TEST_HOME" sh "$repo/scripts/install.sh" "$@"
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

assert_absent() {
  [ ! -e "$1" ] || fail "expected absent: $1"
}

assert_same() {
  cmp -s -- "$1" "$2" || fail "expected identical files: $1 $2"
}

# Callers must `|| return 1`: bats clears errexit inside `run`, so a bare
# call prints the refusal and the assertion proceeds anyway.
have_needle() {
  [ -n "$1" ] || fail "refusing to match $2 against an empty needle"
}

assert_contains() {
  have_needle "$2" 'output' || return 1
  case $1 in
  *"$2"*) ;;
  *) fail "expected output to contain: $2" ;;
  esac
}

assert_not_contains() {
  case $1 in
  *"$2"*) fail "expected output not to contain: $2" ;;
  esac
}

assert_file_contains() {
  have_needle "$2" "$1" || return 1
  grep -qF -- "$2" "$1" || fail "expected $1 to contain: $2"
}

frontmatter_of() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next }
       inside && $0 == "---" { exit }
       inside { print }' "$1"
}

assert_frontmatter() {
  have_needle "$2" "the frontmatter of $1" || return 1
  frontmatter_of "$1" | grep -qxF "$2" || fail "expected frontmatter line in $1: $2"
}

assert_no_frontmatter_key() {
  have_needle "$2" "the frontmatter keys of $1" || return 1
  if frontmatter_of "$1" | grep -q "^$2:"; then
    fail "unexpected frontmatter key in $1: $2"
  fi
}

# Write a spec of exactly $1 words, to drive the validator's word budget.
filler_spec() {
  awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) print "word" }' >"$2"
}

# First non-empty line past optional YAML frontmatter; files without
# frontmatter are body from line 1.
first_body_line() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next }
       NR == 1                 { body = 1 }
       inside && $0 == "---"   { inside = 0; body = 1; next }
       body && NF              { print; exit }' "$1"
}

# tomllib is stdlib only from Python 3.11 and CI sets up no interpreter, so a
# missing tomllib is reachable. Probe python3 and tomllib separately so the
# message names the real cause instead of a traceback blaming a valid file.
assert_toml_parses() {
  if ! command -v python3 >/dev/null 2>&1; then
    fail "need python3 3.11+ with tomllib to validate $1; found no python3 on PATH"
  fi
  if ! python3 -c 'import tomllib' 2>/dev/null; then
    fail "need python3 3.11+ with tomllib to validate $1; found $(python3 -V 2>&1)"
  fi
  python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1" ||
    fail "expected valid TOML: $1"
}
