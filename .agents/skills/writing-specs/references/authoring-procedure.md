# Authoring procedure

Where the specification file goes and what it is called.

## Output path and file name

Determine the output path:

1. If the project's agent-instruction files document a spec directory, use it.
2. Otherwise if `.specs/` already exists in the repository, use it.
3. Otherwise if `docs/specs/` or `specs/` exists, use that.
4. Otherwise default to `.specs/` and create it.

File name: `Spec-{slug}.md`. Derive `{slug}` in this order:

1. If a tracker ID is present (e.g. `BP-138`, `SORT-42`, `#238`), use it: `Spec-BP-138.md`, `Spec-238-codex-agent-adapter.md`.
2. Otherwise, derive a concise kebab-case name from the feature title: `Spec-Email-Classification.md`.

Use the same slug across all related artifacts (spec, review, plan) so traceability is automatic.
