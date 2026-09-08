#!/bin/sh

# The headings come from the shipped template, never from a copy here: a
# second copy is the drift this hook exists to prevent.

set -eu

CLAUDE_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")/.." && pwd)
TEMPLATE="$CLAUDE_DIR/skills/create-pr/assets/pull_request_template.md"

# Without jq there is no decision to make, and a non-zero exit would only
# add a hook error to every Bash call, so decline rather than fail.
command -v jq >/dev/null 2>&1 || exit 0

command=$(jq -r '.tool_input.command // ""')

case $command in
*'gh pr create'* | *'gh pr edit'*) ;;
*) exit 0 ;;
esac

# --body-file shares this prefix, so one pattern covers both spellings.
case $command in
*--body*) ;;
*) exit 0 ;;
esac

if [ ! -r "$TEMPLATE" ]; then
  printf 'Refusing gh pr: cannot read the PR template at %s\n' "$TEMPLATE" >&2
  exit 2
fi

# The body reaches us quoted, with newlines and apostrophes intact, so the
# whole command line is searched rather than unquoted into an argument.
body=$command
body_file=$(printf '%s' "$command" |
  sed -n "s/.*--body-file[ =]*['\"]\{0,1\}\([^'\" ]*\).*/\1/p")
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
