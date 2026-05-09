# Frontmatter Fields Reference

Complete guide to SKILL.md YAML frontmatter, covering the agentskills.io spec and the platform-specific extensions on top.

## Contents

- Spec fields (name, description, license, compatibility, metadata, allowed-tools)
- Description by invocation model
- Description writing strategy
- Claude Code extensions (disable-model-invocation, user-invocable, argument-hint, arguments, when_to_use, model, effort, context, agent, hooks, paths, shell)
- OpenAI Codex extensions (agents/openai.yaml)
- Field/platform support matrix

## Spec field overview

The agentskills.io specification defines six frontmatter fields:

| Field           | Required | Constraint                                                                            |
| --------------- | -------- | ------------------------------------------------------------------------------------- |
| `name`          | yes      | 1-64 chars; lowercase alphanumeric and hyphens; matches directory; no reserved words. |
| `description`   | yes      | 1-1024 chars; non-empty; no XML tags. Describes what the skill does and when to use.  |
| `license`       | no       | Short licence name or reference to a bundled file.                                    |
| `compatibility` | no       | ≤ 500 chars. Environment requirements (target product, OS packages, network).         |
| `metadata`      | no       | Arbitrary key-value mapping for client-specific properties.                           |
| `allowed-tools` | no       | Pre-approved tools (experimental). Behavior varies by platform.                      |

Anything else is a vendor extension. Cross-platform skills should stay inside this table.

## name

| Constraint  | Rule                                                   |
| ----------- | ------------------------------------------------------ |
| Length      | 1-64 characters                                        |
| Characters  | Lowercase alphanumeric and hyphens (`a-z`, `0-9`, `-`) |
| Start/end   | Cannot start or end with `-`                           |
| Consecutive | No `--` allowed                                        |
| Match       | Must match the parent directory name                   |
| Reserved    | Cannot contain "anthropic" or "claude"                 |
| XML         | Cannot contain XML tags                                |

Prefer gerunds: `processing-pdfs`, `analyzing-data`, `testing-code`, `writing-documentation`. Acceptable: noun phrases (`pdf-processing`, `spreadsheet-analysis`), action verbs (`process-pdfs`). Avoid: `helper`, `utils`, `tools`, `documents`, `data`, `files`.

## description

| Constraint  | Rule                                       |
| ----------- | ------------------------------------------ |
| Length      | 1-1024 characters                          |
| Content     | Non-empty, no XML tags                     |
| Perspective | Third person (injected into system prompt) |

### Description by invocation model

The description's purpose changes depending on who can invoke the skill. Get this wrong and the description is either dead tokens or a missed trigger.

| Invocation         | Set                                                                                              | Where the description is read                                                | How to write it                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Model + user (default) | nothing                                                                                       | Model context (for selection) **and** slash menu (for the user).             | What it does + explicit triggers ("Use when ..."). Concise enough to read in the menu.           |
| User-invoked only  | `disable-model-invocation: true` (Claude Code) or `policy.allow_implicit_invocation: false` (Codex) | Slash-command picker / `$skill` autocomplete only. The model never sees it.  | Terse, accurate label of what the skill does. **No "Use when ..." triggers.** No marketing copy. |
| Model-invoked only | `user-invocable: false` (Claude Code)                                                            | Model context only. Hidden from slash menu.                                  | Strong triggers and clear scope; this is the only thing the model gets.                          |

The Claude Code docs spell this out in their context-loading matrix: when `disable-model-invocation: true` is set, "description not in context, full skill loads when you invoke". Triggers in such a description are noise that take up the slash-menu label budget for nothing.

### Why descriptions matter for model-invoked skills

For model-invoked skills the description is the primary discovery mechanism. At startup, agents pre-load only the name and description of every installed skill (~100 tokens each). When a request arrives, the agent scans those descriptions to choose. A poor description means the skill never triggers.

### Formula (model-invoked)

```plaintext
[What the skill does] + [When to use it, with specific triggers and edge cases]
```

### Effective examples (model-invoked)

```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```

```yaml
description: Generate descriptive commit messages by analysing git diffs. Use when the user asks for help writing commit messages, reviewing staged changes, or preparing a pull request description.
```

```yaml
description: "Apply Acme Corp brand guidelines to presentations and documents (colours #FF6B35, #004E89; fonts Montserrat, Open Sans). Use whenever creating external-facing materials, slide decks, reports, or any document representing Acme Corp."
```

### Effective examples (user-invoked only)

```yaml
description: "Stage and commit current changes following project commit style."
disable-model-invocation: true
argument-hint: "[scope]"
```

```yaml
description: "Deploy the application to production via the standard build pipeline."
disable-model-invocation: true
```

No "Use when ...". No edge-case keyword bait. The user is already typing `/deploy`; persuading the model is moot.

### Pushiness for model-invoked skills

Agents tend to under-trigger. State edge cases that should still trigger activation:

```yaml
description: "Build dashboards to display data. Use whenever the user mentions dashboards, data visualization, metrics, charts, graphs, or wants to display any kind of data visually, even if they don't explicitly ask for a 'dashboard'."
```

### Common mistakes

```yaml
description: Helps with PDFs.
# Vague. No triggers. Agent will never select it.
```

```yaml
description: I can help you process Excel files and generate reports.
# First person. Descriptions are injected as third person in the system prompt.
```

```yaml
description: "Stage and commit. Use when the user asks to commit, save, or persist changes; also use when wrapping up a task and asking what to do next."
disable-model-invocation: true
# Triggers in a user-only description. The model never reads them. They take up the slash-menu label budget for free.
```

## license

```yaml
license: Apache-2.0
license: Proprietary. LICENSE.txt has complete terms
```

## compatibility

≤ 500 characters. Include only when there are real environment requirements:

```yaml
compatibility: Requires git, docker, jq, and access to the internet
compatibility: Designed for Claude Code (or similar products with filesystem access)
```

Use it to declare a single-vendor target explicitly: `compatibility: "Claude Code only; uses disable-model-invocation and slash-command UX."`

## metadata

Arbitrary key-value mapping. Use reasonably unique keys to avoid client conflicts:

```yaml
metadata:
  author: your-org
  version: "1.0"
  category: development
```

Codex reads `metadata.short-description` as the user-facing description in the IDE.

## allowed-tools

Pre-approved tools the skill may use without per-invocation permission. The agentskills.io spec marks this as **experimental**; behavior varies.

```yaml
allowed-tools:
  - Read
  - Grep
  - Glob
  - WebSearch
```

Claude Code accepts both space-separated strings and YAML lists, with optional argument patterns: `allowed-tools: Bash(git:*) Bash(jq:*) Read`.

| Platform          | Support |
| ----------------- | ------- |
| Claude Code       | Full    |
| VS Code / Copilot | None    |
| Cursor            | None    |
| Gemini CLI        | Partial |
| Codex CLI         | None    |

Read-only skills (review, audit, explainers) benefit from a tight allow-list; mutating skills typically need broader access.

## Claude Code extensions

Claude Code follows the agentskills.io spec and adds the fields below. None of these is portable to other platforms; gate them behind `compatibility` or accept that the skill is single-vendor.

| Field                      | Type    | Effect                                                                                                                                      |
| -------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `disable-model-invocation` | bool    | `true` ⇒ description **not** loaded into model context; only user can invoke via `/name`. Use for `/commit`, `/deploy`, side-effect skills. |
| `user-invocable`           | bool    | `false` ⇒ hidden from `/` menu. Only the model can invoke. Use for background-knowledge skills (`legacy-system-conventions`).               |
| `argument-hint`            | string  | Autocomplete hint, e.g. `"[issue-number]"` or `"[filename] [format]"`.                                                                      |
| `arguments`                | list/str | Named positional arguments for `$name` substitution in the body.                                                                            |
| `when_to_use`              | string  | Additional model-facing trigger context appended to `description` in the listing. Counts toward the 1,536-char skill-listing cap.           |
| `model`                    | string  | Model override for the skill turn (`sonnet`, `opus`, `haiku`, `inherit`).                                                                   |
| `effort`                   | string  | Effort override (`low`, `medium`, `high`, `xhigh`, `max`).                                                                                  |
| `context`                  | string  | `fork` runs the skill in an isolated subagent.                                                                                              |
| `agent`                    | string  | Subagent type (`Explore`, `Plan`, `general-purpose`, or a custom agent) when `context: fork`.                                               |
| `hooks`                    | object  | Lifecycle hooks scoped to the skill (`PreToolUse`, `PostToolUse`, `Stop`, etc.).                                                            |
| `paths`                    | list/str | Glob patterns that gate auto-activation by file scope.                                                                                      |
| `shell`                    | string  | `bash` (default) or `powershell` for `` !`command` `` injection.                                                                            |

The Claude Code skill listing has a 1,536-char per-skill cap on combined `description` + `when_to_use`; long marketing copy gets truncated. Put the load-bearing trigger first.

### Invocation control matrix

| Frontmatter                      | Model can invoke | User can invoke | Description in model context | Visible in `/` menu |
| -------------------------------- | ---------------- | --------------- | ---------------------------- | ------------------- |
| (default)                        | yes              | yes             | yes                          | yes                 |
| `disable-model-invocation: true` | no               | yes             | **no**                       | yes                 |
| `user-invocable: false`          | yes              | no              | yes                          | no                  |

## OpenAI Codex extensions

Codex stores skills in `.agents/skills/<name>/` (project) or `~/.agents/skills/<name>/` (user). The spec frontmatter applies; UI metadata and invocation policy go in an optional sibling file.

### agents/openai.yaml

```yaml
interface:
  display_name: "Human-Friendly Name"
  short_description: "Shown in Codex UI"
  icon_small: "./assets/icon.svg"
  icon_large: "./assets/icon-large.png"
  brand_color: "#3B82F6"
  default_prompt: "Optional surrounding prompt"
policy:
  allow_implicit_invocation: false  # require explicit $skill invocation
dependencies:
  tools:
    - type: "mcp"
      value: "serverName"
      description: "Required MCP server"
      transport: "streamable_http"
      url: "https://example.com/mcp"
```

When `policy.allow_implicit_invocation: false` is set, Codex requires explicit `$skill-name`; the description's triggers no longer matter for model selection. This is the Codex equivalent of Claude Code's `disable-model-invocation: true`.

The file is Codex-specific and silently ignored elsewhere. Include it only when targeting Codex.

## Cross-platform compatibility cheat sheet

| Field                      | Spec | Claude Code | Codex | Cursor | Gemini | Copilot |
| -------------------------- | ---- | ----------- | ----- | ------ | ------ | ------- |
| `name`                     | yes  | yes         | yes   | yes    | yes    | yes     |
| `description`              | yes  | yes         | yes   | yes    | yes    | yes     |
| `license`                  | yes  | yes         | yes   | yes    | yes    | yes     |
| `compatibility`            | yes  | yes         | yes   | yes    | yes    | yes     |
| `metadata`                 | yes  | yes         | yes   | yes    | yes    | yes     |
| `allowed-tools`            | exp  | full        | —     | —      | partial | —       |
| `disable-model-invocation` | —    | yes         | —     | —      | —      | —       |
| `user-invocable`           | —    | yes         | —     | —      | —      | —       |
| `argument-hint`/`arguments` | —   | yes         | —     | —      | —      | —       |
| `when_to_use`              | —    | yes         | —     | —      | —      | —       |
| `model`/`effort`           | —    | yes         | —     | —      | —      | —       |
| `context`/`agent`          | —    | yes         | —     | —      | —      | —       |
| `hooks`/`paths`/`shell`    | —    | yes         | —     | —      | —      | —       |
| `agents/openai.yaml`       | —    | —           | yes   | —      | —      | —       |

Pick the columns you actually ship to. A skill that lives only in `~/.claude/skills/` should use the Claude Code column; a skill destined for skills.sh distribution should stay in the first six rows.
