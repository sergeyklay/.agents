# Platform targeting and distribution

Which platforms a skill targets, which vendor frontmatter each one accepts, where each platform loads skills from, and how a finished skill ships.

## Contents

- Platform targeting (cross-platform vs single-vendor, per-vendor extensions, storage matrix, precedence)
- Distribution (skills.sh, `.skill` package, Claude Code plugin marketplace)

## Platform targeting

The agentskills.io spec is intentionally minimal: required `name` and `description`; optional `license`, `compatibility`, `metadata`, and experimental `allowed-tools`. Every vendor ships extensions on top.

**Decide once, up front: cross-platform or single-vendor?**

| Choice          | When                                                                              | What to use                                                                                |
| --------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Cross-platform  | Public distribution; team uses multiple platforms; portability is the goal.       | Spec frontmatter only; no vendor-only fields; forward slashes; bundle deps; document target in `compatibility` if narrow. |
| Single-vendor   | The skill exists for one platform and will not be used elsewhere.                 | Use vendor extensions where they help; declare the target in `compatibility`; ignore other platforms. |

**Single-vendor is not a smell.** A `commit` skill that lives only in `~/.claude/skills/` should use `disable-model-invocation: true`, `argument-hint: "[scope]"`, `allowed-tools: Bash(git:*)`, and `context: fork` if those make the skill correct on its target. Refusing those features to "stay portable" produces a worse Claude Code skill that nobody else runs anyway. The cross-platform default applies when portability is an actual goal — not as a moral rule.

**Platform-specific extensions** (full reference in `references/frontmatter-fields.md`):

- **Claude Code**: `disable-model-invocation`, `user-invocable`, `argument-hint`, `arguments`, `when_to_use`, `model`, `effort`, `context`, `agent`, `hooks`, `paths`, `shell`. Slash-command invocation `/skill-name`. Live change detection on `~/.claude/skills/` and `.claude/skills/`.
- **OpenAI Codex**: `agents/openai.yaml` for UI metadata and `policy.allow_implicit_invocation`. Invocation `$skill-name`. Scans `.agents/skills/` from CWD upward, then `~/.agents/skills/`.
- **Cursor**: `.cursor/skills/`; spec-compliant frontmatter only.
- **Gemini CLI**: prefers `.agents/skills/` over `.gemini/skills/` when both exist.
- **VS Code / Copilot**: `.github/skills/`; spec-compliant frontmatter only.

**Storage matrix:**

| Platform                | Project           | User                  |
| ----------------------- | ----------------- | --------------------- |
| Claude Code             | `.claude/skills/` | `~/.claude/skills/`   |
| Cursor                  | `.cursor/skills/` | `~/.cursor/skills/`   |
| Gemini CLI              | `.gemini/skills/` | `~/.gemini/skills/`   |
| OpenAI Codex            | `.agents/skills/` | `~/.codex/skills/`    |
| VS Code / Copilot       | `.github/skills/` | `~/.copilot/skills/`  |
| Cross-platform fallback | `.agents/skills/` | n/a                   |

`.agents/` is the emerging cross-platform convention. Codex uses it natively; Gemini reads it preferentially; Antigravity and OpenCode adopt it. Claude Code does not: it loads only `.claude/skills/` at project scope, so a skill placed in `.agents/skills/` is invisible to it. Serve both from one source by symlinking the `.agents/skills/<name>` directory into `.claude/skills/`, which Claude Code follows.

**Precedence**: project > personal > extension/plugin. (Codex shows colliding skills in the selector instead of merging.)

## Distribution

- **skills.sh** (Vercel package manager): `npx skills add <owner>/<repo>` or `... --skill "<name>"` for a multi-skill repo. Publish to GitHub in standard layout.
- **`.skill` package** (Claude.ai-specific): zip archive with `.skill` extension; upload via Settings → Features.
- **Claude Code Plugin marketplace**: `/plugin marketplace add <owner>/<repo>`.
