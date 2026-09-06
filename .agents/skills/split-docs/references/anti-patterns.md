# Anti-patterns of a document split

Ways a split passes inspection while carrying breakage. Each entry names the shortcut and what it costs.

- **Rewriting prose during the move.** Tightening a sentence "while you are in there" breaks the byte-faithful contract and hides real extraction errors inside intended edits. Move first, verified; edit later, separately, with approval.
- **Trusting an edit-plan list of links over a grep sweep.** The link that breaks is the one the plan forgot. Enumerate links from the files, not from memory - for both outbound (step 5) and inbound (step 8).
- **Searching for inbound references only in `*.md`, or only near the doc.** References live repo-wide and in many file types. Search the whole tree.
- **Leaving every prose "§5.3.10" mention because "prose does not break".** A section reference that names the split doc *does* break: the doc file no longer holds that section, so it now misroutes. Linkify it to the owning section file. Only a bare `§N` that the surrounding doc means as its *own* section stays as-is. Conflating the two ships stale cross-references.
- **Reading a raw `${DOCNAME}#` grep count as proof.** Section files named `*-${DOCNAME}` false-match it. Resolve the links; do not count strings.
- **Silently skipping a protected file you just broke.** "I am not allowed to edit ADRs" is not a reason to leave a dangling link in one. Surface the breakage and ask. Blind rule-following that knowingly ships breakage is a defect, not compliance.
- **Skipping the concat diff because the split "looks right".** Dropped or reordered bytes are invisible on a scroll-through and obvious in a diff. The diff is cheap; run it.
- **Cutting at `##` because the procedure's example cuts at `##`.** When the `##` headers are containers, that produces one enormous file per container and no progressive disclosure at all. Pick the level from the document's actual shape.
- **Treating a transform as if the byte gate covered it.** A green concat diff over the moved sections says nothing about the sections you rearranged. Those need containment, uniqueness, and count, or they are unverified.
- **Resurrecting a tombstone.** A struck-through or "superseded" row becomes a live file, and now the subject exists twice - once properly, once as a ghost that will be read, cited, and updated. Field containment passes while this happens; only the uniqueness gate catches it.
- **Filling a metadata field because it looked empty.** A guessed date is worse than a null one: null is visibly missing and gets fixed, a guess is invisible and gets trusted.
- **Porting the index table from the stale digest.** The digest is being deleted *because* it drifted. Reusing its descriptions reintroduces the drift the split was meant to remove. Derive each row from the live section.
- **Applying one blanket `../` fix to all links.** Section-to-section links inside the new tree must not gain a `../`; only links escaping the directory do. A global substitution over-repairs the internal ones.
