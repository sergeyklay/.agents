# Hosts

What the installer writes, where each host reads it, and the quirks that follow. For the short version see [README.md](../README.md).

## Install

Clone the repo, then either symlink (or copy) what you need into the directory your agent reads from, or run `scripts/install.sh` to mirror the whole set into the host directories under `$HOME`.

Codex agent installation and merging repository settings into an existing Codex `config.toml` require Python 3.11+ and use only its standard library. A clean Codex settings install does not require Python.

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

## Agents on Codex

`--agents` installs personal Codex agents as standalone TOML files under `~/.codex/agents/`. Each file takes its name, description, and developer instructions from the corresponding canonical `.agents/agents/*.md` file. Settings-only templates under `templates/.codex/agents/` select the Codex model tier, reasoning effort, enforceable feature restrictions, and skill visibility that most closely match the Claude agent behavior.

The translation is necessarily broader than Claude in some places. Roles that need workspace reads retain Codex's shell and can therefore execute commands. Roles with Claude's Skill tool retain plugins so plugin skills remain available; plugin tools and MCP servers come with them because Codex cannot enable only the skill half of a plugin. Apps remain disabled because they add a separate connector surface. Codex cannot independently restrict `apply_patch`, web search, delegation, or inherited MCP servers, and role-local sandbox and approval values are not enforced by the role application path.

Selected-skill templates provide best-effort visibility, not a closed allow-list. The renderer hides other skills shipped by this repository, but future user, project, administrator, and plugin skills can still appear because Codex has no wildcard skill deny. `skills = "none"` hides the model-visible skill catalog and instructions; it is not a hard execution deny. Skills remain progressively loaded rather than eagerly preloaded.

The installer records generated-file digests in `~/.codex/.agents-install-state.json`, outside Codex's role discovery directory, and serializes reconciliation with `~/.codex/.agents-install.lock`. Before changing roles it records both installed and intended digests, then converges the files and records the completed state. A later install can finish an interrupted update or stale-file removal, including a missing managed file. Content matching neither digest is treated as a local edit and blocks reconciliation. Unrelated files are preserved, and an unrecognized same-name file is never replaced.

## Rules on OpenCode

opencode has no path-scoped instructions. Rules with a Claude `paths` overlay remain Claude/Copilot-only; the rest install to `~/.config/opencode/rules/`. The Working Agreement loads from `~/.config/opencode/AGENTS.md`.

## Keeping opencode away from Claude Code

opencode reads `~/.claude/skills/` on top of its own `~/.config/opencode/skills/`, so every skill installed here is discovered twice and opencode logs `duplicate skill name` for each one. Both copies are byte-identical, so whichever wins the load race behaves the same. To cut opencode off from Claude Code entirely, export `OPENCODE_DISABLE_CLAUDE_CODE=1` in your shell profile. There is no config-file equivalent: opencode reads that flag from the environment only, and it ignores a `.env` file. The flag also stops opencode from falling back to `~/.claude/CLAUDE.md`, and it hides any skill that lives only under `~/.claude/skills/`.
