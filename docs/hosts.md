# Hosts

What the installer writes, where each host reads it, and the quirks that follow. For the short version see [README.md](../README.md).

## Install

Clone the repo, then either symlink (or copy) what you need into the directory your agent reads from, or run `scripts/install.sh` to mirror the whole set into the host directories under `$HOME`.

Asset flags such as `--agents` and `--skills` combine with host filters such as `--claude` and `--opencode`: `scripts/install.sh --agents --opencode` installs only opencode agents, while `scripts/install.sh --claude` installs every supported asset type for Claude Code. Multiple host filters can be combined, and omitting them preserves the default of targeting every registered host. Pass `--help` for the full flag list; each host is skipped unless its directory already exists.

## Global context

`--context` installs `.agents/AGENTS.md` under each host's native name:

| Host | Destination |
| --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` |
| Codex | `~/.codex/AGENTS.md` |
| GitHub Copilot CLI | `~/.copilot/copilot-instructions.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` |
| opencode | `~/.config/opencode/AGENTS.md` |

VS Code Copilot can load `~/.claude/CLAUDE.md` when `chat.useClaudeMdFile` is enabled. Existing context files are overwritten. Unmodified legacy `working-agreement` rules are removed.

## Commands on Copilot

Copilot CLI reads personal assets only from `~/.copilot/skills/`, so `--commands` installs each command as `skills/<name>/SKILL.md` rather than into a commands directory of its own. Invocation is unchanged: `/<name>`, the same spelling the other hosts use. Earlier versions wrote `~/.copilot/prompts/<name>.prompt.md`, which no Copilot CLI version reads; `--commands` now removes those files and leaves any prompt file of your own in place.

## Rules on opencode

opencode has no path-scoped instructions. Rules with a Claude `paths` overlay remain Claude/Copilot-only; the rest install to `~/.config/opencode/rules/`. The Working Agreement loads from `~/.config/opencode/AGENTS.md`.

## Keeping opencode away from Claude Code

opencode reads `~/.claude/skills/` on top of its own `~/.config/opencode/skills/`, so every skill installed here is discovered twice and opencode logs `duplicate skill name` for each one. Both copies are byte-identical, so whichever wins the load race behaves the same. To cut opencode off from Claude Code entirely, export `OPENCODE_DISABLE_CLAUDE_CODE=1` in your shell profile. There is no config-file equivalent: opencode reads that flag from the environment only, and it ignores a `.env` file. The flag also stops opencode from falling back to `~/.claude/CLAUDE.md`, and it hides any skill that lives only under `~/.claude/skills/`.
