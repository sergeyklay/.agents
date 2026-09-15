# Frontmatter Fields Reference

Complete guide to SKILL.md YAML frontmatter, covering the agentskills.io spec and the platform-specific extensions on top.

## Contents

- Spec fields (name, description, license, compatibility, metadata, allowed-tools)
- Description by invocation model
- Description writing strategy
- Claude Code extensions (when_to_use, argument-hint, arguments, disable-model-invocation, user-invocable, disallowed-tools, model, effort, context, agent, background, hooks, paths, shell)
- Skill-listing budgets (Claude Code and Codex)
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
| `metadata`      | no       | A map from string keys to string values, for client-specific properties.             |
| `allowed-tools` | no       | Space-separated **string** of tools pre-approved to run (experimental).              |

Anything else is a vendor extension. Cross-platform skills should stay inside this table.

The six are not a recommendation on Anthropic's distribution path. `package_skill.py` imports `validate_skill` from `quick_validate.py` and calls it before packaging anything, and that check fails the whole file rather than dropping the stray key. Run the copy in `anthropics/skills` at `main` (`skills/skill-creator/scripts/quick_validate.py:42`, allow-list last changed 2026-02-06) against a skill carrying `argument-hint` and `compatibility`:

```plaintext
Unexpected key(s) in SKILL.md frontmatter: argument-hint. Allowed properties are: allowed-tools, compatibility, description, license, metadata, name
```

Claude Code's own documentation quotes that message verbatim and applies it to claude.ai skill uploads, the Skills API, and `package_skill.py`.

That script is forked, and the forks disagree about `compatibility`. Codex CLI 0.153.4 ships its own copy at `~/.codex/skills/.system/skill-creator/scripts/quick_validate.py:40` whose allow-list is five names, with `compatibility` absent. The same skill through that copy fails differently:

```plaintext
Unexpected key(s) in SKILL.md frontmatter: argument-hint, compatibility. Allowed properties are: allowed-tools, description, license, metadata, name
```

So five of the six are safe wherever this family of scripts runs, and `compatibility` is safe on Anthropic's path but not on every fork of it. The divergence is a validator disagreement only: no host has been observed refusing to load a skill over `compatibility`.

`validate_skill.py` reports any field outside the six as an INFO line, so a deliberate single-vendor skill still validates clean while the portability cost stays visible.

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

A map from string keys to string values. Use reasonably unique keys to avoid client conflicts:

```yaml
metadata:
  author: your-org
  version: "1.0"
  category: development
```

`version` is not a frontmatter field: not in the spec, not in Claude Code's table. Nest it under `metadata`, as the spec's own example does. A top-level `version:` fails `package_skill.py` and every claude.ai upload.

Codex parses `metadata.short-description` but does not use it in the model-visible skill listing: measured on 0.153.4, the listing renders `description` at both a truncating and a saturated budget. Tuning it changes nothing the model sees.

## allowed-tools

Tools **pre-approved to run** without a per-invocation permission prompt. This grants permission; it does not take any away. Claude Code states the direction outright: "It does not restrict which tools are available: every tool remains callable, and your permission settings still govern tools that are not listed." The field that removes capability is `disallowed-tools`, which is Claude Code only and not in the spec.

The spec types the value as a space-separated **string**, and the reference validator declares it `Optional[str]`:

```yaml
allowed-tools: Bash(git:*) Bash(jq:*) Read
```

Claude Code's shipped frontmatter schema calls the field a "Comma-separated string or YAML list" and never mentions spaces, which reads like a trap for the spec's own example. It is not one. The tokenizer in Claude Code 2.1.263 walks the value character by character and breaks it on commas **and** spaces, holding a run together while it sits inside parentheses: `Bash(git log --oneline) Read` yields two entries, and so does `Read, Grep`. The published field table agrees with the parser rather than with the schema string, calling the value "a space- or comma-separated string, or a YAML list", and the page's own example is `allowed-tools: Read Grep`. Write the space-separated string: it is the spec form, and the host most likely to read it parses it correctly. A YAML list is the form `validate_skill.py` rejects.

| Platform                        | Behavior                                                                                     |
| ------------------------------- | -------------------------------------------------------------------------------------------- |
| Claude Code                     | Honored. Grant lasts for the turn that invokes the skill and clears on your next message.    |
| GitHub Copilot (CLI, coding agent) | Honored. "If a tool is not listed in the `allowed-tools` field, Copilot will prompt you for permission before using it." |
| VS Code Copilot client          | Rejected. Not in the skill attribute list; the editor reports "Attribute '{0}' is not supported by VS Code skills." |
| Cursor                          | Not a documented field.                                                                      |
| Zed                             | Not a documented field.                                                                      |
| Gemini CLI                      | Discarded. Its frontmatter parser returns `{ name, description }` and drops everything else. |
| Codex CLI                       | Discarded. Its frontmatter parser reads `name`, `description`, and `metadata.short-description` only. |

Pre-approving `Bash` or `shell` removes the confirmation step for arbitrary commands. Grant it only in a skill whose scripts you have read.

## Claude Code extensions

Claude Code's frontmatter table has grown to twenty fields: the six spec fields above plus the fourteen below. It parses `license` and `compatibility` and then does nothing with them. Every field is optional, and only `description` is recommended, so the model knows when to use the skill. None of the fourteen is portable: gate them behind `compatibility` or accept that the skill is single-vendor.

| Field                      | Type    | Effect                                                                                                                                      |
| -------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `when_to_use`              | string  | Additional model-facing trigger context appended to `description` in the listing. Counts toward the 1,536-char skill-listing cap.           |
| `argument-hint`            | string  | Autocomplete hint, e.g. `"[issue-number]"` or `"[filename] [format]"`.                                                                      |
| `arguments`                | list/str | Named positional arguments for `$name` substitution in the body.                                                                            |
| `disable-model-invocation` | bool    | `true` ⇒ description **not** loaded into model context; only user can invoke via `/name`. Use for `/commit`, `/deploy`, side-effect skills. |
| `user-invocable`           | bool    | `false` ⇒ hidden from `/` menu. Only the model can invoke. Use for background-knowledge skills (`legacy-system-conventions`).               |
| `disallowed-tools`         | list/str | Tools removed from the model's pool while the skill is active. The real restriction field; clears on your next message.                     |
| `model`                    | string  | Model override for the skill turn (`sonnet`, `opus`, `haiku`, `inherit`).                                                                   |
| `effort`                   | string  | Effort override (`low`, `medium`, `high`, `xhigh`, `max`).                                                                                  |
| `context`                  | string  | `fork` runs the skill in an isolated subagent.                                                                                              |
| `agent`                    | string  | Subagent type (`Explore`, `Plan`, `general-purpose`, or a custom agent) when `context: fork`.                                               |
| `background`               | bool    | With `context: fork`, `false` waits for the subagent's result in the invoking turn instead of backgrounding it.                             |
| `hooks`                    | object  | Lifecycle hooks scoped to the skill (`PreToolUse`, `PostToolUse`, `Stop`, etc.).                                                            |
| `paths`                    | list/str | Glob patterns that gate auto-activation by file scope.                                                                                      |
| `shell`                    | string  | `bash` (default) or `powershell` for `` !`command` `` injection.                                                                            |

### Invocation control matrix

| Frontmatter                      | Model can invoke | User can invoke | Description in model context | Visible in `/` menu |
| -------------------------------- | ---------------- | --------------- | ---------------------------- | ------------------- |
| (default)                        | yes              | yes             | yes                          | yes                 |
| `disable-model-invocation: true` | no               | yes             | **no**                       | yes                 |
| `user-invocable: false`          | yes              | no              | yes                          | no                  |

## Skill-listing budgets

Every host loads a listing of installed skill names and descriptions into each session. Both hosts that publish a budget shrink descriptions rather than erroring, so an over-budget listing costs activation accuracy with no diagnostic in the transcript.

| Host        | Budget                                                                        | What happens over budget                                                                     |
| ----------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Claude Code | 1% of the model's context window, in characters. Raise with `skillListingBudgetFraction`. | Drops descriptions starting with the least-invoked skills, so heavily used skills keep theirs. |
| Codex       | 2% of the context window, in tokens, with an 8,000-character fallback when the window is unknown. Override with `skills.max_context_tokens`. | Shrinks the per-description ceiling; omits whole skills, with a warning, only when names alone overflow. Measured on 0.153.4 at the catalog default window of 272,000, the ceiling lands at 600 characters and the cut carries no ellipsis and no word boundary. |

Claude Code also caps each entry at 1,536 characters of `description` plus `when_to_use` combined, regardless of budget, configurable with `skillListingMaxDescChars`. Codex truncates each description to 1,024 characters before its own budget math runs. Put the load-bearing trigger first in the description so it survives both.

## OpenAI Codex extensions

Keep portable skill metadata in `SKILL.md` frontmatter. Codex-specific UI metadata, invocation policy, and tool dependencies belong in the optional `<skill>/agents/openai.yaml` sidecar. Support for a field in one host or file does not establish support in another.

### agents/openai.yaml

This is an illustrative subset of the [official Codex skill metadata example](https://developers.openai.com/codex/skills), not an exhaustive schema. Include only the fields the skill needs and verify them for its target installation:

```yaml
interface:
  display_name: "Human-Friendly Name"
  short_description: "A concise picker description"
policy:
  allow_implicit_invocation: false
dependencies:
  tools:
    - type: "mcp"
      value: "serverName"
      description: "Required MCP server"
      transport: "streamable_http"
      url: "https://example.com/mcp"
```

The documented purpose of `interface` is human-facing presentation; `policy.allow_implicit_invocation` controls implicit invocation; `dependencies.tools` declares tool dependencies. A dependency declaration is not a substitute for an access-control policy. Keep model-routing triggers in the skill description and check presentation separately from invocation.

Before using vendor-specific fields or relying on validation behavior:

1. Identify the target Codex installation, version, and distribution path: a standalone skill and a packaged plugin can encounter different validators.
2. Read the official documentation for that target. Use the installed CLI's help, bundled references, schema or source when available to resolve missing details. Match source to the target release; upstream `main` may describe a different implementation. If the target or behavior cannot be established, leave the claim unverified rather than filling it from an older observation.
3. Validate the artifact with the tool that consumes it. A standalone skill validator, plugin-package validator, and runtime loader check different boundaries; do not transfer an allow-list, successful result, or rejection rule from one to another.
4. Check the intended effect on the relevant surface: model-visible discovery and invocation, human-facing UI metadata, or dependency resolution. Use the target's available inspection commands or a small isolated probe with a known working control and an invalid input. Record the tool version and observed result so later users can reproduce the check without treating it as a permanent guarantee.

Unknown or ill-typed fields may be ignored, rejected, or affect neighboring metadata. Treat this as version-dependent implementation behavior unless the official contract promises an outcome. A successful load, a validator pass, or silence in the terminal alone does not prove that a field took effect. Keep exhaustive field lists, numeric limits, parser internals, and release-specific failure observations in task evidence; look up the target's contract when those details matter.

## Cross-platform compatibility cheat sheet

"Copilot" splits: the VS Code client and everything else under the same brand disagree about `allowed-tools`.

| Field                       | Spec | Claude Code | Codex   | Cursor  | Gemini | Copilot CLI   | VS Code       |
| --------------------------- | ---- | ----------- | ------- | ------- | ------ | ------------- | ------------- |
| `name`                      | yes  | yes         | yes     | yes     | yes    | yes           | yes           |
| `description`               | yes  | yes         | yes     | yes     | yes    | yes           | yes           |
| `license`                   | yes  | accepted    | no      | no      | no     | yes           | accepted      |
| `compatibility`             | yes  | accepted    | no      | no      | no     | no            | accepted      |
| `metadata`                  | yes  | yes         | partial | yes     | no     | no            | accepted      |
| `allowed-tools`             | exp  | yes         | no      | no      | no     | yes           | rejected      |
| `disallowed-tools`          | no   | yes         | no      | no      | no     | no            | no            |
| `disable-model-invocation`  | no   | yes         | no      | yes     | no     | yes           | yes           |
| `user-invocable`            | no   | yes         | no      | no      | no     | yes           | yes           |
| `argument-hint`/`arguments` | no   | yes         | no      | no      | no     | argument-hint | argument-hint |
| `when_to_use`               | no   | yes         | no      | no      | no     | no            | no            |
| `model`/`effort`            | no   | yes         | no      | no      | no     | no            | no            |
| `context`/`agent`           | no   | yes         | no      | no      | no     | no            | `context`     |
| `background`                | no   | yes         | no      | no      | no     | no            | no            |
| `hooks`/`paths`/`shell`     | no   | yes         | no      | `paths` | no     | no            | no            |
| `icon`/`color`              | no   | no          | no      | yes     | no     | no            | no            |
| `agents/openai.yaml`        | no   | no          | yes     | no      | no     | no            | no            |

- **accepted** means the host parses the field without complaint and does nothing with it.
- **partial** for Codex `metadata` means only `metadata.short-description` is parsed, and nothing the model sees uses it.
- **rejected** means the host reports the field as unsupported. VS Code raises it as an editor hint, not a load failure.
- The Gemini CLI column is `no` below `description` on purpose. Its frontmatter parser returns `{ name, description }`, so every other field is discarded in silence.
- Zed has no column because it documents three fields in total: `name`, `description`, and `disable-model-invocation`.

`disable-model-invocation` is the one non-required field every implementation agrees on. Reach for it before any other vendor extension.

Pick the columns you actually ship to. A skill that lives only in `~/.claude/skills/` should use the Claude Code column; a skill destined for skills.sh distribution should stay in the first six rows.
