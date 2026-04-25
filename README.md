# `.agents`

My personal, curated set of artifacts for AI coding agents that I actually use day-to-day. Right now it's Agent Skills and agents only. More kinds will land here over time. I port this around alongside my dotfiles, so the same capabilities follow me between machines.

## Scope

Let's be clear about what this is **not**:

- an "awesome-*" list,
- a dump of AI slop scraped off the internet,
- a showcase of every trending prompt the algorithm pushed this week.

Everything here earns its place by being something I actually reach for in daily work. When something stops pulling its weight, it gets deleted - no sentimentality, no "maybe later." Borrow what's useful, but don't mistake this for a general recommendation: it reflects my workflow, not yours.

## Contents

- **`.agents/skills/`:** standalone agent skills, each in its own subdirectory. Each skill is self-contained (`SKILL.md` plus optional `scripts/`, `references/`, and `assets/`) and follows the [agentskills.io specification](https://agentskills.io). The skills are agent-agnostic and location-agnostic: they are not tied to any specific agent (Claude, Copilot, Cursor, etc.) or to a fixed path on disk. Place them wherever your agent expects skills to live.
- **`.agents/agents/`:** my collection of "agents" I find useful in daily work. Strictly speaking these are not agents but system prompts (personas, role definitions, operating instructions) for real agents - GitHub Copilot, Claude Code, Gemini, Cursor, and the like. Each file defines a focused mode of work (e.g. a deep-research investigator) that orchestrates the relevant skills and constrains how the underlying agent should behave. Drop them into whatever location your host expects custom agents/modes/personas to live (e.g. `.github/agents/`, `.claude/agents/`, etc), or load them manually as a system prompt.
- **`.claude/`:** Claude-specific configuration, including `settings.json` and any custom hooks. This directory is for configuration that only applies to Claude Code. It does not contain any skills or agents - those go in `.agents/`.
- **`scripts/`:** small utilities that support the rest of this repo:
  - **`scripts/analyze-chat-dump.mjs`:** reads a VS Code Copilot Chat JSON export and prints a clean summary - duration, slash command and task, token totals, tools and subagents used, plus a per-subagent tool breakdown - so I can spot slow or noisy steps and iterate on agent configs, prompts, and models.

## Note on agents

Unlike Agent Skills, which follow a published [industry specification](https://agentskills.io), agents are not standardized - every host (Claude Code, Copilot, Cursor, Gemini, Codex, ...) ships its own frontmatter schema, and the schemas are mutually incompatible. To keep the agents in this repo portable across hosts, their frontmatter is stripped down to the smallest subset every host will accept. The trade-off: these agents are functionally leaner than a host-native one could be.

After copying an agent into your host's directory, hand-edit the frontmatter to add the fields your host actually supports (model, allowed tools, capability flags, etc.).

## Install

No bootstrapper. Clone the repo, then symlink (or copy) what you need into the directory your agent reads from. For details on the Agents Skills see my blogpost: [Agent Skills 101: a practical guide for engineers](https://blog.serghei.pl/posts/agent-skills-101/).

## License

Licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution and trademark notes.

Copyright © 2026 Serghei Iakovlev
