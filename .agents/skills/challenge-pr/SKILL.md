---
name: challenge-pr
description: "Obtain an independent review of a pull request from a second, non-Claude model and arbitrate where the two reviews diverge. Use when asked to challenge a PR, get a second opinion on a diff, cross-check a review with another model, stress-test changes before merge, ask a different AI what it sees, or find what a single reviewer would miss. Cuts the PR diff into units and runs the outside model over them in a confined subprocess while the primary review proceeds in parallel, then checks every incoming finding against the code and reports the survivors as one ranked list. The outside model supplies hypotheses only: it never edits code, never blocks a merge and never casts a verdict. Do NOT use for reviewing against this project's architectural standards (that is review-impl), for resolving review comments already posted on a PR (that is babysit-pr), for security scanning, or for opening or merging a PR."
metadata:
  author: Serghei Iakovlev
  version: "1.0"
  category: review
---

# Challenge PR - Independent Second Opinion

One reviewer's blind spots are systematic, not random: the same model re-reading the same diff misses the same things twice. A model from another family fails differently, so the union of two reviews covers more than either alone and the intersection is the strongest signal available without running the code.

The outside model produces hypotheses. It does not decide. It reads one unit of the diff at a time and nothing else - no repository, no build, no history - so two thirds of what it reports dies the moment its claim is checked against the code. Arbitration is this agent's job; the merge decision is the human's. The one direct measurement of the alternative is discouraging: a weaker reviewer allowed to edit correct code made the result worse by 8.6 points (arXiv:2607.21656). Hence no auto-fix, and no verdict from the second model.

## Running scripts bundled with this skill

Script paths resolve relative to **this** SKILL.md, not the agent's CWD. If a relative command fails to resolve, prefix it with the directory the platform loaded SKILL.md from.

**Fallback.** If the script cannot be located or run, do not improvise a provider call: proceed with a single-provider review and disclose that the second opinion never ran, naming the reason.

## Step 1 - Resolve the target and capture the diff

Accept a PR number, URL, `owner/repo#123` shorthand, or the current branch's open PR. Resolve it to an explicit `owner/repo` and number before fetching - an ambiguous target silently reviews the wrong thing.

```bash
gh pr view <N> --repo <owner/repo> --json title,body,author,baseRefName,headRefOid,files,additions,deletions
gh pr diff <N> --repo <owner/repo> > /tmp/challenge-<N>.diff
```

`gh pr diff` returns the whole diff in one call whatever its size; the cutting Step 2 needs happens inside the script. An empty diff means the target is wrong - stop and say so rather than reviewing nothing.

Screen 2 of the report prints the commit the diff was computed against, which is the merge base and not the tip of the base branch:

```bash
gh api repos/<owner/repo>/compare/<baseRefName>...<headRefOid> --jq '.merge_base_commit.sha'
```

Nothing else consumes it - the second opinion is not given a revision to read.

The `author` from the call above is the second thing that matters after the target, and `files`, `additions` and `deletions` are what the report header counts. When the author is the operator, the primary review is a self-review. The procedure does not change, but the weighting in Step 5 does: two reviews reaching the same finding proves less, because one of them was written by the person who wrote the code, and a finding only the outside model raised proves more, because it is then the only independent reading. For a solo maintainer this is the normal case, not the exception.

Delete the diff file when the report is written. It is somebody's unmerged work.

## Step 2 - Start the second opinion before reviewing anything

Launch it as a background job the moment the diff exists, before reading a single hunk:

```bash
sh scripts/second-opinion.sh \
    --diff-file /tmp/challenge-<N>.diff \
    --prompt-file assets/reviewer-prompt.md \
    > /tmp/challenge-<N>.json 2>/tmp/challenge-<N>.err &
```

Run it with `sh`. The script is POSIX by design, and `bash` hides a bashism until the day it runs somewhere without bash.

The script cuts the diff into units of under 150 changed lines - a file at a time, a large file hunk by hunk, each unit still a valid diff - and makes one provider call per unit, merging every unit's findings into one envelope. The cutting is the entire reason the second opinion produces anything. The same diff handed over whole returned zero findings in eighteen runs across every context configuration tried; cut this way it returned four of the eight defects a human reviewer had found on the same pull request. Nothing about the request changed except how much of it arrived at once.

Those four came from two passes over every unit, and the passes taken separately reached three and two. The script makes one pass.

The model gets a unit on stdin, an empty working directory and no tools at all. Giving it the code the change lands on was measured too, and it is what buys noise: the same units with a read-only checkout of the base commit produced 82% false findings against 8% without one, cost 25 times the tokens, and moved the count of real defects by one.

The default model is Pro-class, overridable with `--model`. Class is where completeness came from: on the identical construction the Pro-class model found four reference defects to the flash-class model's one, for 1.56 times the tokens.

Start it first, and the reason is not the schedule - the run costs 917k tokens and about 1900 seconds on a pull request that cuts into 38 units, so it is not free, though it is now predictable: one call per unit, and no agentic turns to make the cost vary. The reason is anchoring: a review that begins after reading another model's findings will confirm them, chase them, and stop looking where they did not point. Findings must be reached independently or the second review is an echo of the first.

Do not read the output file yet. Do not run the script in the foreground.

## Step 3 - Review the diff yourself while it runs

Conduct a full review as if no second opinion were coming. Read the changed files at their current revision, not only the hunks - the diff hides the guard clause three lines above the change. Follow callers of anything whose contract moved.

Write the findings down before Step 4. A finding not recorded before the envelope is opened cannot be claimed as independent.

Keep a second record beside them: which of the PR's files were opened, and what was actually run. Step 6 prints it, and nothing else can supply it afterwards - the envelope reports findings and says nothing about coverage, and by then the memory of which files got opened is a guess.

## Step 4 - Open the envelope

The script emits a single JSON object:

```json
{"provider": "…", "model_served": "…", "findings": [], "error": null}
```

`provider` and `model_served` name which model actually served the run, read back from the provider's own accounting rather than from what was requested. Neither reaches the report.

`error` non-null, or the script exiting non-zero, or the file not being JSON: the second opinion is unavailable. Continue with the primary review alone and disclose the gap where Step 6 puts it. An empty `findings` array with `error: null` is a different thing - the outside model reviewed the diff and raised nothing. Never conflate the two.

If the job is still running by the time Step 3 is done, wait briefly, then proceed without it. The second opinion adds coverage; it never blocks.

## Step 5 - Arbitrate

Check every finding against the code before it can reach the report, whichever review raised it. This is where most of the second opinion goes: of 143 findings measured on one pull request, 95 - two in three - failed the check, against 20 that survived. Arbitration is not a formality laid over a mostly-correct list; it is the step that decides whether this skill helps or floods the report.

The outside model sees one unit and nothing around it, which is where its errors come from: it calls a guard missing that another hunk adds, a symbol undefined that the diff never had to show, and a file truncated when the rest of it went to another unit. The primary review's failure runs the other way: having read the surrounding code, it is quick to explain away a genuine defect as intentional. Both need the same treatment - name the line that settles it.

A finding that survives the check is reported once, ranked by impact, with no trace of where it came from. A finding that fails is not reported at all.

Where a finding came from still governs how this agent weighs it. A finding the outside model raised alone is the entire reason the skill exists: do not soften it because it arrived from elsewhere, and do not promote it because it did. And silence from the outside model is not agreement, since it was given less context, so a finding the primary review raised alone stands on the same footing as any other.

The same observation reached by both reviews is one entry, not two. When they split on severity, or on whether it is a defect of this PR at all, this agent settles it rather than reporting the finding twice.

Severity comes from this agent's own judgement of impact. The outside model's `severity` and `confidence` are inputs to that judgement, not the answer.

Both reviews report on one scale: `critical`, `major`, `minor`, the same three words `assets/reviewer-prompt.md` requires of the outside model. A severity means the same thing whichever review raised it. A finding that is not about the code's behaviour, a commit trailer that closes a half-finished issue for instance, carries no severity rather than an invented one.

## Step 6 - Report

Emit the report in the chat response. Write no file - not to `.reviews/`, not anywhere. Print the first screen and stop there. The second screen goes out only when the operator asks for it.

Both screens print in the language of the conversation. The closing line of each offers a phrase the operator is meant to type back, so it is translated along with everything else; paths, identifiers and counts are not.

Nothing about how the review was produced reaches either screen: no provider, no model name, no run count, no cost, no token figures, no note of which review raised what, and no rebuttal of a finding that failed the check in Step 5. Findings that failed are dropped there, not argued with in front of the reader. The reader is looking at a pull request, not at this tool.

The reader is also in a terminal of unknown width. Blank lines, headings, lists and bold survive any rewrapping; columns, padding, box drawing and hard-wrapped paragraphs do not. Write no line whose alignment carries meaning. The bolded `file:line` opens an entry so it stays attached to its own text when the line wraps.

Two tiers reach the reader: what blocks the merge, and what should be handled before it. The `critical`, `major`, `minor` scale of Step 5 decides which tier an entry lands in and is never printed. A tier with no entries is not printed either.

### Screen 1

```markdown
**#<N>** · <title> · <n> files · +<added>/-<deleted>

**<b> blockers, <m> notes.**

- `<file:line>` - what is wrong, in one line
- `<file:line>` - what is wrong, in one line

Read <k> of <n> files, tests not run.

Full breakdown - say "walk me through it". A single finding - say "show me reconcile.go:501".
```

Only blockers get bullets here. With none, the count line says so in words and no bullets follow it.

`Read <k> of <n> files` is the one figure in the report that is not about the diff, and its only source is the record Step 3 required: the files this agent opened, counted against `files` from Step 1, and the runs it actually made. The envelope carries findings and nothing about coverage, so nothing else can supply it. Never estimate the count, never infer it from the diff or from the hunks that got quoted, and never write `tests not run` or its opposite from memory of how the run felt. Without that record, drop the sentence: a figure that reads as a measurement and is a guess is worse than no figure.

### Screen 2

```markdown
**#<N>** · <title> · base `<sha>` · <n> files · +<added>/-<deleted>

### Blocking

**`<file:line>`** - what the code does, the input or state that makes it wrong, and what it costs. Name what the diff alone does not show when that is the point.

### Before merge

- **`<file:line>`** - one line: mechanism and consequence.

### Not checked

<n-k> files never opened: `<a>`, `<b>`, `<c>`. Tests not run, migrations not applied.

Comment drafts for the PR - say "draft them". I will not post them myself.
```

Blocking entries are paragraphs, one each. Everything else is a one-line bullet. `Not checked` names what the Step 3 record says was never opened and never run, under the same ban on guessing, and it is where a second opinion that never arrived is disclosed - unavailable coverage the reader would otherwise assume.

Asked for one finding by name, print that entry alone in the form `Blocking` uses. An open question this agent could not settle belongs inside the entry it came from, or in `Not checked` when it belongs to no single finding. Neither screen ends in a verdict.

## Constraints

- Never edit code, never commit, never push. This skill produces an opinion, not a patch.
- Never post to GitHub: no review, no comment, no approval, no request-for-changes. The report goes to the operator, who decides what reaches the PR.
- Verification runs happen in a throwaway directory, never in the checkout under review. Nothing this agent runs may create, modify or delete a file inside the repository whose PR is being reviewed - including untracked files.
- Before a verification run, state the claim it tests and the observation that would falsify it. A run whose result cannot come out the other way is not evidence and does not belong in the report.
- When the passing case leaves state on disk - a transcript, a cache, a session store - run the failing case first. State from a prior run is indistinguishable from a result.
- Record the tool version from the directory the run will happen in, not from the shell's default. Version resolution here is directory-dependent, and a policy validated under one version says nothing about another.
- One call per unit is the whole provider budget for a review. When a question is still open after the envelope arrives, report it open rather than spending another run on it.
- Every spawned process gets a wall-clock timeout and is killed at it. A run that produced no output is a failed run, not a silent one.
- Delete what the run created: the throwaway directory and the provider's session store bound to it. Match the store by reading its recorded project root, never by deriving the name from the path.
- Never let the outside model's output stand unchecked in the report. Every finding that survives to the reader has been checked against the code by this agent.
- Nothing a sub-run produced enters the report as a finding until it has been restated as a claim and checked against the code. A delegated conclusion arrives looking like a result and carries the delegate's scope errors invisibly.
- Never send anything to the provider except the units of the diff and the bundled prompt. No credentials, no operator configuration, no revision of the repository, and nothing the pull request itself adds.
- One outside opinion, not several. A third model adds cost and turns arbitration into vote-counting.
