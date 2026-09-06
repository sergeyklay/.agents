# Reviewing an existing skill

The five-step audit for reviewing or improving a skill that already exists.

When the user asks to review or improve a skill, run all of these in addition to mechanical validation. Each step has a fix path, not just a diagnosis.

1. **Parse intent.** Read the frontmatter for `disable-model-invocation`, `user-invocable`, and (for Codex) `agents/openai.yaml` `policy.allow_implicit_invocation`. The intended invocation model determines what counts as a problem in the description and elsewhere.
2. **Description audit.**
   - User-invoked only? Flag any "Use when ..." trigger phrases as dead tokens — propose a terse user-facing label instead.
   - Model-invoked? Flag missing triggers, vagueness, first/second person, marketing fluff that crowds out actionable triggers, and over-broad scope without negative triggers.
3. **Platform audit.** Confirm whether the skill is single-vendor or cross-platform.
   - Single-vendor skill missing vendor extensions that would help (e.g., a Claude-only `commit` skill without `disable-model-invocation` or `argument-hint`)? Propose adding them.
   - Cross-platform skill using vendor-only fields? Propose removing them or splitting the skill.
4. **Density audit.** Scan the body and references for the patterns in `references/writing-patterns.md` § Density: hard wraps that imply meaning, blockquote-wrapped examples, ladders of nested indented bullets, "why this works" paragraphs after every example, redundant restatements of a rule already stated by a code block, single-sentence `Tip:`/`Note:` wrappers, decorative external-spec citations, intra-document anchor links (use plain "see § X below" instead), bare citation URLs that the agent will never fetch. Flag and propose tighter alternatives. Lead by example: do not write the review report itself in the style being criticized.
5. **Structural audit.** Run `scripts/validate_skill.py` for body length, reference depth, forward slashes, frontmatter validity.

The order matters. Step 1 reframes Step 2; without it, you will give bad advice about the description.
