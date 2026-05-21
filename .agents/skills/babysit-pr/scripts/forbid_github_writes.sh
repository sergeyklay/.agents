#!/usr/bin/env bash
# PreToolUse hook for the babysit-pr skill: blocks any Bash command
# that would write to GitHub. Backstops Step 5 of the skill prose,
# which is otherwise an honour-system check on the LLM. Wired in
# templates/.claude/skills/babysit-pr.yaml; active only while the
# skill is loaded.
#
# Contract: read PreToolUse JSON from stdin, exit 0 to allow, exit
# 2 to block. stderr on a block is shown to the model.

set -eu

input=$(cat)

# Fail open when jq is missing: a missing tool must not block
# legitimate calls, and the skill prose still forbids the action.
if ! command -v jq >/dev/null 2>&1; then
    printf '[babysit-pr hook] jq not found on PATH; cannot inspect command, allowing.\n' >&2
    exit 0
fi

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$cmd" ] && exit 0

# Strip up to two layers of `<shell> -c "..."` wrapping so the
# patterns match the underlying command. Deeper nesting is exotic
# enough to escalate visibly rather than slip past.
norm="$cmd"
i=0
while [ "$i" -lt 2 ]; do
    stripped=$(printf '%s' "$norm" | sed -E "s/^[[:space:]]*(bash|sh|zsh|dash)[[:space:]]+-c[[:space:]]+['\"]?(.*)['\"]?[[:space:]]*$/\2/")
    if [ "$stripped" = "$norm" ]; then
        break
    fi
    norm=$stripped
    i=$((i + 1))
done

verdict=""
write_method='(--method|--request|-X)[[:space:]]+(POST|PATCH|PUT|DELETE)\b'

# gh pr mutators. Two intentional omissions:
#   - `create`: out of scope (resolve-review operates on an existing PR).
#   - `edit`: the agent legitimately updates PR description/metadata
#     while applying review fixes - reviewer-visible but part of the
#     work product, not a reply to the reviewer.
if printf '%s' "$norm" | grep -iEq '\bgh[[:space:]]+pr[[:space:]]+(comment|review|close|reopen|reaction|lock|unlock|delete|merge|ready|draft)\b'; then
    verdict="gh pr subcommand writes to GitHub"
fi

# gh issue mutators. `create` omitted: Step 4b opens deferred-comment
# tickets via `gh issue create`. `edit` kept blocked: the skill only
# references duplicate tickets and creates new ones with full context.
if [ -z "$verdict" ] \
   && printf '%s' "$norm" | grep -iEq '\bgh[[:space:]]+issue[[:space:]]+(comment|edit|close|reopen|reaction|lock|unlock|delete)\b'; then
    verdict="gh issue subcommand writes to GitHub"
fi

# gh api with a writing HTTP method. AND-joined so a stray --method
# on an unrelated tool does not false-positive.
if [ -z "$verdict" ] \
   && printf '%s' "$norm" | grep -iEq '\bgh[[:space:]]+api\b' \
   && printf '%s' "$norm" | grep -iEq "$write_method"; then
    verdict="gh api writes to GitHub"
fi

# curl against api.github.com with a writing HTTP method. AND-joined
# so unrelated --request flags do not false-positive.
if [ -z "$verdict" ] \
   && printf '%s' "$norm" | grep -iEq '\bcurl\b' \
   && printf '%s' "$norm" | grep -iEq 'api\.github\.com' \
   && printf '%s' "$norm" | grep -iEq "$write_method"; then
    verdict="curl writes to GitHub"
fi

if [ -n "$verdict" ]; then
    cat >&2 <<EOF
[babysit-pr] Blocked: $verdict.

Per Step 5 of babysit-pr ("Verify no reviewer-facing output"), all
output of this workflow goes to the human operator only.
Reviewer-facing comments, reactions, resolutions, and PR or issue
state changes are out of scope.

Attempted command:
  $cmd

If the operator wants to post to GitHub, they will do so manually
from the chat output you produce. Continue with the next step of
the workflow.
EOF
    exit 2
fi

exit 0
