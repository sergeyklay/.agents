---
name: split-docs
description: "Split one oversized Markdown reference document into a progressive-disclosure tree - a curated index page plus one file per top-level section - without altering a byte of prose. Use when a single doc has grown too large to read whole (a multi-hundred-line architecture spec, PRD, or reference), when asked to split, shard, or break up a doc into sections, when converting a monolith-plus-stale-digest pair into an index-plus-sections layout, or when a digest has drifted from the doc it summarizes. Covers header-tiling extraction, concat-vs-original byte verification, per-link relative-depth repair with a grep sweep, deriving the index fresh from each section's current content in the repo's index style, deleting a now-redundant digest, and reconciling context-file pointers. Do NOT use for authoring new documentation content (that is make-docs), for choosing a Diataxis type, for splitting source code, or for editing prose during the move."
metadata:
  author: Serghei Iakovlev
  version: "1.1"
  category: documentation
---

# Splitting a Large Doc into a Progressive-Disclosure Tree

A reference doc that has grown past a few hundred lines is read whole every time any part of it is relevant, which wastes context and buries the section that matters. The fix is to split it into one file per top-level section under a sibling directory, and replace the original with a curated index that routes a reader to the one section their task touches.

The hard constraint is that this is a *move*, not a *rewrite*. Section prose must survive byte-for-byte; only the index is new writing. Three failure modes recur and all are silent:

1. Dropped or reordered bytes during extraction.
2. Outbound links inside the moved sections that break because the section files now sit one directory deeper than the original.
3. Inbound links from elsewhere in the repo that pointed *into* the doc by section anchor (`thedoc.md#some-heading`), left dangling because that anchor no longer exists in the doc - it moved to a section file.

This skill makes all three verifiable instead of hoped-for. The third is the easiest to miss and the most damaging, because the dangling links sit in *other* files, often ones an agent never reopens during the split.

A frequent variant: the doc travels with a hand-written digest (`*-digest.md`, `*-summary.md`) that has drifted out of date. The digest's job - route a reader to the right part - is exactly what the new index does, so the digest is deleted after the split, not carried forward.

This document uses one example doc to keep the commands concrete, but nothing here is specific to it: it applies equally to an architecture spec, a PRD, or any long reference. Set the two variables below once and the rest is doc-agnostic.

## When this applies

Run it when a single Markdown reference doc is too large to read whole and the request is to break it up. It generalizes across doc types. If the repo holds several monolith-plus-digest pairs (for example an architecture spec and a PRD, each with its own digest), each is a separate application of this same procedure.

It does not apply to authoring new prose (`make-docs`), to picking a Diataxis quadrant, or to splitting code. If the task involves rewriting or improving the prose while moving it, stop - that breaks the byte-faithful contract and needs a different approach the user should approve first.

## Procedure

### 1. Snapshot the original before touching anything

Set the source and target as variables so every later command is doc-agnostic, then copy the source to a scratch path. Every later check diffs against this snapshot, so it must be taken before the first edit.

```bash
SRC=docs/the-doc.md     # the oversized doc to split (e.g. docs/architecture.md, docs/PRD.md)
DIR=docs/the-doc        # sibling directory that will hold one file per section
cp "$SRC" /tmp/_split_original.md
wc -l "$SRC"            # record the line count
```

### 2. Map the top-level section boundaries

List the headers at the split level (usually `##`) with their line numbers. These are the cut points; the count is how many section files you will produce.

```bash
grep -nE '^## ' "$SRC"
```

Decide the per-file naming up front: zero-padded ordinal plus a slug from the heading (`01-<slug>.md`, `02-<slug>.md`) keeps the directory sorted in document order. Create the target directory (`mkdir -p "$DIR"`).

### 3. Tile the file by header into section files

Extract each section as the byte range from its header line up to (but not including) the next header line. Drive it from the boundary line numbers in step 2 - do not hand-retype prose. Run `sed -n 'START,ENDp' "$SRC"` for each range, writing to the matching section file. The first section starts at the doc's first `##`; anything above it (title, preamble) belongs in the index, not a section file. For the last section, end at `$` so a missing trailing newline does not truncate it.

Extract every section before editing either the snapshot or the live file, so the line numbers stay valid.

### 4. Verify byte-faithfulness by concatenation

This is the gate that makes the split trustworthy. Concatenate the section files in order and diff against the snapshot. The only legitimate difference is the title and preamble lifted into the index (the lines above the first `##`).

```bash
diff <(sed -n '<first-##-line>,$p' /tmp/_split_original.md) <(cat $(ls "$DIR"/*.md | sort))
```

Investigate every diff line. A diff hunk in the *middle* of a section means dropped or duplicated content - fix the tiling and re-run. Do not proceed until the only diff is the lifted preamble (or run the diff against the original from the first section line, as above, for a clean empty result).

### 5. Repair outbound relative-link depth, then sweep every link

Section files now live one directory deeper than the original, so every relative link that pointed *outside* the doc's own directory needs one extra `../`. A link to `decisions/0008.md` from the old `$SRC` becomes `../decisions/0008.md` from `$DIR/05-*.md`. Links *within* the new tree (section to section, including same-file `#anchor` links) do not change.

Do not trust a hand-built list of links to fix - that is exactly where one gets missed (a single doc can hold more escaping links than you expect). After repairing, sweep *all* relative links across the new files and confirm each resolves:

```bash
grep -rnoE '\]\(([^)]+)\)' "$DIR" | grep -v '://'   # every non-http link
```

For each hit, check the target exists from the section file's location (`test -e` against the resolved path, or open it). A link that does not resolve is either an unrepaired depth (`../` missing) or over-repaired (one `../` too many). The grep sweep, not the edit plan, is the source of truth for which links exist.

### 6. Author the index fresh from each section's current content

Replace the original file with an index page. Derive each section's summary by reading that section file *as it now stands* - do not port descriptions from the old digest or an outdated table of contents, which may describe content that has since moved or changed. Open each section, write its row from what is actually there.

Match the repo's existing index house-style: study a sibling index (for example `docs/README.md` or a `decisions/README.md`) and reuse its table shape and column semantics. A routing index typically carries a short preamble, an optional orientation paragraph, and a table whose columns name each section, what it covers, and when a reader should open it. State, near the top, that the section file wins when the index summary and the section disagree - the index is a map, not a second source of truth. Follow the project's writing rules (sentence-case headings, punctuation conventions, banned words, em-dash bans) the same as any other doc edit.

### 7. Delete a now-redundant digest, after confirming it holds nothing unique

If a `*-digest.md` / `*-summary.md` accompanied the original, the new index supersedes it. Before deleting, diff its content against the section files and the new index to confirm it carries no information that exists nowhere else. If it holds a unique line, fold that into the right section or the index first; then delete. Removing it stops a second stale artifact from accumulating drift.

### 8. Find and repair every inbound reference, repo-wide

This is the step that is most often under-done. Other files point *at* the doc you just split: agent context files, other docs, ADRs, reference pages, even source comments. Search the whole repo, not just `*.md`, and not just the doc's own directory.

```bash
DOCNAME=$(basename "$SRC")          # e.g. architecture.md
SECTIONS=$(basename "$DIR")         # e.g. architecture
EXC="--exclude-dir=node_modules --exclude-dir=.next --exclude-dir=$SECTIONS"
grep -rn "$DOCNAME" . $EXC                                  # by file name
grep -rnE "${SECTIONS}[[:space:]]+(section[[:space:]]+)?§?[0-9]" . $EXC  # by short name + section
```

The second grep matters because a reference like `architecture §11C.1` or `architecture section 20` names the doc by its short name with no `.md`, so the first grep never sees it. Adjust `${SECTIONS}` to whatever short name prose actually uses for this doc.

Classify each hit; the forms need different handling. The split changes what the doc *file* contains, so any reference that resolves through a section - whether by anchor or by section number - is now stale, even when nothing about it is a clickable link:

- **Anchor link** (`](...${DOCNAME}#some-section)`): **broken.** The anchor moved to a section file. Repoint the path to the section file that now owns that heading, keeping the anchor slug unchanged (the slug is derived from the heading text, which the move preserved): `](../the-doc.md#92-aws-s3)` becomes `](../the-doc/09-storage.md#92-aws-s3)`.
- **Plain link, no anchor** (`](...${DOCNAME})`): still resolves to the new index. Leave it.
- **Section reference naming the split doc** ("see ${DOCNAME} §5.3.10", "section 20 of ${DOCNAME}", or the doc's short name plus a section like "architecture §11C.1", linked or not): **now stale.** The named file no longer holds that section - it moved to a section file - so the reference points a reader at the wrong place, or at a heading the file no longer has. Linkify it to the owning section file and anchor: bare `architecture §5.3.10` becomes `[architecture §5.3.10](../the-doc/05-workflow.md#5310-dispatch-object)`. Do not assume the section number equals the file ordinal: `§20` may live in `25-webhook-support.md` because numbering and file order diverged. Resolve the owning file from the heading, the same way step 5 verifies, never from the number alone.
- **Bare section reference, source ambiguous** ("see section 9.2", "§4", no doc named): disambiguate before acting. A doc that numbers its *own* sections (a reference page, a spec) routinely cites itself by bare `§N` - that is a same-doc reference, still valid, leave it. Treat a bare `§N` as a reference *into the split doc* only when the surrounding text or the file's role makes the split doc the referent. When genuinely unsure which doc a bare number points at, ask rather than rewrite a self-reference into a wrong cross-doc link.

Two traps here, both learned the hard way:

- **The base-name suffix false-match.** When you re-grep to confirm no broken anchors remain, a bare `${DOCNAME}#` pattern will *false-match the section files you just created* if any section slug ends in the doc's base name. Splitting `architecture.md` produces files like `09-storage-architecture.md`, and `09-storage-architecture.md#91-postgresql` contains the substring `architecture.md#91-postgresql`. Anchor the search on the boundary - require a `/` immediately before the name (`/${DOCNAME}#`) or exclude `"$SECTIONS"` - and treat "every rewritten link resolves to a real heading" as the pass condition, never "the raw grep count is zero". The same holds for the short-name + section grep: it can match a section file's own heading or the new index, so exclude `"$SECTIONS"` and judge by resolution, not count.
- **Files you are forbidden to edit still count.** Some broken inbound references - anchor links *and* stale section references - live in files a project rule protects from edits: accepted ADRs, a README, a spec marked immutable. Do **not** silently skip them. A dangling or misrouting cross-reference inside an authoritative doc that agents consult degrades every task that reads it; leaving breakage you just caused, in the name of a no-edit rule, is the rule causing harm. Surface it instead: list the protected files and the exact broken references, explain what the split broke, and ask the user to approve the repair (or confirm an explicit instruction to proceed). Fixing is a one-line link or linkify repair, not a decision change - make that distinction clear when you ask. Then keep the edit minimal: only the reference, nothing else in the protected file.

Distinguish **active** references (context files, ADRs, current reference docs - fix them) from **historical** ones (implementation plans, past reviews, dated task logs - point-in-time records that should keep citing the state they were written against; leave them, and say you did).

Verify each repaired inbound link resolves the same way as in step 5: target file exists, and a heading in it slugifies to the anchor.

## Validation

The split is correct when all of these hold:

- The order-preserving `cat` of section files diffs clean against the pre-split snapshot, save for the preamble lines lifted into the index.
- The all-links grep sweep over the new tree resolves every relative link from its file's location - none missing a `../`, none with one too many.
- Every inbound reference repo-wide that resolves through a section - anchor link or section reference naming the split doc - has been repointed to the owning section file and resolves, or is a deliberately-left historical artifact you have named.
- Every bare `§N` reference of ambiguous source has been judged a same-doc self-reference (left) or a reference into the split doc (repointed) on evidence, not rewritten blind.
- Any broken inbound references inside edit-protected files have been surfaced to the user with the file list and an explanation, not silently skipped.
- The index is built from the current section content, follows the repo's index house-style, and names the section files as authoritative on conflict.
- No `*-digest.md` survives carrying information absent from the sections or index.

## Anti-patterns

- **Rewriting prose during the move.** Tightening a sentence "while you are in there" breaks the byte-faithful contract and hides real extraction errors inside intended edits. Move first, verified; edit later, separately, with approval.
- **Trusting an edit-plan list of links over a grep sweep.** The link that breaks is the one the plan forgot. Enumerate links from the files, not from memory - for both outbound (step 5) and inbound (step 8).
- **Searching for inbound references only in `*.md`, or only near the doc.** References live repo-wide and in many file types. Search the whole tree.
- **Leaving every prose "§5.3.10" mention because "prose does not break".** A section reference that names the split doc *does* break: the doc file no longer holds that section, so it now misroutes. Linkify it to the owning section file. Only a bare `§N` that the surrounding doc means as its *own* section stays as-is. Conflating the two ships stale cross-references.
- **Reading a raw `${DOCNAME}#` grep count as proof.** Section files named `*-${DOCNAME}` false-match it. Resolve the links; do not count strings.
- **Silently skipping a protected file you just broke.** "I am not allowed to edit ADRs" is not a reason to leave a dangling link in one. Surface the breakage and ask. Blind rule-following that knowingly ships breakage is a defect, not compliance.
- **Skipping the concat diff because the split "looks right".** Dropped or reordered bytes are invisible on a scroll-through and obvious in a diff. The diff is cheap; run it.
- **Porting the index table from the stale digest.** The digest is being deleted *because* it drifted. Reusing its descriptions reintroduces the drift the split was meant to remove. Derive each row from the live section.
- **Applying one blanket `../` fix to all links.** Section-to-section links inside the new tree must not gain a `../`; only links escaping the directory do. A global substitution over-repairs the internal ones.
