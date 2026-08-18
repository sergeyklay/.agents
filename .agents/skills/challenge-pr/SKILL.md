---
name: challenge-pr
description: "Obtain an independent review of a pull request from a second, non-Claude model and arbitrate where the two reviews diverge. Use when asked to challenge a PR, get a second opinion on a diff, cross-check a review with another model, stress-test changes before merge, ask a different AI what it sees, or find what a single reviewer would miss. Runs the outside model on the PR diff in a tool-denied subprocess while the primary review proceeds in parallel, then sorts findings into Agreed, Disputed and Second-opinion-only and names the model that actually served the request. The outside model supplies hypotheses only: it never edits code, never blocks a merge and never casts a verdict. Do NOT use for reviewing against this project's architectural standards (that is review-impl), for resolving review comments already posted on a PR (that is babysit-pr), for security scanning, or for opening or merging a PR."
metadata:
  author: Serghei Iakovlev
  version: "1.0"
  category: review
---

# Challenge PR - Independent Second Opinion

One reviewer's blind spots are systematic, not random: the same model re-reading the same diff misses the same things twice. A model from another family fails differently, so the union of two reviews covers more than either alone and the intersection is the strongest signal available without running the code.

The outside model produces hypotheses. It does not decide. It sees the diff and nothing else - no repository, no history, no build - so a large share of what it reports dies the moment its claim is checked against the surrounding code. Arbitration is this agent's job; the merge decision is the human's. The one direct measurement of the alternative is discouraging: a weaker reviewer allowed to edit correct code made the result worse by 8.6 points (arXiv:2607.21656). Hence no auto-fix, and no verdict from the second model.

## Running scripts bundled with this skill

Script paths resolve relative to **this** SKILL.md, not the agent's CWD. If a relative command fails to resolve, prefix it with the directory the platform loaded SKILL.md from.

**Fallback.** If the script cannot be located or run, do not improvise a provider call: proceed with a single-provider review and mark the report `one-provider only`, naming the reason.

## Step 1 - Resolve the target and capture the diff

Accept a PR number, URL, `owner/repo#123` shorthand, or the current branch's open PR. Resolve it to an explicit `owner/repo` and number before fetching - an ambiguous target silently reviews the wrong thing.

```bash
gh pr view <N> --repo <owner/repo> --json title,body,author,baseRefName,files
gh pr diff <N> --repo <owner/repo> > /tmp/challenge-<N>.diff
```

A diff of a few hundred kilobytes goes through in one call; do not shard it. An empty diff means the target is wrong - stop and say so rather than reviewing nothing.

Delete the diff file when the report is written. It is somebody's unmerged work.

## Step 2 - Start the second opinion before reviewing anything

Launch it as a background job the moment the diff exists, before reading a single hunk:

```bash
scripts/second-opinion.sh \
    --diff-file /tmp/challenge-<N>.diff \
    --prompt-file assets/reviewer-prompt.md \
    > /tmp/challenge-<N>.json 2>/tmp/challenge-<N>.err &
```

This ordering is mandatory for two reasons, and the weaker one is the schedule. The subprocess takes roughly fifteen seconds and the primary review takes minutes, so starting it first costs nothing. The reason that matters is anchoring: a review that begins after reading another model's findings will confirm them, chase them, and stop looking where they did not point. Findings must be reached independently or the word "Agreed" in the report means nothing.

Do not read the output file yet. Do not run the script in the foreground.

## Step 3 - Review the diff yourself while it runs

Conduct a full review as if no second opinion were coming. Read the changed files at their current revision, not only the hunks - the diff hides the guard clause three lines above the change. Follow callers of anything whose contract moved.

Write the findings down before Step 4. A finding not recorded before the envelope is opened cannot be claimed as independent.

## Step 4 - Open the envelope

The script emits a single JSON object:

```json
{"provider": "…", "model_served": "…", "findings": [], "error": null}
```

`model_served` is read back from the provider's own accounting, not from what was requested and not from what the model says about itself - a model asked to name itself answers with whatever name is most common in its training data, and a requested alias may be served by something else entirely. Report the served value verbatim; it is what makes the run reproducible.

`error` non-null, or the script exiting non-zero, or the file not being JSON: the second opinion is unavailable. Mark the report `one-provider only` with the reason and continue. An empty `findings` array with `error: null` is a different thing - the outside model reviewed the diff and raised nothing. Never conflate the two.

If the job is still running by the time Step 3 is done, wait briefly, then proceed without it. The second opinion adds coverage; it never blocks.

## Step 5 - Arbitrate

Check every incoming finding against the code before classifying it. The outside model reasons from the diff alone, so its most common failure is reporting a defect that the unchanged context already handles. The primary review's failure runs the other way: having read the surrounding code, it is quick to explain away a genuine defect as intentional. Both need the same treatment - name the line that settles it.

- **Agreed** - both reviews reached it independently. The strongest signal in the report; lead with it.
- **Disputed** - one review raised it and the other, having examined the code, rejects it. Record the evidence that settles it, and record it even when this agent is the one rejecting. A dispute the human can adjudicate is worth more than a finding quietly dropped.
- **Second-opinion only** - raised by the outside model, survives the check against the code, and the primary review did not reach it. This bucket is the entire reason the skill exists. Do not soften it because it arrived from elsewhere, and do not promote it because it did.

Findings only the primary review raised are reported too, in a fourth section. Silence from the outside model is not agreement: it was given less context.

Severity comes from this agent's own judgement of impact. The outside model's `severity` and `confidence` are inputs to that judgement, not the answer.

## Step 6 - Report

Emit the report in the chat response. Write no file - not to `.reviews/`, not anywhere.

```markdown
## Challenge: <owner/repo>#<N> - <title>

Second opinion: <model_served> | one-provider only: <reason>

### Agreed (n)
- **[severity] `file:lines`** - claim. Evidence: <the line that proves it>.

### Disputed (n)
- **[raised by: outside model | primary] `file:lines`** - claim. Rejected because <evidence>.

### Second-opinion only (n)
- **[severity, confidence] `file:lines`** - claim. Bites when <condition>. Unverified because <what could not be checked>.

### Primary only (n)
- **[severity] `file:lines`** - claim. Evidence: <…>.
```

Drop empty sections rather than printing "None". Close with the open question the human has to settle, if there is one - not with a verdict.

## Constraints

- Never edit code, never commit, never push. This skill produces an opinion, not a patch.
- Never post to GitHub: no review, no comment, no approval, no request-for-changes. The report goes to the operator, who decides what reaches the PR.
- Never let the outside model's output stand unchecked in the report. Every finding that survives to the reader has been checked against the code by this agent.
- Never send anything to the provider except the diff and the bundled prompt. No repository files, no context files, no credentials.
- One outside opinion, not several. A third model adds cost and turns arbitration into vote-counting.
