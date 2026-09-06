---
name: log-changes
description: "Use when asked to update the changelog, document version changes, prepare a release, or add entries for recent work, and when reviewing a diff or pull request that touches CHANGELOG.md. Produces concise user-facing CHANGELOG.md entries, follows Keep a Changelog and Semantic Versioning, and verifies that new bullets sit under [Unreleased] rather than a published version. Do NOT use for committing, user guides, or release notes outside CHANGELOG.md."
metadata:
  author: Serghei Iakovlev
  version: "1.5"
  category: documentation
---

# Changelog Maintenance

The changelog records notable changes to the distributed software. Every entry must answer: "Does this change affect someone who uses, upgrades, deploys, or integrates with the project?" If not, omit it.

Format authority: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## Project constants

Detect the following constants from the project itself - do not ask the user unless detection fails. Inspect, in order: existing CHANGELOG.md entries, project documentation (README.md, CONTRIBUTING.md, docs/), and recent git commit messages.

Seven constants: the GitHub repository slug, the issue tracker with its base URL and key prefix, the subsystem labels, the entry unit, the bullet order within a category, the audience, and the product surface. How to detect each one, and what to fall back to when the first probe fails, is in [references/project-constants.md](references/project-constants.md).

Use the detected values everywhere a project key, tracker URL, or GitHub URL is needed. If a constant cannot be determined with confidence, ask the user once before proceeding. Do not guess or invent values.

## When to use

- Adding entries for new features, fixes, or breaking changes.
- Preparing a release: moving Unreleased entries under a versioned heading.
- Creating CHANGELOG.md from scratch when it does not exist.
- Reviewing a diff or pull request that touches CHANGELOG.md: a hunk header names the category, never the enclosing version.

## Workflow

### Step 1: Read the current changelog

CHANGELOG.md, if it exists, lives at the repository root. Read it first. If the file does not exist, create it from `assets/changelog-template.md` (see Step 5).

### Step 2: Gather changes

**The merged PR is the minimum evidence unit - not necessarily the changelog entry unit.** Inspect each PR as a whole rather than turning its commits into bullets, then group PRs by the logical change users receive. One PR can produce one entry; several PRs that introduce, refine, or fix the same unreleased feature produce one combined entry describing its final state.

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

Before drafting, reduce the evidence to four facts:

1. **Capability or outcome:** what can the user do now, or what observable behavior changed?
2. **Required action:** must the user configure, migrate, upgrade, or respond differently?
3. **Material constraints:** which limitations change setup or reasonable operator expectations?
4. **Implementation evidence:** which internals prove the change but do not belong in the entry? Use these to verify accuracy, then discard them from the prose.

### Step 3: Filter - decide what belongs

The changelog records **notable changes to the distributed software**. A change is notable when it alters what a consumer of the project can observe: new capabilities, changed behavior, fixed bugs, security patches, removed features, or deprecation notices.

Apply the following filter to every commit or change before writing an entry.

The signals that always belong, the noise that never does, and the edge cases with their thresholds are tabulated in [references/entry-filter.md](references/entry-filter.md). Open it before drafting, and again for any change you cannot place from the paragraph above.

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

The writing rules and a worked altitude example are in [references/entry-style.md](references/entry-style.md). They govern how much of the change survives into prose, when a CLI flag or API symbol earns its name, how several PRs fold into one bullet, why an entry never asserts the absence of a change, and how a bullet cites its issue or task. Read it before drafting any bullet.

### Step 5: Write the entry

Use `assets/changelog-template.md` as the structural template when creating CHANGELOG.md from scratch or adding the first versioned section. The template covers the preamble, `[Unreleased]` placeholder, a versioned section, and bottom comparison links.

Structural rules:

- Versions in reverse chronological order (newest release first).
- Bullets inside a category follow the one convention detected in Step 1 - newest-first by default. One convention per file: a section written in the opposite direction from its neighbours is a defect, and it stays invisible for months because each section reads fine on its own.
- `[Unreleased]` section always present at the top.
- Dates in ISO 8601 (`YYYY-MM-DD`).
- Comparison links at the bottom for every version.
- Empty categories are omitted (no `### Removed` if nothing was removed).

Dated release sections are shipped history and are not edited when logging new work. New entries go under `## [Unreleased]` only.

This collides with how a changelog is laid out: `### Added`, `### Fixed`, and the rest repeat once per version, so the first `### Fixed` in the file usually belongs to the newest *release*, not to `[Unreleased]`. An edit anchored on a bare category heading lands in shipped history. Anchor instead on text unique to the Unreleased window - the preceding bullet's tracker URL, or the pair of the category heading and the following `## [x.y.z]` header. When `[Unreleased]` lacks the category you need, create it inside that window rather than reusing a released version's heading.

When a deliberate edit does span released sections - a policy change such as purging a class of sentence from every entry - treat prose integrity as part of the operation. Removing a sentence from the middle or end of a bullet leaves dangling connectors and punctuation (`... and never falls back to it. No new OAuth scope,`), and a sweep leaves trailing whitespace behind. Re-read every bullet you touched as a whole sentence, not as a diff.

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
- [ ] PRs that deliver or refine the same unreleased user-facing change are consolidated into one bullet describing the final behavior.
- [ ] The first sentence states the user-facing capability or observable outcome.
- [ ] Every later sentence changes a user's required action or material expectation; no entry reads like a setup guide, API reference, or implementation report.
- [ ] Public identifiers appear only when users need the exact name to discover, enable, migrate, or react to the change.
- [ ] Observable scope is precise: attempt/run, local/remote, optional/required, and supported/unsupported distinctions match the evidence.
- [ ] No sentence asserts the absence of a change.
- [ ] Newest version is at the top.
- [ ] Bullet order inside every category matches the file's single convention.
- [ ] `git diff -- CHANGELOG.md` touches only `[Unreleased]` (or, when cutting a release, only the section being released). Zero changes to any other dated section.
- [ ] Every bullet you edited reads as complete prose - no clause orphaned by a removed sentence, no trailing `,`, `;`, `and`, or `so`.
- [ ] No trailing whitespace, and the repository's formatter passes on the file when it runs one (`prettier --check CHANGELOG.md`, `markdownlint`, or the project's equivalent).
- [ ] Every version has a date (except Unreleased).
- [ ] Bottom links are correct and complete.
- [ ] No empty category headings.
- [ ] No git-log copy-paste - entries are human-readable.
- [ ] Entries identify the subsystem where helpful.
- [ ] Tracker references are full URLs, not bare keys or plain `#NNN`.
- [ ] When an issue/task exists, the bullet references the issue/task only - not also the PR.
- [ ] **If the project's tracker is not GitHub Issues:** no `https://github.com/OWNER/REPO/issues/NNN` links are present in the changelog.

## Reviewing a CHANGELOG diff

Reviewing someone else's changelog edit is not the authoring workflow run backwards. The rules above are enforced by *where the insert is anchored*, and a reviewer never sees the anchor - only the result. The result hides the one fact that decides whether the edit is legal.

The procedure for resolving every added hunk to its enclosing `## [` heading, and the placement, order, and width checks that travel with a misanchored bullet, are in [references/reviewing-diffs.md](references/reviewing-diffs.md). Open it before approving any pull request that touches CHANGELOG.md.

## Error Recovery

The recovery table for a changelog that is already in a bad state (missing comparison links, duplicate entries, a dated section edited by mistake, bullet order mixed across sections, a dangling clause left by a removed sentence) is in [references/anti-patterns.md](references/anti-patterns.md). Open it the moment you find the file wrong rather than the entry wrong.

## Anti-Patterns

One entry per commit, one entry per PR, `git log --oneline` as the primary source, mini user guide, implementation report, vague minimalism, diagnostic catalog, plain `#NNN` references, bare tracker keys, stating that nothing is required, anchoring an edit on a bare `### Added` heading, rewriting an entry that was already committed, and reading a hunk header as proof of the section. Each one's failure mode and its correction are in [references/anti-patterns.md](references/anti-patterns.md).
