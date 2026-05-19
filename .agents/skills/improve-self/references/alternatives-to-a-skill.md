# Alternatives to a new skill

Load this only when the candidate fails one of Phase 3's four criteria (Procedural / Reusable / Self-contained / Testable), or when the gap looks skill-shaped but lives more naturally elsewhere. Route the gap to its proper home — do not force it into a skill.

| Gap shape | Better home |
|---|---|
| A project convention everyone needs to know | `CLAUDE.md` / `AGENTS.md` |
| A coding-style rule | `.agents/rules/` or the platform's `rules/` directory |
| A one-off task with no future recurrence | Document in the current conversation; nothing persists |
| A fact about an external API | The research path next time (see `research-it`); do not hardcode |
| A capability the agent cannot do at all (auth, write-API call against a private system) | Propose an MCP server, not a skill |
| A user-triggered template with arguments | A slash command (`.agents/commands/`, `.claude/commands/`, or the platform's equivalent) |
| A repeated investigation pattern in one domain | A skill — proceed |
| A recurring explanation pattern for one topic class | A skill — proceed |

When in doubt, prefer the smaller intervention. Skills are tokens that load forever.
