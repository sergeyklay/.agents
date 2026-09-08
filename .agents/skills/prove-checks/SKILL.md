---
name: prove-checks
description: "Prove a passing check was capable of failing before recording it as evidence. Use when a test, CI job, build-and-diff, smoke test or rehearsal comes back green and that green is about to be treated as proof - especially when the check depends on a setup mutation (a sed/awk rewrite, an env var, a secret, a fixture file, a branch or working-copy state), when a job passes under continue-on-error, `|| true`, `set +e` or warning-only output, when an event-driven workflow is hand-run while nothing has changed, when simulating a future input such as the next release, or when a flaky or racy fix is about to be called verified. Covers asserting the precondition actually took effect, confirming the subject rather than the receiver was exercised, stripping failure suppressors, and running a negative control, which a race needs forced, not reverted. Do NOT use for zero-hit searches or absence claims (that is research-it), or for authoring unit tests in a specific language (that is test-go or test-ts)."
metadata:
  author: Serghei Iakovlev
  version: "1.2"
  category: testing
---

# Prove the Check Can Fail

A green result is evidence only if red was reachable. Every check runs in a state, and when that state is wrong the check does not error — it passes, cheaply and convincingly. The failure is silent by construction: nothing in the output distinguishes "the system works" from "the system was never asked".

Three ways a check goes green without testing anything:

| Shape | What happened | What green meant |
|---|---|---|
| Setup no-op | The mutation the check depends on never applied | The check compared the old state to itself |
| Subject not exercised | Only the downstream half ran, or it ran its no-op branch | The upstream half is still unverified |
| Failure suppressed | The failure path was routed to a warning or a forced exit 0 | Exit status carries no information |
| Subject substituted | The named target was unreachable and the tool silently chose another one | The work was done correctly, on the wrong thing |

## Trigger

Run this before recording any green as proof, and always when one of these is true:

- The check depends on a setup mutation: an in-place text edit, an env var, a secret, a generated fixture, a checked-out revision, a temporary config override.
- The job or step is wrapped in `continue-on-error`, `|| true`, `set +e`, `if: always()`, or emits `::warning::`/`echo` instead of a non-zero exit.
- An event-driven pipeline was hand-run: a `workflow_dispatch` on something whose real trigger is a `repository_dispatch`, a webhook, a tag push, or a release.
- The run is a rehearsal of a future input ("simulate the next release", "pretend the version bumped", "assume the API returns X").
- The check passed on the first attempt after a change that should have been hard.

Not this skill: a search returning zero hits, or a claim that something is absent — those are `research-it` (silent-zero results, format-assumption false negatives, summariser-bounded negatives), including when the absent thing is a third-party capability.

## Procedure

### 1. State the red condition

Write, in one sentence, the defect this check catches and what its output looks like when it catches it. If that sentence cannot be written, the check is decorative — stop and redesign it before running it again.

### 2. Assert the precondition took effect

Never infer that a mutation applied from the mutating command's exit status. Most of them succeed on zero matches.

| Mutation | Assertion (read the state back, not the command's exit code) |
|---|---|
| `sed -i` / `perl -pi` / scripted edit | Re-read the file and match the **new** value; `grep -c` it and require a non-zero count. `sed` exits 0 when the pattern matched nothing. |
| Working-copy revision | `git fetch` then require `git rev-list --count @..@{u}` to be `0`, before any build. A build from a stale copy renders stale output and diffs clean against stale expectations. |
| Env var or secret | Assert non-empty inside the job that consumes it and exit non-zero if unset. A missing secret expands to the empty string, not an error. |
| Generated fixture or artifact | Stat it, read it back, and check a distinguishing field — not just that the path exists. |
| Multi-file write by an agent tool | List the directory afterwards (`find <dir> -type f`) and match it against every intended path. A per-file success message reports the tool's intent, not the filesystem; a batch can report success for each write while only the last one survives. |
| Agent-reported restoration of files it destroyed | Hash each file (`git hash-object <path>`) and compare against what you recorded from your own earlier read. An agent that reverted or overwrote work and then reports restoring it "byte-for-byte" is quoting its own memory, not the filesystem - and one file of a pair can match exactly while another silently differs. |
| Service/container/branch state | Query it through its own API, not through the command that was supposed to change it. |

The rule underneath the table: **verify through a different path than the one that wrote**. The writing path is the thing under suspicion.

### 3. Confirm the subject, not the receiver, was exercised

For any pipeline with a sender and a receiver, name both, then say which one this run touched. Hand-running the receiver proves the receiver parses its input; it says nothing about whether the sender ever sends. The evidence to look for is the **observable side-effect** — a dispatch event delivered, a commit written, an outbound request logged, a row changed — not the receiver's exit code.

A run that legitimately no-ops (nothing changed, so nothing to do) is the weakest possible evidence: it exercised the guard clause and returned. Record it as "the no-op path works".

### 4. Strip the suppressors before believing the exit code

Grep the job or script for `continue-on-error`, `|| true`, `set +e`, `|| exit 0`, trap handlers, and warning-only reporting. Each one severs exit status from correctness. Where one is present and intentional, the check must assert on a **log line or artifact** the step is required to produce, because green no longer means anything. Where it is not intentional, remove it.

### 5. Run the negative control

Break the thing on purpose and confirm the check turns red:

- Revert the fix, or point the check at the pre-fix revision. Copy the file aside before you break it and restore from that copy; never with `git checkout --`, `git restore` or `git reset`, which take every uncommitted change in the tree with them.
- Run the control in a throwaway `git worktree` rather than in the tree you are working in. An interrupted control then cannot leave a half-broken file where the next command reads it, and a parallel session's uncommitted work is out of reach by construction rather than by care.
- Blank the secret, delete the fixture, or feed the old value.
- Corrupt one field the assertion is supposed to notice.

Restore, re-run, confirm green. A check never observed red is an unproven check. This is the inverse of `research-it`'s positive control: that one proves the instrument can see; this one proves the instrument can object.

**When the subject is a guard, weaken it as well as remove it. Removal is the weaker control.** Removal deletes the mechanism and asks whether it does anything. Weakening leaves it in place and breaks only its decision, its return value, or its exit path, and asks whether the check notices when the guard stops protecting. Removal also takes the guard's message, its log line, and its other side effects with it, so the check can go red on one of those while the behavior under protection goes untested. An assertion helper that refuses an empty needle was controlled by deleting the refusal, and the regression test went red on the missing refusal text; keeping the refusal and making it return success left the same test green with the helper fully disarmed.

**A weakening control means nothing on a fixture that cannot reach the defect.** The guard exists because some input makes the protected code pass without checking anything, and unless the fixture carries that input the disarmed code still fails on an unrelated branch, so the check stays green either way and the control never goes red. Build the fixture from the defect's own condition, then isolate that condition: delete it alone, re-run, and confirm the weakening control goes green. The helper above needed a blank line inside its fixture's frontmatter, because a blank line is the one thing an empty needle matches; without it the disarmed helper failed on a missing match instead of passing vacuously, and the test could not tell the two apart.

**When the positive run leaves state behind, run the negative control first.** Files, caches, session history, database rows: anything the positive run writes whose absence the negative control is checking turns that control into a reading of the previous run's litter. A deny-all tool policy was checked by feeding an agent CLI empty stdin and asserting it could not name a secret sentinel; it named the sentinel anyway, having grepped the CLI's own transcripts from the earlier positive run. That measured leftovers, not isolation. Give every run a fresh working directory and a fresh random sentinel, so a hit cannot be a trace of the last one.

**A negative arm asserting that a remote call never happened is settled by the dependency's own record, not by the exit code or the clock.** A fast non-zero exit is equally consistent with a call that was issued and discarded and with one that was never made. Read the count out of the tool's own store, its session rows, its request log, or the provider's usage, and show that same counter non-zero from the positive arm first, or the zero is an unread instrument rather than a result.

**Reap what the red run leaks, and never reap it by pattern.** A control that ends red usually leaves the subprocess tree it was asserting about still running, because the assertion returned before its own cleanup. The next run then reads the survivors of the previous one. Clean up explicitly: kill the process group the check created, or register the teardown with the test framework so a failed assertion still runs it. Do not reach for `pkill -f <pattern>` to do it. The pattern is a substring of the command line of the shell issuing the command, so the shell matches itself and dies mid-command, surfacing as an unexplained non-zero status with no output rather than as anything resembling the mistake it was. Match the exact command line instead, and skip your own process tree.

**When the defect is intermittent, reverting the fix is not a control.** A deterministic bug turns the reverted check red every run; a race turns it red only on the losing interleaving, so the control can come up green by luck and be recorded as proof the check never caught anything. Restore the losing order instead of the old code: hold the concurrent work until after the assertion reads, remove the synchronisation the fix introduced and pin the scheduling, or make the racing call settle late. Two conditions bind that control. It must go red on the assertion the race itself produces, because a sabotage that trips a compile error or an unrelated throw turns the check red for a reason the defect never causes. And a race with two losing orders needs one control per order, since fixing the side that was observed tends to relocate the failure to the side that was not.

**A repeat run confirms nothing until its length is derived from the measured rate.** Zero failures in N runs bounds the true rate at roughly `3/N`, so a green series excludes a rate `p` only once N reaches `3/p`. Measure `p` before the fix, over a loop long enough to see failures, and report the bound rather than the count: a rate observed at one in six is not excluded by twelve green runs, which bound it only at one in four and which the unfixed code itself would produce about one time in nine. Group the failures by which assertion they land on, too — failures that alternate between opposite assertions are the two halves of one race, not two unrelated flakes.

**Take a repeat loop's command from the project's own runner, and make it count itself.** A hand-rolled invocation drops whatever the real runner supplies — the gate variable that turns a suite on, its concurrency limit, its reporter — and each omission fails silently: a suite whose gate is unset skips by design and exits 0, so every iteration is green having executed nothing. Then require the number of iterations that produced a parsable result to equal the number requested, and abort when it is short. Without that guard a runner that rejected its own arguments, and so exited before doing any work, yields empty output that a tally reads as an unbroken series of passes.

### 6. Record the scope, not a verdict

Write down what was exercised and what was not: "the receiver's no-op path ran; the sender is unverified" beats "release notification works". Verdicts outlive their evidence.

## Validation

Green counts as evidence only when all of these hold:

- [ ] The red condition was stated before the run.
- [ ] Every setup mutation was read back through an independent path and asserted non-empty / changed / matching the new value.
- [ ] The half of the system under test was exercised, and the observable side-effect is named — not just an exit code.
- [ ] No suppressor sits between the failure and the exit status, or the assertion targets a required log line instead.
- [ ] The check has been observed red at least once for the defect it claims to catch.
- [ ] Where the subject is a guard, the control broke the guard's decision rather than deleting the guard, on a fixture that reaches the defect.
- [ ] Where the defect is intermittent, the control forced the losing order rather than reverting the fix, once per losing order.
- [ ] Any green series offered as evidence states the rate bound it buys, not the run count alone.

Any unticked box downgrades the result from "verified" to "not contradicted".

## Anti-patterns

- **Reading a no-op as a pass.** The workflow ran, exited 0, and changed nothing because there was nothing to change. It exercised the guard, not the work.
- **Trusting a mutating command's exit code.** `sed`, `jq`, `yq`, `xmlstarlet` and most templating tools exit 0 on zero matches. The edit that silently did nothing is the most common cause of a vacuous pass.
- **Building before syncing.** A rehearsal on a working copy that is behind the remote produces old output; the comparison then confirms the old output, in detail, convincingly.
- **Warning-shaped failures.** A step that prints a warning and exits 0 turns a broken release into a green one. Warnings are for things that are allowed to be false.
- **Treating repetition as confirmation.** Re-running the same vacuous check with different parameters returns the same green. Setup-level failures are perfectly correlated across runs, exactly like instrument-level failures are across queries.
- **Accepting another agent's account of the tree.** A subagent reporting that it restored, reverted or reconstructed files is reporting its intent and its memory, not the filesystem. The tree is a different path; hash it.
- **Controlling a guard by deleting it.** Removal takes the guard's message and its side effects with it, so the check can go red on any of those while the behavior the guard protects stays untested. Break the decision, keep the mechanism.
- **Reverting a probabilistic fix and calling the result a control.** The reverted check is a coin flip; when it lands green the conclusion drawn is that the check never caught the defect, which is exactly backwards.
- **Quoting the repeat count instead of the bound.** The number of green runs is an input. What it buys is an upper bound on the failure rate, and below `3/p` it does not even exclude the rate measured before the fix.
- **Skipping the negative control because it is inconvenient.** It is one revert and one re-run, and it is the only step that distinguishes a check from a ritual.
