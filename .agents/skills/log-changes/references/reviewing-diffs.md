# Reviewing a CHANGELOG diff

How to resolve every added hunk to the version heading that encloses it, and the two defects that travel with a misanchored bullet. Read this when reviewing a pull request that touches CHANGELOG.md.

A unified-diff hunk header names the enclosing **category**, never the enclosing **version**:

```
@@ -76,6 +76,16 @@
 ### Fixed
```

That reads as a plausible `### Fixed`, and it is one. It says nothing about whether the `## [x.y.z]` heading above it is `[Unreleased]` or a version shipped months ago - that heading can sit dozens of lines further up and never appear in the diff at all. The built-in markdown diff driver does not rescue this: its function-name pattern matches any heading level, so it reports the nearest `###` and not the `##`.

Resolve the version yourself, one line per added hunk:

```bash
git diff -U0 "$BASE".."$HEAD" -- CHANGELOG.md \
| sed -n 's/^@@ -[^ ]* +\([0-9]*\).*/\1/p' \
| while read -r n; do
    v=$(git show "$HEAD":CHANGELOG.md | awk -v n="$n" 'NR<=n && /^## \[/{h=$0} END{print h}')
    printf '+%-6s %s\n' "$n" "${v:-<preamble>}"
  done
```

Every hunk must resolve to `## [Unreleased]`, unless the change under review is deliberately cutting a release. A hunk resolving to a dated version is an edit to shipped history. Confirm it against what was actually published - `git tag --list`, plus the forge's release list when the project publishes releases - because a section can carry a date before anyone has shipped it, and only the tag settles the question.

Two further defects travel with this one, because a bullet anchored against the wrong heading is usually drafted against the wrong neighbours too. Check all three in the same pass:

- **Placement.** Every hunk resolves to `[Unreleased]`.
- **Order.** The bullet sits at whichever end of its category the file's convention reserves for new work - the direction detected in Step 1, not the direction that looks natural.
- **Width.** The bullet wraps to the width its new neighbours use, not the width of whatever it was drafted against.
