# Anti-patterns

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
