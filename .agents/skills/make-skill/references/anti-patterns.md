# Skill anti-patterns

Failure modes graded by severity: Critical ones stop a skill from activating correctly, High impact ones degrade how it performs, Medium impact ones cost tokens and quality.

**Critical** (skill never activates correctly):

- **Workflow summary in `description`.** The model may skip the body if the description tells the whole story. Description triggers; body teaches. Bad: `"Analyzes git diff, identifies the change type, generates a commit message"`. Good: `"Use when generating commit messages. Handles conventional commits, scope detection, breaking changes."`
- **Vague description.** "Helps with documents" matches nothing.
- **Monolithic skill.** "Handles all dev workflows" loads slowly and triggers imprecisely. Split.

**High impact** (degrade performance):

- **README-style content.** Skills teach how, not what. Procedures with steps, not narrated context.
- **Inlining what belongs in `assets/`.** Templates with placeholders, schemas, and other output-generation patterns go in `assets/<name>.md`, referenced from SKILL.md. Inlining a per-type catalog loads every variant on every invocation and obscures the skill's structural shape. Inline only when the block is small and used unconditionally.
- **External fetch dependencies.** Network downloads at activation time are fragile. Bundle.
- **Command lists without verification.** Add explicit checks and failure handling.
- **First/second person in description.** "I can help" / "You can use" reads wrong from a system prompt.
- **Cross-platform dogma on a single-vendor skill.** Refusing `disable-model-invocation`, `allowed-tools`, or `argument-hint` on a skill that lives only in `~/.claude/skills/` is missed value. Portability is a goal, not a moral rule.
- **"Use when ..." triggers in a user-invoked-only description.** When `disable-model-invocation: true` (Claude Code) or `allow_implicit_invocation: false` (Codex), the model never reads the description. The triggers consume the user-facing label budget for nothing.

**Medium impact** (token bloat, lower quality):

- **User-guide aesthetics.** Hard wraps that imply meaningful line breaks where there are none, blockquotes around examples (use code fences), three-deep ladders of indented bullets where one tight sentence suffices, "why this works" paragraphs after every example, restating a rule in prose immediately after a code block already showing it, `Tip:`/`Note:`/`Important:` wrappers around single sentences. The reader is a model; visual decoration costs tokens with no benefit. See `references/writing-patterns.md` § Density.
- **Decorative links to external specs and intra-document anchors.** `[agentskills.io spec](https://agentskills.io/specification)`, `[Platform targeting](#platform-targeting)`, bare citation URLs at the end of a sentence — these are documentation aesthetics. The agent does not click during normal execution; the whole SKILL.md is already in context. Anchor links break on heading rename and add nothing the model could not get from "see § Platform targeting below". External URLs are noise unless the agent is genuinely expected to `WebFetch` them as part of the procedure (rare). Functional links to bundled files — `[references/foo.md](references/foo.md)` — are different: the path is the operand the agent passes to Read/bash, the link text gives loading context. Keep those.
- Verbose explanations of well-known concepts.
- Multiple equivalent options without a default.
- Windows backslash paths.
- Deep reference chains (SKILL.md → a.md → b.md).
- Time-sensitive notes ("After August 2025 ..."). Move to an "Old patterns" section.
- Inconsistent terminology.
- Heavy `MUST`s without reasoning.
