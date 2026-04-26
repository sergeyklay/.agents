---
name: log-changes
description: "Use when asked to update the changelog, document version changes, prepare a release, or add entries for recent work. Handles CHANGELOG.md updates following Keep a Changelog format and Semantic Versioning. Do NOT use for committing or creating release notes outside CHANGELOG.md."
metadata:
  author: Serghei Iakovlev
  version: "1.1"
  category: documentation
---

# Changelog Maintenance

The changelog records notable changes to the distributed software. Every entry must answer: "Does this change affect someone who uses, upgrades, deploys, or integrates with the project?" If not, omit it.

Format authority: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## Project constants

Detect the following constants from the project itself - do not ask the user unless detection fails. Inspect, in order: existing CHANGELOG.md entries, project documentation (README.md, CONTRIBUTING.md, docs/), and recent git commit messages.

1. **GitHub repository slug (`OWNER/REPO`).** Read existing comparison links at the bottom of CHANGELOG.md (preferred). Fall back to `git remote get-url origin` and parse the slug from the URL.
2. **Issue tracker.** Look for tracker references in existing CHANGELOG entries, PR templates, contributing docs, and recent commit messages:
   - **GitHub Issues** - links of the form `https://github.com/OWNER/REPO/issues/NNN`, or closing keywords `closes/fixes/resolves #NNN` in commit/PR bodies.
   - **Jira** - task keys of the form `[A-Z]+-[0-9]+` (e.g. `ABC-123`) or links to `*.atlassian.net/browse/...`.
   - **Linear** - keys like `ENG-123` or links to `https://linear.app/...`.
   - **Other trackers** - distinct ID schemes or links in commit/PR bodies.

   For non-GitHub trackers, also detect the tracker base URL and the project key prefix (e.g. `BP`, `ABC`, `ENG`).
3. **Subsystem labels.** Read existing CHANGELOG entries to learn which subsystem prefixes the project already uses (e.g. `API:`, `CLI:`, `Auth:`). If none exist, propose labels that match the project's top-level directory or package layout. The human reviewer will correct any that are wrong.

Use the detected values everywhere a project key, tracker URL, or GitHub URL is needed. If a constant cannot be determined with confidence, ask the user once before proceeding. Do not guess or invent values.

## When to use

- Adding entries for new features, fixes, or breaking changes.
- Preparing a release: moving Unreleased entries under a versioned heading.
- Creating CHANGELOG.md from scratch when it does not exist.

## Workflow

### Step 1: Read the current changelog

CHANGELOG.md, if it exists, lives at the repository root. Read it first. If the file does not exist, create it from `assets/changelog-template.md` (see Step 5).

### Step 2: Gather changes

**The merged PR is the atomic unit of a changelog entry - not the commit.** A single PR often contains the feature commit, follow-up fixes, review feedback, test additions, and docs updates. These are one logical change and produce one changelog bullet. Never split a PR's commits into separate entries.

#### 2a: Identify the release window

```bash
# Last tag, its date (window start), and recent tags for context
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
git log -1 --format="%ai" "$LAST_TAG"
git tag --sort=-version:refname | head -10
```

If no tags exist, treat the entire git history as the unreleased window. The release window is: tag date (exclusive) → today.

#### 2b: List merged PRs in the window

**Primary: milestone-based** (when the project sets milestones on PRs; replace `MILESTONE_PREFIX` with the prefix the project uses, e.g. `M10`):

```bash
gh pr list --state merged --limit 100 \
  --json number,title,mergedAt,milestone,labels \
  --jq '.[] | select(.milestone != null and (.milestone.title | startswith("MILESTONE_PREFIX")))
        | "\(.number)\t\(.mergedAt | split("T")[0])\t\(.title)"' \
  | sort -t$'\t' -k2
```

**Fallback: date-based** (when milestones are not set; replace YYYY-MM-DD with the tag date):

```bash
gh pr list --state merged --limit 200 \
  --json number,title,mergedAt,labels \
  --jq '.[] | select(.mergedAt >= "YYYY-MM-DDT00:00:00Z")
        | "\(.number)\t\(.mergedAt | split("T")[0])\t\(.title)"' \
  | sort -t$'\t' -k2
```

For non-GitHub trackers, also fetch resolved tasks within the same window using the tracker's search API or web UI - see `references/trackers.md` for the section matching the detected tracker.

#### 2c: Inspect individual PRs and link to tracker tasks

```bash
# PR title, body (scope/intent), and constituent commits
gh pr view <NUMBER> --json title,body --jq '"\(.title)\n\(.body)"' | head -40
gh pr view <NUMBER> --json commits --jq '.commits[].messageHeadline'
```

Extract issue/task references from the PR body using the extraction commands in `references/trackers.md` for the tracker detected in Step 1. Read each linked issue/task for the user-facing problem statement: PR titles are implementation-focused, tracker items are user/operator-focused.

Use the PR body's **Scope & Context** section (when present) to understand the user-facing or operator-facing impact. Do not rely on `git log --oneline` - it shows commits, not logical changes.

If the user describes changes verbally, use that as the primary source.

### Step 3: Filter - decide what belongs

The changelog records **notable changes to the distributed software**. A change is notable when it alters what a consumer of the project can observe: new capabilities, changed behavior, fixed bugs, security patches, removed features, or deprecation notices.

Apply the following filter to every commit or change before writing an entry.

**ALWAYS include:**

| Signal                                                                                     | Why it matters to consumers           |
| ------------------------------------------------------------------------------------------ | ------------------------------------- |
| New user-facing feature (CLI flag, integration, config option, API surface, UI capability) | Consumers discover new capabilities   |
| Changed behavior of existing feature                                                       | Consumers must adjust usage           |
| Bug fix for incorrect behavior                                                             | Consumers know issues are resolved    |
| Security or vulnerability fix                                                              | Operators must act on upgrades        |
| Deprecation of public interface                                                            | Consumers prepare for removal         |
| Removal of feature or public interface                                                     | Consumers must adapt before upgrading |
| Performance improvement with measurable impact                                             | Consumers benefit from upgrading      |
| New or changed persistence schema (migration)                                              | Operators plan upgrade procedures     |
| Changed CLI flags, env vars, deployment, or config file format                             | Operators must update deployment config |

**NEVER include - these are noise, not signal:**

| Noise                                                     | Why it does not belong                |
| --------------------------------------------------------- | ------------------------------------- |
| Internal variable/function/type renames                   | No observable effect on consumers     |
| Code formatting, whitespace, linting fixes                | No observable effect on consumers     |
| Test-only changes (new tests, test refactors)             | Not shipped to consumers              |
| CI/CD pipeline changes (workflows, actions)               | Not shipped to consumers              |
| Dotfile changes (`.gitignore`, `.github/*`, `CODEOWNERS`) | Not shipped to consumers              |
| Documentation-only changes (README, AGENTS.md, comments)  | Not shipped to consumers              |
| Merge commits                                             | Infrastructure artifact, not a change |
| Internal refactoring with no behavior change              | No observable effect on consumers     |
| Dev-only dependency bumps                                 | Not shipped to consumers              |
| Project scaffolding and repo housekeeping                 | Not shipped to consumers              |

**Edge cases - include only when the threshold is met:**

| Change                         | Include when...                                                  | Omit when...                            |
| ------------------------------ | ---------------------------------------------------------------- | --------------------------------------- |
| Dependency bump                | Major version, security fix, or changed behavior                 | Routine patch/minor with no user impact |
| Refactoring                    | It changes observable performance, error messages, or log output | Purely internal restructuring           |
| New internal module/package    | It introduces a new adapter or public API surface                | It reorganizes existing code            |
| ADR or architecture doc update | It records a decision that changes system behavior               | It clarifies existing behavior          |

When in doubt, ask: "If I were a consumer of this project reading this before
upgrading, would I need to know this?" If the answer is no, leave it out.

### Step 4: Classify each change

Place every surviving entry under exactly one category:

| Category       | When to use                                                                  |
| -------------- | ---------------------------------------------------------------------------- |
| **Added**      | New user-facing capability: CLI command, integration, config option, API surface, UI capability |
| **Changed**    | Existing behavior altered in a way consumers can observe                     |
| **Deprecated** | Still works but scheduled for removal in a future version                    |
| **Removed**    | Previously available feature or interface deleted                            |
| **Fixed**      | Bug fix - incorrect behavior corrected                                       |
| **Security**   | Vulnerability patch, dependency CVE fix                                      |

Writing rules:

- **One bullet per logical change between releases.** A logical change is everything the consumer observes as a single unit of value. It may span multiple PRs and commits if they all deliver, refine, or fix the same capability within the release window.
- **Fold within-release churn.** If a feature is introduced in one PR and then corrected, polished, or adjusted in subsequent PRs before the release ships, all of that work produces **one** changelog entry describing the final state. From the consumer's perspective there was no intermediate broken state - only the delivered result.
- **Fold sub-fixes into the feature entry.** If a PR introduces a feature and also fixes a bug found during its implementation, describe the fix as part of the feature bullet. Only create a standalone Fixed entry when the PR's sole purpose is a bug fix that is independent of any in-progress feature.
- **Reference the issue/task when one exists; fall back to the PR otherwise.** Each bullet ends with a parenthetical reference using a full URL (plain `#NNN` or bare tracker keys are not clickable in rendered markdown). When a tracker issue/task is linked from the PR, reference **the issue/task only** - not also the PR. When multiple distinct issues/tasks are linked, list all of them. See `references/trackers.md` for the URL format matching the detected tracker.
- Start each bullet with what changed, not with "Fixed" or "Added" (the heading already says that).
- Be specific: "`coroutine 'main' was never awaited` bug after async migration" not "Fixed async bug".
- Identify the subsystem when it helps locate the change, using the labels detected in Step 1 (e.g. `API:`, `CLI:`, `Auth:`, `Dashboard:`).
- Reference types or functions in backticks when they help the reader.
- Do not copy git commit messages verbatim - rewrite for a human reader.

### Step 5: Write the entry

Use `assets/changelog-template.md` as the structural template when creating CHANGELOG.md from scratch or adding the first versioned section. The template covers the preamble, `[Unreleased]` placeholder, a versioned section, and bottom comparison links.

Structural rules:

- Reverse chronological order (newest first).
- `[Unreleased]` section always present at the top.
- Dates in ISO 8601 (`YYYY-MM-DD`).
- Comparison links at the bottom for every version.
- Empty categories are omitted (no `### Removed` if nothing was removed).

### Step 6: Determine the version bump

When cutting a release, choose the version number:

| Bump      | Trigger                                               |
| --------- | ----------------------------------------------------- |
| **Major** | Breaking API/CLI change for users or operators, removed public functionality |
| **Minor** | New feature, backward-compatible behavior change      |
| **Patch** | Bug fix, security patch                               |

To cut a release:

1. Replace `## [Unreleased]` with `## [X.Y.Z] - YYYY-MM-DD`.
2. Add a fresh empty `## [Unreleased]` section above it.
3. Update the comparison links at the bottom.

### Step 7: Verify

- [ ] Every entry passes the filter from Step 3 (no noise).
- [ ] Newest version is at the top.
- [ ] Every version has a date (except Unreleased).
- [ ] Bottom links are correct and complete.
- [ ] No empty category headings.
- [ ] No git-log copy-paste - entries are human-readable.
- [ ] Entries identify the subsystem where helpful.
- [ ] Tracker references are full URLs, not bare keys or plain `#NNN`.
- [ ] When an issue/task exists, the bullet references the issue/task only - not also the PR.
- [ ] **If the project's tracker is not GitHub Issues:** no `https://github.com/OWNER/REPO/issues/NNN` links are present in the changelog.

## Error Recovery

| Problem                    | Fix                                                        |
| -------------------------- | ---------------------------------------------------------- |
| Missing comparison links   | Reconstruct from `git tag --sort=-version:refname`         |
| Duplicate entries          | Deduplicate, keep the more descriptive version             |
| Entry under wrong category | Move it; if ambiguous, prefer Changed over Added           |
| No tags in repository      | Use commit SHAs in comparison links as a temporary measure |
| Noise entry slipped in     | Remove it - a leaner changelog is more trustworthy         |

## Anti-Patterns

| Anti-pattern | Why it's wrong | Correct approach |
| --- | --- | --- |
| One entry per commit | Commits are implementation steps, not logical changes. A 6-commit PR produces one changelog bullet. | Use `gh pr list` to enumerate PRs; write one bullet per logical change. |
| Using `git log --oneline` as the primary source | Produces commit-level noise: test commits, review feedback, merge commits, formatting fixes. | Query merged PRs via `gh pr list --state merged` filtered by milestone or date range since the last git tag. |
| Plain `#NNN` references | Not clickable in rendered markdown - readers must manually construct the URL to navigate to the change. | Use full URLs (see `references/trackers.md`). |
| Including both the issue/task and the PR in one bullet | Doubles the noise and misleads the reader: the issue/task already describes the user-visible problem, the PR is its implementation. | Reference the issue/task only when one exists; fall back to the PR only when no issue/task is available. |
| Bare tracker keys (e.g. `BP-123`, `ENG-42`) | Not clickable; readers cannot navigate to the task without knowing the tracker URL. | Use the full tracker URL (see `references/trackers.md`). |
| GitHub Issue links in changelog **when the project's tracker is not GitHub Issues** | The detected tracker is the authoritative source for task references. Adding `/issues/NNN` links is misleading and breaks over time as the GitHub Issues tab is unused. | Use tracker links for all task references; GitHub links remain only for PRs. |
