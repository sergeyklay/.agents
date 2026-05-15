# `.agents`

My personal, curated set of artifacts for AI coding agents that I actually use day-to-day, permissively licensed for others to adapt. I port this around alongside my dotfiles, so the same capabilities follow me between machines.

## This is NOT

- an "awesome-*" list,
- a dump of AI slop scraped off the internet,
- a showcase of every trending prompt the algorithm pushed this week.

Everything here earns its place by being something I actually reach for in daily work. When something stops pulling its weight, it gets deleted - no sentimentality, no "maybe later." Borrow what's useful, but don't mistake this for a general recommendation: it reflects my workflow, not yours.

## Note on agents

Unlike Agent Skills, which follow a published [industry specification](https://agentskills.io), agents are not standardized - every host (Claude Code, Copilot, Cursor, Gemini, Codex, ...) ships its own frontmatter schema, and the schemas are mutually incompatible. To keep the agents in this repo portable across hosts, their frontmatter is stripped down to the smallest subset every host will accept. The trade-off: these agents are functionally leaner than a host-native one could be.

After copying an agent into your host's directory, hand-edit the frontmatter to add the fields your host actually supports (model, allowed tools, capability flags, etc.).

## Install

No bootstrapper. Clone the repo, then symlink (or copy) what you need into the directory your agent reads from. For details on the Agents Skills see my blogpost: [Agent Skills 101: a practical guide for engineers](https://blog.serghei.pl/posts/agent-skills-101/).

## License

This project is open source software licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution and trademark notes.

Copyright © 2026 Serghei Iakovlev
