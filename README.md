# `.agents`

My personal collection of artifacts for AI coding agents: skills, rules, prompts, instructions, and hooks. Right now it's Agent Skills only. More kinds will land here over time. I port this around alongside my dotfiles, so the same capabilities follow me between machines.

## Contents

- **`.skills/`** - standalone agent skills, each in its own subdirectory. Each skill is self-contained (`SKILL.md` plus optional `scripts/`, `references/`, and `assets/`) and follows the [agentskills.io specification](https://agentskills.io). The skills are agent-agnostic and location-agnostic: they are not tied to any specific agent (Claude, Copilot, Cursor, etc.) or to a fixed path on disk. Place them wherever your agent expects skills to live.

## Install

No bootstrapper. Clone the repo, then symlink (or copy) what you need into the directory your agent reads from. 
For details on the Agents Skills see my blogpost: [Agent Skills 101: a practical guide for engineers](https://blog.serghei.pl/posts/agent-skills-101/).

## License

Licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution and trademark notes.

Copyright © 2026 Serghei Iakovlev
