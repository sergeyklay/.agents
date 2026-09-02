# `.agents`

My personal, curated set of artifacts for AI coding agents that I actually use day-to-day, permissively licensed for others to adapt. I port this around alongside my dotfiles, so the same capabilities follow me between machines.

## This is NOT

- an "awesome-*" list,
- a dump of AI slop scraped off the internet,
- a showcase of every trending prompt the algorithm pushed this week.

Everything here earns its place by being something I actually reach for in daily work. When something stops pulling its weight, it gets deleted - no sentimentality, no "maybe later." Borrow what's useful, but don't mistake this for a general recommendation: it reflects my workflow, not yours.

## Note on agents

Unlike Agent Skills, which follow a published [industry specification](https://agentskills.io), agents are not standardized - every host (Claude Code, Copilot, Cursor, Gemini, Codex, ...) ships its own frontmatter schema, and the schemas are mutually incompatible. To keep the agents in this repo portable across hosts, their frontmatter is stripped down to the smallest subset every host will accept. The trade-off: these agents are functionally leaner than a host-native one could be.

`scripts/install.sh` puts the host-specific fields back on the way out: `templates/<vendor>/` carries them per host (model, tool lists, capability flags, opencode's `mode` and `subtask`) and the installer merges them onto the source frontmatter. Copying an agent by hand skips that step, so hand-edit the frontmatter yourself to add what your host supports.

## Install

Clone the repo, then either symlink (or copy) what you need into the directory your agent reads from, or run `scripts/install.sh` to mirror the whole set into the host directories under `$HOME`. Asset flags such as `--agents` and `--skills` combine with host filters such as `--claude` and `--opencode`: `scripts/install.sh --agents --opencode` installs only opencode agents, while `scripts/install.sh --claude` installs every supported asset type for Claude Code. Multiple host filters can be combined, and omitting them preserves the default of targeting every registered host. Pass `--help` for the full flag list; each host is skipped unless its directory already exists. For details on the Agents Skills see my blogpost: [Agent Skills 101: a practical guide for engineers](https://blog.serghei.pl/posts/agent-skills-101/).

### Global context

`--context` installs `.agents/AGENTS.md` under each host's native name:

| Host | Destination |
| --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` |
| Codex | `~/.codex/AGENTS.md` |
| GitHub Copilot CLI | `~/.copilot/copilot-instructions.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |
| opencode | `~/.config/opencode/AGENTS.md` |

VS Code Copilot can load `~/.claude/CLAUDE.md` when `chat.useClaudeMdFile` is enabled. Existing context files are overwritten. Unmodified legacy `working-agreement` rules are removed.

### Rules on opencode

OpenCode has no path-scoped instructions. Rules with a Claude `paths` overlay remain Claude/Copilot-only; the rest install to `~/.config/opencode/rules/`. The Working Agreement loads from `~/.config/opencode/AGENTS.md`.

### Keeping opencode away from Claude Code

opencode reads `~/.claude/skills/` on top of its own `~/.config/opencode/skills/`, so every skill installed here is discovered twice and opencode logs `duplicate skill name` for each one. Both copies are byte-identical, so whichever wins the load race behaves the same. To cut opencode off from Claude Code entirely, export `OPENCODE_DISABLE_CLAUDE_CODE=1` in your shell profile. There is no config-file equivalent: opencode reads that flag from the environment only, and it ignores a `.env` file. The flag also stops opencode from falling back to `~/.claude/CLAUDE.md`, and it hides any skill that lives only under `~/.claude/skills/`.

## Formatting

```bash
asdf plugin add shfmt https://github.com/luizm/asdf-shfmt.git
asdf install shfmt
shfmt -w scripts
shfmt -d scripts
```

## License

This project is open source software licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution and trademark notes.

Copyright © 2026 Serghei Iakovlev
