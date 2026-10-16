# Highlights format

A changelog written for people who use the product rather than for developers who integrate with it. Each release leads with a few highlights that can stand on their own, for example in a "What's new" panel inside the product, and puts everything else in one list. It replaces Keep a Changelog's sorting by change type, which tells a product user nothing they care about.

Use this file when Step 1 detects the format. It replaces Steps 4 to 6 of the main workflow; Steps 2, 3 and 7 still apply.

## Detecting it

The file uses this format when its preamble or agent comment says so, or when `[Unreleased]` or the newest release carries `### Highlights` or `### Improvements and fixes`. A file that switched to it keeps its older releases in Keep a Changelog form. Those sections are shipped history: never convert, reorder, or reword them, and never take their categories as the shape for new work.

When the project's own changelog comment states a rule that differs from this file (heading names, the highlight limit, entry length), the project's rule wins.

## Structure

```markdown
## [Unreleased]

## [2026.3.2]

### Highlights

#### Share a board with a link

Send anyone a link that opens the board read-only, and turn the link off at any time from "Share". ([PROJ-210](https://tracker.example.com/browse/PROJ-210))

#### Export a board as a PDF

Download any board as a PDF from the board menu. ([PROJ-204](https://tracker.example.com/browse/PROJ-204))

### Improvements and fixes

- Boards: Cards keep their order after you undo a move. ([PROJ-215](https://tracker.example.com/browse/PROJ-215))

- Search: Results now include archived boards. ([PROJ-199](https://tracker.example.com/browse/PROJ-199))
```

- A release section holds at most two headings, `### Highlights` then `### Improvements and fixes`. Leave out a heading that would be empty. `[Unreleased]` uses the same two headings.
- There are no Added, Changed, Removed, Deprecated, Fixed or Security headings. A removal or a security fix that the user can notice goes into "Improvements and fixes", worded as what the user sees.
- Bottom comparison links, newest release first, and one entry per ticket work as in Keep a Changelog.
- A release heading may carry only the version, because a calendar version already says when it shipped and the tag records the day. Copy whichever form the newest release heading uses; when it has no date, the Step 7 "every version has a date" check does not apply.

## Choosing the tier

| Tier | What goes there |
|---|---|
| Highlights | Something new a person can now do, important enough that they would want to hear about it unprompted. |
| Improvements and fixes | Everything else that passes the Step 3 filter: smaller improvements, changed behavior, fixes, removals. |

When unsure, use "Improvements and fixes". A highlight that turns out minor costs the reader attention in every place it is shown, while a demoted one is still in the release.

## Writing a highlight

- A `####` heading in sentence case that names what the person can do: "Snooze an email until later", not "Email snoozing" or "New: snooze".
- One paragraph of one or two sentences under it, on a single line, ending with the tracker reference. No area prefix; the heading already carries it.
- It must make sense with nothing around it, because it may be shown alone. Do not refer to another highlight or to "this release".
- Order highlights by importance, most important first.

## Writing an improvement or fix

- One bullet per ticket: `- Area: what the person sees change. (reference)`, one or two short sentences.
- Newest first unless the file shows another convention; detect it as for Keep a Changelog bullets.
- Do not open with "Fixed" or "Added" for every bullet; say what changed.

The entry style rules that the main workflow links from Step 4 apply to both tiers.

## Cutting a release

1. Pick the version (below).
2. Insert `## [VERSION]`, with ` - YYYY-MM-DD` only when the newest release heading carries a date, under `## [Unreleased]`, so the entries move into the release and `[Unreleased]` stays empty above it.
3. Enforce the highlight limit the project states (when it states none, three). Move the least important extra highlights down into "Improvements and fixes" as bullets in the bullet form above. This edit to the section being released is part of cutting it.
4. Update the bottom comparison links.

## Calendar versions

A project on this format often uses calendar versions. Read the scheme from the preamble and the existing tags; do not impose one. For `YEAR.MONTH.NUMBER`, a common shape:

- No leading zeros (`2026.3.2`, never `2026.03.02`), so the version stays valid for semver-aware tools.
- The number counts releases within the month, starting at 1. Find the previous release of the same month with `git tag --list 'YEAR.MONTH.*'` and the release headings, and add one; the first release of a month is `.1`.
- The month is the month the release ships, not the month the work started.

## Reviewing a diff

The main workflow's "Reviewing a CHANGELOG diff" checks still hold: a hunk header can name a `####` highlight or the `### Improvements and fixes` heading of a shipped release, so resolve every added line to its enclosing `## [` heading. Also reject a new section that reintroduces Keep a Changelog categories, a highlight without its own heading, and a release that ships more highlights than the project allows.
