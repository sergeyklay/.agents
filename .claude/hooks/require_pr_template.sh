#!/bin/sh

# The headings come from the shipped template, never from a copy here: a
# second copy is the drift this hook exists to prevent.

set -eu

CLAUDE_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")/.." && pwd)
TEMPLATE="$CLAUDE_DIR/skills/create-pr/assets/pull_request_template.md"

# Without jq there is no decision to make, and a non-zero exit would only
# add a hook error to every Bash call, so decline rather than fail.
command -v jq >/dev/null 2>&1 || exit 0

# A payload jq rejects is the same absent decision, and set -e would turn
# jq's failure into the per-call hook error the guard above avoids.
command=$(jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

# Matched anywhere, `gh pr create` refuses the echo or commit message that
# merely quotes it, so anchor it to command position past any VAR=value.
GH_PR_CALL='(^|[;&|(`])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+(create|edit)([[:space:]]|$)'
printf '%s\n' "$command" | grep -qE "$GH_PR_CALL" || exit 0

# --body-file shares this prefix, so one pattern covers both spellings.
printf '%s\n' "$command" |
  grep -qE '(^|[[:space:]])--body(-file)?([[:space:]=]|$)' || exit 0

if [ ! -r "$TEMPLATE" ]; then
  printf 'Refusing gh pr: cannot read the PR template at %s\n' "$TEMPLATE" >&2
  exit 2
fi

# The body reaches us quoted, with newlines and apostrophes intact, so the
# whole command line is searched rather than unquoted into an argument.
body=$command
# A quoted path runs to its closing quote; only a bare path ends at a space.
body_file=$(printf '%s' "$command" | sed -n \
  -e "s/.*--body-file[ =]*\"\([^\"]*\)\".*/\1/p;t" \
  -e "s/.*--body-file[ =]*'\([^']*\)'.*/\1/p;t" \
  -e "s/.*--body-file[ =]*\([^'\" ]*\).*/\1/p")
if [ -n "$body_file" ] && [ -r "$body_file" ]; then
  body="$body
$(cat -- "$body_file")"
fi

# A `#` inside a fenced example is a comment, not a heading the body must carry.
missing=$(awk '/^ *(```|~~~)/ { fenced = !fenced; next }
     !fenced && /^#{1,6} / { print }' "$TEMPLATE" |
  while IFS= read -r heading; do
    printf '%s' "$body" | grep -qF -- "$heading" || printf '  %s\n' "$heading"
  done)

[ -n "$missing" ] || exit 0

printf 'Refusing gh pr: the body omits headings the PR template defines.\n\n' >&2
printf 'Missing:\n%s\n\n' "$missing" >&2
printf 'Read %s and reproduce its headings verbatim.\n' "$TEMPLATE" >&2
exit 2
