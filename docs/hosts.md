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

## Permissions and MCP on Codex

Codex uses separate mechanisms for approval flow, filesystem access, network access, and command policy. Instructions in `AGENTS.md` remain advisory and are not permission enforcement.

| Intent | Codex mechanism | Behavioral check |
| --- | --- | --- |
| Continue without interactive approval | `approval_policy = "never"` | An ordinary model-issued command executes; an escalation request is rejected without prompting. The `on-request` control reaches a real approval request. |
| Read ordinary files | `default_permissions = "full-access"` | A session inherits the installed profile and reads an ordinary sentinel through its shell tool. |
| Use the network | The `full-access` network profile | The installed profile reads a sentinel from a local HTTP server. Disabling network makes the same request fail. |
| Refuse dotenv reads | Workspace-root `deny` entries in the `full-access` profile | The session's shell tool cannot read a `.env` sentinel. Weakening the deny makes that read succeed. |
| Refuse dangerous command prefixes | `$CODEX_HOME/rules/default.rules` | A session automatically loads the installed rules and rejects a model-issued `shutdown --help`. Weakening the rule lets that harmless command execute. The policy matcher separately checks every prohibited prefix. |

The custom name `full-access` does not mean Codex's built-in `:danger-full-access`: filesystem restrictions remain active. Dotenv denies apply within workspace roots, with Linux glob expansion bounded by `glob_scan_max_depth = 16`. They cover `.env`, not every filename that may contain credentials. MCP servers have separate process and transport controls. See the [Codex permissions reference](https://developers.openai.com/codex/permissions).

`--settings --codex` installs native `mcp_servers` declarations for `atlassian`, `context7`, and `snyk`. Atlassian and Context7 use their provider-owned HTTPS endpoints. Snyk runs an exact CLI package version. Private, project-specific MCP servers are configured in that project's trusted `.codex/config.toml`; the installer ships no private MCP runtime.

Credentials remain outside the repository. Atlassian requires OAuth login, Context7 supports external authentication, and Snyk uses its external login state. The local MCP sentinel proves installer transport, discovery, and tool execution without service credentials; it does not test authenticated access to these providers.

The TOML merge preserves unrelated host-local permission profiles and MCP servers. If merging an existing server would combine stdio `command` with HTTP `url`, installation fails with the server name and leaves `config.toml` unchanged. A transport change requires an explicit choice before reinstalling. Same-transport settings continue to merge, including host-local authentication settings.

## Rules on OpenCode

opencode has no path-scoped instructions. Rules with a Claude `paths` overlay remain Claude/Copilot-only; the rest install to `~/.config/opencode/rules/`. The Working Agreement loads from `~/.config/opencode/AGENTS.md`.

## Keeping opencode away from Claude Code

opencode reads `~/.claude/skills/` on top of its own `~/.config/opencode/skills/`, so every skill installed here is discovered twice and opencode logs `duplicate skill name` for each one. Both copies are byte-identical, so whichever wins the load race behaves the same. To cut opencode off from Claude Code entirely, export `OPENCODE_DISABLE_CLAUDE_CODE=1` in your shell profile. There is no config-file equivalent: opencode reads that flag from the environment only, and it ignores a `.env` file. The flag also stops opencode from falling back to `~/.claude/CLAUDE.md`, and it hides any skill that lives only under `~/.claude/skills/`.
