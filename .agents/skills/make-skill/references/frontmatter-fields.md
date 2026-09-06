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

That script is forked, and the forks disagree about `compatibility`. Codex CLI 0.153.2 ships its own copy at `~/.codex/skills/.system/skill-creator/scripts/quick_validate.py:40` whose allow-list is five names, with `compatibility` absent. The same skill through that copy fails differently:

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

Codex reads `metadata.short-description` and prefers it over `description` in its model-visible skill listing.

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
| Codex       | At most 2% of the context window, or 8,000 characters when the window is unknown. | Shortens every description first; omits whole skills, with a warning, only when names alone overflow. |

Claude Code also caps each entry at 1,536 characters of `description` plus `when_to_use` combined, regardless of budget, configurable with `skillListingMaxDescChars`. Codex truncates each description to 1,024 characters before its own budget math runs. Put the load-bearing trigger first in the description so it survives both.

## OpenAI Codex extensions

Codex scans `.agents/skills/` from the working directory upward, and `$CODEX_HOME/skills/` for user-scope skills, which is `~/.codex/skills/` unless `CODEX_HOME` says otherwise. Its SKILL.md parser reads exactly three things: `name`, `description`, and `metadata.short-description`. Every other frontmatter key is discarded at load time, so Claude Code fields cost nothing on Codex and do nothing either. Loading is not the only gate, though: the plugin validator Codex ships (`~/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py:468-474`) rejects a skill whose `disable-model-invocation` is anything but `false` or absent: ``skill `X` frontmatter field `disable-model-invocation` must be false``. A skill distributed inside a Codex plugin therefore cannot carry that field set. UI metadata, invocation policy, and MCP dependencies go in a sibling file instead.

### agents/openai.yaml

The sidecar lives at `<skill>/agents/openai.yaml`. The directory name is `agents`, with no leading dot, and the filename is `openai.yaml`; there is no `.yml` spelling in the loader. Codex compares the directory name case-insensitively while loading the literal lowercase path, so a differently cased directory works only on a case-insensitive filesystem. Write it lowercase.

Three sections, and Codex rejects any other key in them:

```yaml
interface:
  display_name: "Human-Friendly Name"
  short_description: "Shown in the picker"   # 25-64 chars
  icon_small: "./assets/icon.svg"            # must resolve under assets/
  icon_large: "./assets/icon-large.png"      # must resolve under assets/
  brand_color: "#3B82F6"                     # exactly #RRGGBB
  default_prompt: "Optional surrounding prompt"
policy:
  allow_implicit_invocation: false  # boolean; default true
dependencies:
  tools:
    - type: "mcp"
      value: "serverName"
      description: "Required MCP server"
      transport: "streamable_http"
      url: "https://example.com/mcp"
```

**`interface`** is UI metadata for the ChatGPT desktop app: how the skill is named and rendered in the picker.

Each comment above names a constraint some shipped artifact enforces, and they do not all come from the same one. Codex CLI 0.153.2's own validator (`plugin-creator/scripts/validate_plugin.py:531-559`) requires `display_name` and `short_description` to be non-empty strings, `default_prompt` to be one when present, `brand_color` to match `#RRGGBB`, and each icon path to be a relative path resolving to a file inside the package; it checks no lengths at all. The `assets/` rule is the loader's, not the validator's: `codex-rs/skills/src/interface.rs` refuses an icon whose first path segment is anything else. The 25-64 range for `short_description` comes from Codex's own reference (`skill-creator/references/openai_yaml.md:37`, stated as advice) and from its generator (`skill-creator/scripts/generate_openai_yaml.py:169`, which errors outside that range).

Character caps do exist in the Rust loader, and they are wider. `openai/codex` at `main` declares `MAX_NAME_LEN = 64` and `MAX_DESCRIPTION_LEN = 1024` in `codex-rs/skills/src/interface.rs:10-11`, applying 64 to `display_name` and 1,024 to `short_description` and `default_prompt`; a value over the cap is dropped with a log warning rather than rejected. Those constants were not confirmed in the installed 0.153.2 build: the module is compiled in, since its other warnings appear as literals in the binary, but the numbers are not observable there. Treat 64 and 1,024 as the upstream source branch, not as a limit this build was seen to apply.

**`policy`** carries one key. `allow_implicit_invocation: false` keeps the whole catalog entry out of the model's context while explicit `$skill-name` invocation keeps working, which is the Codex equivalent of Claude Code's `disable-model-invocation: true`. The default is `true`.

**`dependencies.tools`** declares the MCP servers the skill needs. It is a declaration, not a restriction: nothing in Codex disables a skill whose declared server is absent, and nothing confines the skill to the servers it lists.

The loader is fail-open by design, with a source comment that says so: "Fail open: optional metadata should not block loading SKILL.md." Malformed YAML drops the entire sidecar with a log warning while SKILL.md still loads; one rejected field drops only that field and its siblings survive. Nothing surfaces to the author, so a typo here is silent. Validate the file by reading it back, not by watching for an error.

Two `short_description` fields exist and they feed different surfaces. `interface.short_description` styles the human picker; the model-visible listing falls back from frontmatter `metadata.short-description` to `description` and never sees the sidecar. Tune `metadata.short-description` for implicit routing.

The sidecar is Codex-specific and ignored elsewhere: it is an ordinary file in the skill directory, and the spec allows a skill to contain any files beyond SKILL.md. Include it only when targeting Codex.

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
- **partial** for Codex `metadata` means only `metadata.short-description` is read.
- **rejected** means the host reports the field as unsupported. VS Code raises it as an editor hint, not a load failure.
- The Gemini CLI column is `no` below `description` on purpose. Its frontmatter parser returns `{ name, description }`, so every other field is discarded in silence.
- Zed has no column because it documents three fields in total: `name`, `description`, and `disable-model-invocation`.

`disable-model-invocation` is the one non-required field every implementation agrees on. Reach for it before any other vendor extension.

Pick the columns you actually ship to. A skill that lives only in `~/.claude/skills/` should use the Claude Code column; a skill destined for skills.sh distribution should stay in the first six rows.
