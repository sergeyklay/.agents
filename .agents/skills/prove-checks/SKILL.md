---
name: prove-checks
description: "Prove a passing check was capable of failing before recording it as evidence. Use when a test, CI job, build-and-diff, smoke test or rehearsal comes back green and that green is about to be treated as proof - especially when the check depends on a setup mutation (a sed/awk rewrite, an env var, a secret, a fixture file, a branch or working-copy state), when a job passes under continue-on-error, `|| true`, `set +e` or warning-only output, when an event-driven workflow is hand-run while nothing has changed, or when simulating a future input such as the next release. Covers asserting the precondition actually took effect, confirming the subject rather than the receiver was exercised, stripping failure suppressors, and running a negative control. Do NOT use for zero-hit searches or absence claims (that is research-it), or for authoring unit tests in a specific language (that is test-go or test-ts)."
metadata:
  author: Serghei Iakovlev
  version: "1.0"
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
- Blank the secret, delete the fixture, or feed the old value.
- Corrupt one field the assertion is supposed to notice.

Restore, re-run, confirm green. A check never observed red is an unproven check. This is the inverse of `research-it`'s positive control: that one proves the instrument can see; this one proves the instrument can object.

**When the positive run leaves state behind, run the negative control first.** Files, caches, session history, database rows: anything the positive run writes whose absence the negative control is checking turns that control into a reading of the previous run's litter. A deny-all tool policy was checked by feeding an agent CLI empty stdin and asserting it could not name a secret sentinel; it named the sentinel anyway, having grepped the CLI's own transcripts from the earlier positive run. That measured leftovers, not isolation. Give every run a fresh working directory and a fresh random sentinel, so a hit cannot be a trace of the last one.

### 6. Record the scope, not a verdict

Write down what was exercised and what was not: "the receiver's no-op path ran; the sender is unverified" beats "release notification works". Verdicts outlive their evidence.

## Validation

Green counts as evidence only when all of these hold:

- [ ] The red condition was stated before the run.
- [ ] Every setup mutation was read back through an independent path and asserted non-empty / changed / matching the new value.
- [ ] The half of the system under test was exercised, and the observable side-effect is named — not just an exit code.
- [ ] No suppressor sits between the failure and the exit status, or the assertion targets a required log line instead.
- [ ] The check has been observed red at least once for the defect it claims to catch.

Any unticked box downgrades the result from "verified" to "not contradicted".

## Anti-patterns

- **Reading a no-op as a pass.** The workflow ran, exited 0, and changed nothing because there was nothing to change. It exercised the guard, not the work.
- **Trusting a mutating command's exit code.** `sed`, `jq`, `yq`, `xmlstarlet` and most templating tools exit 0 on zero matches. The edit that silently did nothing is the most common cause of a vacuous pass.
- **Building before syncing.** A rehearsal on a working copy that is behind the remote produces old output; the comparison then confirms the old output, in detail, convincingly.
- **Warning-shaped failures.** A step that prints a warning and exits 0 turns a broken release into a green one. Warnings are for things that are allowed to be false.
- **Treating repetition as confirmation.** Re-running the same vacuous check with different parameters returns the same green. Setup-level failures are perfectly correlated across runs, exactly like instrument-level failures are across queries.
- **Accepting another agent's account of the tree.** A subagent reporting that it restored, reverted or reconstructed files is reporting its intent and its memory, not the filesystem. The tree is a different path; hash it.
- **Skipping the negative control because it is inconvenient.** It is one revert and one re-run, and it is the only step that distinguishes a check from a ritual.
