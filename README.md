# `.agents`

**One set of rules, skills, and agents that follows you across every AI coding tool.**

Clone it once, run the installer, and Claude Code, Codex, Copilot, Gemini, and Opencode all read the same instructions - no copy-pasting between config directories, no drift between machines.

## The Problem

Every AI coding host invents its own config directories, file formats, and frontmatter fields. Keeping your rules and skills in sync across five hosts and several machines means hand-editing the same content again and again - and the copies quietly drift apart.

Collecting prompts from the internet makes it worse: most of it is scrap you never use, and stale instructions actively confuse your agent.

## How It Works

This repository holds one canonical copy of everything: working rules, agent skills that follow the published [specification](https://agentskills.io), and agents for each host. A single script, `scripts/install.sh`, adds the host-specific fields each tool expects and writes every file to where that host reads it.

Nothing here is scraped or collected. Each file earns its place by being something I reach for daily; when it stops pulling its weight, it gets deleted. That is why this reflects my workflow rather than yours - borrow what is useful.

## Try It

```bash
git clone git@github.com:sergeyklay/.agents.git
cd .agents
scripts/install.sh --help
```

Or install just one asset type for one host, for example Claude Code skills:

```bash
scripts/install.sh --skills --claude
```

Hosts without an existing directory are skipped, so nothing is written where you do not use it.

## Learn More

- [Hosts](docs/hosts.md) - what the installer writes where, and per-host quirks
- [Agent Skills 101: a practical guide for engineers](https://blog.serghei.pl/posts/agent-skills-101/)

## License

This project is open source software licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution and trademark notes.

Copyright © 2026 Serghei Iakovlev
