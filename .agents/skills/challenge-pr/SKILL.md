---
name: challenge-pr
description: "Obtain an independent review of a pull request from a second, non-Claude model and arbitrate where the two reviews diverge. Use when asked to challenge a PR, get a second opinion on a diff, cross-check a review with another model, stress-test changes before merge, ask a different AI what it sees, or find what a single reviewer would miss. Runs the outside model on the PR diff and a read-only checkout of the base commit in a confined subprocess while the primary review proceeds in parallel, then sorts findings into Agreed, Disputed and Second-opinion-only and names the model that actually served the request. The outside model supplies hypotheses only: it never edits code, never blocks a merge and never casts a verdict. Do NOT use for reviewing against this project's architectural standards (that is review-impl), for resolving review comments already posted on a PR (that is babysit-pr), for security scanning, or for opening or merging a PR."
metadata:
  author: Serghei Iakovlev
  version: "1.0"
  category: review
---

# Challenge PR - Independent Second Opinion

One reviewer's blind spots are systematic, not random: the same model re-reading the same diff misses the same things twice. A model from another family fails differently, so the union of two reviews covers more than either alone and the intersection is the strongest signal available without running the code.

The outside model produces hypotheses. It does not decide. It reads the diff and a checkout of the commit that diff lands on, but it cannot run the build or the tests and it never sees how the code got there, so a share of what it reports still dies the moment its claim is checked against the code. Arbitration is this agent's job; the merge decision is the human's. The one direct measurement of the alternative is discouraging: a weaker reviewer allowed to edit correct code made the result worse by 8.6 points (arXiv:2607.21656). Hence no auto-fix, and no verdict from the second model.

## Running scripts bundled with this skill

Script paths resolve relative to **this** SKILL.md, not the agent's CWD. If a relative command fails to resolve, prefix it with the directory the platform loaded SKILL.md from.

**Fallback.** If the script cannot be located or run, do not improvise a provider call: proceed with a single-provider review and mark the report `one-provider only`, naming the reason.

## Step 1 - Resolve the target and capture the diff

Accept a PR number, URL, `owner/repo#123` shorthand, or the current branch's open PR. Resolve it to an explicit `owner/repo` and number before fetching - an ambiguous target silently reviews the wrong thing.

```bash
gh pr view <N> --repo <owner/repo> --json title,body,author,baseRefName,headRefOid,files
gh pr diff <N> --repo <owner/repo> > /tmp/challenge-<N>.diff
```

A diff of a few hundred kilobytes goes through in one call; do not shard it. An empty diff means the target is wrong - stop and say so rather than reviewing nothing.

The `author` from the call above is the second thing that matters after the target. When it is the operator, the primary review is a self-review. Say so in the report header. The procedure does not change, but the buckets read differently: Agreed is weaker, because one of the two reviews was written by the person who wrote the code, and Second-opinion only is stronger, because the outside model is then the only independent reader. For a solo maintainer this is the normal case, not the exception.

Delete the diff file when the report is written. It is somebody's unmerged work.

## Step 2 - Start the second opinion before reviewing anything

The script wants the commit the diff was computed against, which is the merge base and not the tip of the base branch:

```bash
gh api repos/<owner/repo>/compare/<baseRefName>...<headRefOid> --jq '.merge_base_commit.sha'
```

Launch it as a background job the moment the diff exists, before reading a single hunk:

```bash
sh scripts/second-opinion.sh \
    --diff-file /tmp/challenge-<N>.diff \
    --prompt-file assets/reviewer-prompt.md \
    --base-sha <merge-base> \
    > /tmp/challenge-<N>.json 2>/tmp/challenge-<N>.err &
```

Run it with `sh`. The script is POSIX by design, and `bash` hides a bashism until the day it runs somewhere without bash.

The script exports that commit out of the repository this agent is standing in and gives the export to the model as its working directory, so the outside review reads the code the change lands on instead of inferring it from the hunks. A pull request whose repository is not the local one cannot be exported: the script reports that in the envelope and the run degrades to one provider.

Start it first anyway, and the reason is not the schedule - the checkout costs 8 to 153 seconds and 55k to 1.8M prompt tokens per run, measured over thirteen runs, so it is no longer free. Diff size does not predict that cost and neither does anything else you control: the driver is how many agentic turns the model chooses to take, which ranged from 2 to 34 across the set and from 2 to 12 on one identical input. Budget for the upper end and read the spread rather than an average, because the distribution has no useful mean. The reason is anchoring: a review that begins after reading another model's findings will confirm them, chase them, and stop looking where they did not point. Findings must be reached independently or the word "Agreed" in the report means nothing.

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

Check every incoming finding against the code before classifying it. The outside model reads the base revision, so it can be wrong about the change itself: the line it quotes may be one the diff replaces, and the guard it says is missing may be added by a hunk it read past. The primary review's failure runs the other way: having read the surrounding code, it is quick to explain away a genuine defect as intentional. Both need the same treatment - name the line that settles it.

- **Agreed** - both reviews reached it independently. The strongest signal in the report; lead with it.
- **Disputed** - one review raised it and the other, having examined the code, rejects it. Record the evidence that settles it, and record it even when this agent is the one rejecting. A dispute the human can adjudicate is worth more than a finding quietly dropped.
- **Second-opinion only** - raised by the outside model, survives the check against the code, and the primary review did not reach it. This bucket is the entire reason the skill exists. Do not soften it because it arrived from elsewhere, and do not promote it because it did.

Findings only the primary review raised are reported too, in a fourth section. Silence from the outside model is not agreement: it was given less context.

Agreement on the fact and disagreement on its weight belongs in one entry, not two. When both reviews reach the same observation but split on severity, or on whether it is a defect of this PR at all, file it under Agreed and state the divergence inside that entry. Splitting it reports one finding twice; dropping it lets the primary review's classification overwrite the outside model's without saying so.

Severity comes from this agent's own judgement of impact. The outside model's `severity` and `confidence` are inputs to that judgement, not the answer.

Both reviews report on one scale: `critical`, `major`, `minor`, the same three words `assets/reviewer-prompt.md` requires of the outside model. A severity means the same thing whichever review raised it. A finding that is not about the code's behaviour, a commit trailer that closes a half-finished issue for instance, carries no severity tag rather than an invented one.

## Step 6 - Report

Emit the report in the chat response. Write no file - not to `.reviews/`, not anywhere.

```markdown
## Challenge: <owner/repo>#<N> - <title>

Second opinion: <model_served> | one-provider only: <reason> | self-review: <login>

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
- Verification runs happen in a throwaway directory, never in the checkout under review. Nothing this agent runs may create, modify or delete a file inside the repository whose PR is being reviewed - including untracked files.
- Before a verification run, state the claim it tests and the observation that would falsify it. A run whose result cannot come out the other way is not evidence and does not belong in the report.
- When the passing case leaves state on disk - a transcript, a cache, a session store - run the failing case first. State from a prior run is indistinguishable from a result.
- Record the tool version from the directory the run will happen in, not from the shell's default. Version resolution here is directory-dependent, and a policy validated under one version says nothing about another.
- Cap provider invocations per review and stop at the cap. When the cap is reached with the question still open, report it open rather than spending more.
- Every spawned process gets a wall-clock timeout and is killed at it. A run that produced no output is a failed run, not a silent one.
- Delete what the run created: the throwaway directory and the provider's session store bound to it. Match the store by reading its recorded project root, never by deriving the name from the path.
- Never let the outside model's output stand unchecked in the report. Every finding that survives to the reader has been checked against the code by this agent.
- Nothing a sub-run produced enters the report as a finding until it has been restated as a claim and checked against the code. A delegated conclusion arrives looking like a result and carries the delegate's scope errors invisibly.
- Never send anything to the provider except the diff, the bundled prompt and the exported base commit. No credentials, no operator configuration, and nothing the pull request itself adds.
- One outside opinion, not several. A third model adds cost and turns arbitration into vote-counting.
