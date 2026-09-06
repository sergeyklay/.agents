# Writing the entry

The writing rules behind Step 4 of `SKILL.md`, and a worked example of one change written twice: once at implementation altitude, once at changelog altitude. Read this before drafting any bullet.

Writing rules:

- **A changelog is an upgrade decision aid, not a user guide, API reference, design document, or implementation report.** Announce the final released behavior at the product boundary; leave setup sequences, exhaustive option lists, diagnostic catalogs, and implementation mechanics to reference documentation.
- **Lead with the capability or observable outcome.** A reader who sees only the first sentence should still know what was added, changed, fixed, removed, or deprecated.
- **Default to one bullet of one to three sentences.** Add a sentence only for a required user action, a compatibility or security consequence, or a material behavioral constraint. Concise does not mean shortest: retain a limitation when removing it would give users the wrong setup or runtime expectation.
- **Apply a clause-level relevance test.** Keep a clause only when it answers at least one of: what changed, what the user can now do, what the user must do, or what material behavior or limitation the user will observe. Omit clauses that only explain how the code validates, retries, falls back, maps protocol states, logs diagnostics, or organizes configuration.
- **Name public controls selectively.** Keep a CLI flag, configuration key, agent kind, API symbol, or error identifier when the reader needs that exact name to discover, enable, migrate, or react to the change. Do not inventory nested fields, accepted types, validation codes, or every new error kind; those belong in reference documentation unless automation or operator action depends on them.
- **Describe effects, not machinery.** Prefer "requests requiring human input end the attempt" to a list of protocol outcomes and retry branches. Preserve the source's exact scope: do not replace "attempt" with "run", or a conditional capability with an unconditional promise, merely to simplify the sentence.
- **Explain a limitation when the cause clarifies expectations.** "Token-based budgets do not apply because the protocol does not report token usage" is more useful than listing both facts separately. Do not add architectural rationale that does not change user action or expectations.
- **One bullet per logical change between releases.** A logical change is everything the consumer observes as a single unit of value. It may span multiple PRs and commits if they all deliver, refine, or fix the same capability within the release window.
- **Fold within-release churn.** If a feature is introduced in one PR and then corrected, polished, or adjusted in subsequent PRs before the release ships, all of that work produces **one** changelog entry describing the final state. From the consumer's perspective there was no intermediate broken state - only the delivered result.
- **Fold sub-fixes into the feature entry.** If a PR introduces a feature and also fixes a bug found during its implementation, describe the fix as part of the feature bullet. Only create a standalone Fixed entry when the PR's sole purpose is a bug fix that is independent of any in-progress feature.
- **Do not duplicate or silently rewrite an existing entry.** Fold freely into an entry written in the same session. If `[Unreleased]` already contains a committed entry for the same logical change, ask whether to update it; do not work around the approval boundary by appending a duplicate. Leave unrelated previous entries untouched, and never fold new work into a dated release.
- **Never document the absence of a change.** "No migration is required", "no new environment variables", "No operator action is required", "nothing to do here" describe non-events. The file records changes; a reader who finds no migration note concludes there is no migration. Positive operator facts are changes and stay: a required migration or manual step, a new or removed environment variable, a new permission or scope, a changed default. When the audience detected in Step 1 does not deploy the software, drop deploy mechanics in both directions - the negative assertion and the positive instruction - and keep only what that audience can act on.
- **Reference the issue/task when one exists; fall back to the PR otherwise.** Each bullet ends with a parenthetical reference using a full URL (plain `#NNN` or bare tracker keys are not clickable in rendered markdown). When a tracker issue/task is linked from the PR, reference **the issue/task only** - not also the PR. When multiple distinct issues/tasks are linked, list all of them. See `references/trackers.md` for the URL format matching the detected tracker.
- Start each bullet with what changed, not with "Fixed" or "Added" (the heading already says that).
- Be specific: "`coroutine 'main' was never awaited` bug after async migration" not "Fixed async bug".
- Identify the subsystem when it helps locate the change, using the labels detected in Step 1 (e.g. `API:`, `CLI:`, `Auth:`, `Dashboard:`).
- Reference types or functions in backticks when they help the reader.
- Do not copy git commit messages verbatim - rewrite for a human reader.

Use this integration example as the target altitude:

**Too implementation-heavy:**

```markdown
- A new agent kind runs protocol-compatible runtimes. Set its command and optional nested MCP configuration; validation emits a dedicated wrong-type code. Permission requests map to protocol refusal, two non-retried error kinds cover declined and unknown outcomes, continuation falls back to a fresh session, and a notice lists unsupported runtime capabilities.
```

**Changelog-ready:**

```markdown
- The new `agent-client-protocol` agent kind runs Agent Client Protocol-compatible runtimes over stdio and resumes previous sessions when supported by the runtime. Locally launched runtimes can use workflow-configured MCP servers, while requests requiring human input are refused or end the attempt rather than waiting indefinitely. Token-based budgets do not apply because the protocol does not report token usage. ([#976](https://github.com/sortie-ai/sortie/issues/976))
```

The second form is not minimal for its own sake: it retains the exact public capability and the constraints that affect session continuity, configuration, control flow, and budgeting, while dropping setup syntax, validation codes, error taxonomy, session fallback mechanics, and diagnostic notices.
