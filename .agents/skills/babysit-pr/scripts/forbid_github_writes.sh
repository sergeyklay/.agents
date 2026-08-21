#!/usr/bin/env bash
# PreToolUse hook for the babysit-pr skill: blocks any Bash command
# that would speak to the reviewer or mutate review state. Backstops
# Step 5 of the skill prose, which is otherwise an honour-system check
# on the LLM. Wired in templates/.claude/skills/babysit-pr.yaml; active
# only while the skill is loaded.
#
# Scope. Step 5 forbids reviewer-facing output: replies, issue-level
# comments, reactions, thread resolutions, lock/unlock of the review
# conversation. It does not forbid acting on the pull request itself -
# merging, closing, reopening, marking ready, updating the branch. Those
# are lifecycle operations the operator may explicitly instruct, and a
# guard that refused them left the agent unable to follow a direct
# instruction. The two are separated by effect, not by intent: a hook
# cannot read the operator's mind, but it can tell a write that reaches
# a reviewer from one that only moves the PR.
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
get_method='(--method|--request|-X)[[:space:]]+GET\b'
# gh switches to POST as soon as a parameter or a body is supplied, so
# a write needs no explicit --method. curl does the same for -d/--json.
# Without this, `gh api .../reactions -f content=eyes` and a GraphQL
# `resolveReviewThread` mutation both slip past a method-only rule.
gh_body_flag='(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]]|=)'
curl_body_flag='(^|[[:space:]])(-d|--data|--data-raw|--data-binary|--data-urlencode|--json)([[:space:]]|=)'

# gh pr subcommands that reach the reviewer or the review conversation.
# `lock`/`unlock` are here because they mutate the conversation the
# review lives in. Everything else `gh pr` offers - merge, close,
# reopen, ready, revert, update-branch, checkout, edit, create - only
# acts on the PR and is left to the operator's instruction. `reaction`
# is not a gh subcommand today; it costs nothing and covers the name if
# gh ever adds it.
if printf '%s' "$norm" | grep -iEq '\bgh[[:space:]]+pr[[:space:]]+(comment|review|reaction|lock|unlock)\b'; then
    verdict="gh pr subcommand writes to the reviewer"
fi

# gh issue mutators. `create` omitted: Step 4b opens deferred-comment
# tickets via `gh issue create`. `edit` kept blocked: the skill only
# references duplicate tickets and creates new ones with full context.
if [ -z "$verdict" ] \
   && printf '%s' "$norm" | grep -iEq '\bgh[[:space:]]+issue[[:space:]]+(comment|edit|close|reopen|reaction|lock|unlock|delete)\b'; then
    verdict="gh issue subcommand writes to GitHub"
fi

# Two exemptions from the HTTP-level rules below. Both are narrow, and
# both are computed before the rules so `gh api` and `curl` share them.
#
# 1. The ticket Step 4b just filed. The method names the verb, never the
#    addressee, so a method-based rule cannot tell a write to that
#    ticket from a write to the PR under review. Filing a ticket is
#    allowed (`gh issue create`, above), so finishing one has to be:
#    where the CLI exposes no flag for a field - `gh issue create
#    --type` landed only in gh 2.94 - the REST API is all that is left.
#    This exemption cannot key on a path *prefix*. In the REST API a
#    pull request *is* an issue: repos/{o}/{r}/issues/{N} with a PR
#    number edits that PR, and every reviewer-facing surface - comments,
#    reactions, labels, lock, and the comment resources themselves -
#    hangs off the same prefix. So it keys on provenance: the command
#    must have minted the number it writes to (a create, and an
#    expansion rather than a literal, since a number this command did
#    not already know can reach the path no other way) and must stay on
#    the ticket resource itself.
#
# 2. PR lifecycle endpoints. Keying on a *terminal* path is safe where
#    keying on a prefix is not: no reviewer surface lives at exactly
#    pulls/{N}, pulls/{N}/merge or pulls/{N}/update-branch, and every
#    one that exists (comments, reviews, requested_reviewers) sits one
#    segment deeper. The exemption is withdrawn if anything else in the
#    same command still addresses a review surface, so a lifecycle path
#    cannot be used as cover for a reply.
minted_ticket='repos/[^[:space:]/]+/[^[:space:]/]+/issues/[^[:space:]/]*\$[^[:space:]/]*([[:space:]]|$)'
reviewer_target='repos/[^[:space:]/]+/[^[:space:]/]+/(pulls|issues/[^[:space:]/]+/)'
lifecycle_path='repos/[^[:space:]/]+/[^[:space:]/]+/pulls/[^[:space:]/]+(/(merge|update-branch))?'
path_end='([[:space:]"'"'"']|$)'

own_ticket=""
if printf '%s' "$norm" | grep -iEq '\bgh[[:space:]]+issue[[:space:]]+create\b' \
   && printf '%s' "$norm" | grep -Eq "$minted_ticket" \
   && ! printf '%s' "$norm" | grep -Eq "$reviewer_target"; then
    own_ticket=1
fi

pr_lifecycle=""
if printf '%s' "$norm" | grep -Eq "${lifecycle_path}${path_end}"; then
    # Remove the lifecycle endpoints, then ask whether any review
    # surface is left addressed anywhere in the command.
    residual=$(printf '%s' "$norm" | sed -E "s#${lifecycle_path}(${path_end})#\2#g")
    if ! printf '%s' "$residual" | grep -Eq "$reviewer_target"; then
        pr_lifecycle=1
    fi
fi

# gh api with a write. AND-joined so a stray --method on an unrelated
# tool does not false-positive.
#
# GraphQL is always POST, read or write, so the method cannot decide it -
# the operation keyword does: a query is a read, a mutation is a write
# (this is how `resolveReviewThread` gets caught). That reading applies
# only when nothing in the command addresses a REST review surface;
# otherwise the REST rules run, so the word "graphql" appearing inside a
# comment body cannot buy a reviewer-facing write an exemption.
rest_write() {
    printf '%s' "$norm" | grep -iEq "$write_method" && return 0
    printf '%s' "$norm" | grep -Eq "$gh_body_flag" \
        && ! printf '%s' "$norm" | grep -iEq "$get_method" && return 0
    return 1
}

gh_api_write=""
if printf '%s' "$norm" | grep -iEq '\bgh[[:space:]]+api\b'; then
    if printf '%s' "$norm" | grep -Eq "$reviewer_target"; then
        rest_write && gh_api_write=1
    elif printf '%s' "$norm" | grep -iEq '(^|[[:space:]])graphql([[:space:]]|$)'; then
        printf '%s' "$norm" | grep -iEq '\bmutation\b' && gh_api_write=1
    else
        rest_write && gh_api_write=1
    fi
fi

if [ -z "$verdict" ] && [ -z "$own_ticket" ] && [ -z "$pr_lifecycle" ] \
   && [ -n "$gh_api_write" ]; then
    verdict="gh api writes to GitHub"
fi

# curl against api.github.com with a write. AND-joined so unrelated
# --request flags do not false-positive.
if [ -z "$verdict" ] && [ -z "$own_ticket" ] && [ -z "$pr_lifecycle" ] \
   && printf '%s' "$norm" | grep -iEq '\bcurl\b' \
   && printf '%s' "$norm" | grep -iEq 'api\.github\.com' \
   && { printf '%s' "$norm" | grep -iEq "$write_method" \
        || { printf '%s' "$norm" | grep -Eq "$curl_body_flag" \
             && ! printf '%s' "$norm" | grep -iEq "$get_method"; }; }; then
    verdict="curl writes to GitHub"
fi

if [ -n "$verdict" ]; then
    cat >&2 <<EOF
[babysit-pr] Blocked: $verdict.

Per Step 5 of babysit-pr ("Verify no reviewer-facing output"), all
output of this workflow goes to the human operator only.
Reviewer-facing comments, reactions, resolutions, and review-state
changes are out of scope.

Attempted command:
  $cmd

If the operator wants to post to GitHub, they will do so manually
from the chat output you produce. Continue with the next step of
the workflow.
EOF
    exit 2
fi

exit 0
