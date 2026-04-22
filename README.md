# .agents

My personal collection of artifacts for AI coding agents: skills, rules, prompts, instructions, and hooks. Right now it's Agent Skills only. More kinds will land here over time. I port this around alongside my dotfiles, so the same capabilities follow me between machines.

## Contents

- `comparing-solutions/` - structured tool and architecture comparison
- `context-files/` - authoring and validation of AGENTS.md, CLAUDE.md, GEMINI.md
- `creating-agent-skills/` - writing new Agent Skills against the [agentskills.io](https://agentskills.io/) spec
- `diataxis-documentation/` - Diataxis-style technical documentation
- `review-impl/` - review of implementation changes against architectural standards
- `review-spec/` - review of specifications before implementation
- `verify-spec/` - conformance check of code against its specification
- `skills/todo-management/` - roadmap management via TODO.md

Each skill is self-contained (`SKILL.md` plus optional `scripts/`, `references/`, and `assets/`) and follows the agentskills.io specification.

## Install

No bootstrapper. Clone the repo, then symlink (or copy) what you need into the directory your agent reads from. For Claude Code that is typically `~/.claude/skills/`. Skills with `disable-model-invocation: true` are meant to be triggered explicitly (for example via a slash command), not auto-invoked.

## License

Licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution and trademark notes.

Copyright © 2026 Serghei Iakovlev
