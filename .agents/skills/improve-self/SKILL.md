---
name: improve-self
description: "Detect when a missing Agent Skill would have made the current task faster or more reliable, then scaffold a candidate SKILL.md for user review. Use after a non-trivial task when one of these signals fires: the same procedure repeated 3+ times, error recovery required inventing a workflow, the user corrected the approach (not the answer), the agent realized mid-task that a playbook did not exist, or 5+ tool calls produced what should have taken 1-2. Detects which `.{vendor}/skills/` directories actually exist on the host (project and home), reads every existing SKILL.md across them before proposing, and never duplicates. Writes candidates into the project's preferred .{vendor}/skills/{name} directory — .agents/skills/ by default — never the home folder. Do NOT use for first-attempt failures, one-off questions, fact gaps that belong in research, or style gaps that belong in rules files."
context: fork
metadata:
  author: Serghei Iakovlev
  version: "1.0"
  category: meta
---

# Improving Self by Closing Skill Gaps

This skill turns the trace of just-completed work into a question: *was there a procedure I should have had written down?* When the answer is yes, it scaffolds a new Agent Skill into the current project. The mechanism is the lineage of Voyager's growing skill library (Wang et al., 2023), Reflexion's verbal self-feedback (Shinn et al., 2023), Hermes Agent's autonomous skill creation, and OpenClaw's self-improving-agent — adapted so the human stays in the loop on every write.

The discipline is conservative by design. A skill created for a one-off question becomes long-term noise in the activation context of every future task. A skill created without checking existing skills becomes a duplicate and a confusion vector. A skill encoding a version-specific or transient behavior (the failure mode documented in NousResearch/hermes-agent#25833) becomes a permanent footgun. The bar for creation: a concrete, recurring, procedural gap that survived a check against every existing skill, with the user signing off on the draft.

## Running scripts bundled with this skill

Script paths are resolved relative to **this** SKILL.md, not the agent's CWD. If a relative command (for example `python3 scripts/discover_skills.py`) fails to resolve, prefix it with the directory the platform loaded SKILL.md from — e.g. `python3 .agents/skills/improve-self/scripts/discover_skills.py`.

**Fallback.** If `python3` is missing or the script cannot be located, every procedure here ships a manual alternative — follow that instead.

## What counts as a gap

A gap is **procedural and recurring**. Not every difficulty is a gap.

| Pattern in the trace | Skill-shaped? |
|---|---|
| The agent repeated the same 3-step lookup three times in one task | Yes |
| The agent figured out a non-obvious investigation workflow from scratch and it worked | Yes |
| The agent recovered from an error by inventing a procedure that should be reusable | Yes |
| The user corrected the agent's *approach* with "no, here we always do X first" | Yes |
| The agent realized mid-task it lacked a playbook other agents would also face | Yes |
| The agent did not know a *fact* ("what is the Kafka default port?") | No — research gap, not skill gap |
| The agent failed once and recovered easily | No — one-off, not recurring |
| The task was complex but succeeded smoothly | No — complexity ≠ missing procedure |
| The agent had to consult unfamiliar library docs | No — that is what `research-it` is for |
| The task succeeded without struggle | No — nothing to fix |

Decision rule: **would the agent copy this procedure from memory next time, verbatim?** If yes, write it down. If no, it is not a skill.

## Trigger conditions

Self-assessment runs at the end of a task when **at least one** of these signals is observable in the trace. The signals are concrete; the agent does not need to guess.

1. **Repetition signal.** The agent invoked the same procedural pattern (sequence of tool calls or reasoning steps) three or more times in the task. The third occurrence is the trigger. Example: the agent re-derived "how to find the canonical Postgres source for a behavior" three times across the conversation.
2. **Recovery signal.** The agent hit an error (tool failure, wrong assumption, dead end) and only made progress after inventing a procedure not in any existing skill. The procedure that worked is the candidate. Example: the agent realized mid-task that a particular gRPC server returned proto3 fields with non-default zero-values in a non-obvious way, and worked out a verification pattern.
3. **Correction signal.** The user explicitly corrected the agent on *how* to approach something, not just on the answer. Quoted phrases like "no, here we do X" or "next time, start with Y" are strong. Pure answer corrections ("the value is 16, not 8") are *not* triggers — those are research gaps.
4. **Missing-affordance signal.** The agent noticed mid-task that a needed playbook did not exist anywhere across the `.{vendor}/skills/` directories that actually exist on this host (Phase 2 step A enumerates them). Phrasing in the agent's own reasoning like "I had to discover that …" or "it would help to have a documented procedure for …" is the marker.
5. **Effort-vs-payoff signal.** The task took five or more tool calls for a result that, with the right procedure, would have taken one or two. The yardstick from Hermes Agent's GEPA loop: "a task that took 47 tool calls might have completed in 12 with a better skill." If the agent can describe the better skill concretely, that skill is the candidate.

If none of these fire, do not run self-assessment. False-positive gaps create churn in the skill library.

## Workflow

### Phase 1 — Restate the gap precisely

Write down, internally:

1. The trigger signal that fired (one of the five above), named.
2. The concrete evidence in the trace: specific tool calls, error messages, user quotes, or repeated patterns. A gap claim without trace evidence is fabricated.
3. The procedure as the agent would write it for itself: numbered steps, with inputs and outputs.

If the procedure runs to more than ten numbered steps before any branching, the gap is too broad. Split it into the narrowest reusable subprocedure. Monolithic skills do not activate precisely (see `make-skill` anti-patterns).

Restate the gap as a single sentence that names the procedural domain. Good: "investigation procedure for verifying Postgres MVCC behavior across major versions." Bad: "Postgres stuff." The narrower phrasing is also the working draft of the new skill's description.

### Phase 2 — Check existing skills (mandatory)

Skipping this phase is the single most common way a self-improvement workflow degrades the skill library. Discovery is a two-step procedure so the agent only consults the vendor prefixes it actually reads at runtime — not every `.{name}/skills/` directory that happens to exist on the filesystem.

**Step A — Identify the vendor directories THIS agent reads from.** Each platform loads skills from a known set of `.{vendor}/skills/` paths. The running agent already has that information — from its own system prompt, its `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` context files, or its platform documentation. Use that self-knowledge directly; do not equate "exists on disk" with "I will load this".

The current platform → vendor mapping (per the agentskills.io storage matrix; treat as a reference, not a permanent contract):

| Running agent | Vendor names to pass |
|---|---|
| Anthropic Claude Code | `claude` (also `agents` if the install reads the cross-platform convention) |
| OpenAI Codex | `agents` |
| Cursor | `cursor` (also `agents` if configured to read the cross-platform convention) |
| Gemini CLI | `gemini`, `agents` |
| GitHub Copilot (VS Code) | `github` (project scope), `copilot` (user scope) |
| OpenCode / Antigravity | `agents` |
| Windsurf | `windsurf` |

If the agent cannot determine its own identity from context (rare, but possible inside sandboxed sub-agents), probe the filesystem as a degraded fallback and explicitly mark the resulting list as uncertain in the response:

```bash
detected=$({
  find . -maxdepth 2 -type d -path './.*/skills' 2>/dev/null
  find "${HOME}" -maxdepth 2 -type d -path "${HOME}/.*/skills" 2>/dev/null
} | awk -F/ '{name=$(NF-1); sub(/^\./, "", name); print name}' \
  | sort -u | paste -sd, -)
echo "detected vendors (uncertain): ${detected:-<none>}"
```

The filesystem probe **over-reads**: it returns every vendor prefix present on disk, including ones the running agent does not actually load. Prefer the self-knowledge table above whenever it applies.

If the resolved list is empty either way (no readable vendor directories), skip the Phase 2 script call and treat the result as "no existing skills to deduplicate against" — the candidate gap proceeds to Phase 3 unimpeded.

**Step B — Hand the resolved list to the discovery script.** Save it into a variable for the script call:

```bash
vendors=<comma-separated names from Step A>
python3 scripts/discover_skills.py --vendors "$vendors"
```

`--vendors` is **mandatory**; the script validates each name against its supported set and refuses unknown names with an exit-2 error that lists the accepted vendors so the agent can self-correct.

Output is structured XML by default — one `<skill>` element per installed skill, with three fields in a fixed order (`<type>`, `<agent>`, and `<path>` are opt-in; see below). XML is the default because Anthropic's published guidance recommends XML-tagged inputs to Claude, and because freeform `description` text round-trips cleanly through entity escaping:

```xml
<skills>
  <skill>
    <name>some-skill</name>
    <category>review</category>
    <description>…</description>
  </skill>
  <skill>
    <name>another-skill</name>
    <category></category>
    <description>…</description>
  </skill>
  …
</skills>
```

`<category>` is read from `metadata.category` (project convention) and falls back to a top-level `category:` if `metadata` is omitted. When a skill defines neither, the section is emitted empty (`<category></category>`) rather than dropped, so the record schema stays stable.

**Three fields are opt-in.** The default output answers "which skills exist, how are they classified, what do they do?" — nothing more. Pass any combination of the flags below when the caller needs the additional context:

| Flag | Field added (canonical position) | When to pass |
|---|---|---|
| `--with-type` | `<type>project\|user</type>` before `<name>` | Distinguishing project-local from user-global skills matters to the decision the caller is making. |
| `--with-agent` | `<agent>vendor-name</agent>` between `<type>` and `<name>` | Cross-vendor disambiguation matters (rare — name collisions across vendors are already resolved by the precedence rule). |
| `--with-path` | `<path>…</path>` at the end of the record | The caller actually needs to open or edit a SKILL.md. |

Example with all three flags:

```bash
python3 scripts/discover_skills.py --vendors "$vendors" \
  --with-type --with-agent --with-path
```

`--format` accepts `xml` (default), `json`, `markdown`, and `csv` (RFC 4180 with a header row — fields containing commas, quotes, or newlines are quoted by the standard library `csv` module, embedded quotes doubled, and the header row is emitted even on empty results so the schema is communicated).

Flags compose: pass any subset. Field order is always canonical (`type, agent, name, category, description, path` — with absent opt-ins collapsed out) regardless of the flag combination.

**Ordering.** The result is sorted alphabetically by `--order-by` (default: `category`, with `name` as the stable secondary key). The agent treats every returned skill with equal priority, so a deterministic alphabetical scan is more useful than discovery order. Any field name from the canonical schema is a valid sort key — including opt-in ones (`--order-by path` works without `--with-path` in the rendered output, the sort still applies). Override when a different grouping helps the task at hand:

```bash
python3 scripts/discover_skills.py --vendors "$vendors" --order-by name
python3 scripts/discover_skills.py --vendors "$vendors" --order-by type --with-type
```

When `<path>` is emitted, project-scope entries are rendered relative to the project root (e.g. `.claude/skills/foo/SKILL.md`); user-scope entries are abbreviated with a leading `~` (e.g. `~/.claude/skills/foo/SKILL.md`). The path shape itself signals scope, so `--with-path` is informative even without `--with-type`. Anything discovered through a symlink that escapes both roots stays absolute.

An empty result is `<skills/>` (self-closing).

**Precedence.** When the same skill `name` exists in both user (home) and project scopes, the script emits only the user entry and drops the project copy. This matches what every supported agent actually loads at runtime when both are present, so the agent never sees a phantom project version that would never actually win at activation time. If a name appears multiple times within the *same* scope (e.g. installed under two different vendor prefixes), all entries are preserved — that is a genuine multi-install, not a shadow.

To enumerate the accepted vendor set without triggering a discovery scan, run `python3 scripts/discover_skills.py --list-supported`. Other flags: `--no-home` scopes to the project, `--format json` swaps to a JSON array with the same field names, `--format markdown` produces a human-readable table, `--help` shows the full surface. Exit codes: `0` clean, `1` some SKILL.md unreadable (results still printed), `2` missing/empty/unsupported `--vendors` or contradictory scope flags.

**Fallback.** If `python3` or `discover_skills.py` is unavailable, do the whole job in bash — same detection logic, then awk out each frontmatter block directly:

```bash
{ find . -maxdepth 3 -path './.*/skills/*/SKILL.md' 2>/dev/null
  find "${HOME}" -maxdepth 3 -path "${HOME}/.*/skills/*/SKILL.md" 2>/dev/null
} | while read -r f; do
  echo "=== $f ==="
  awk '/^---$/{c++; if(c==2) exit} c==1' "$f"
done
```

Read each `description`. For each, classify against the candidate gap:

| Comparison | Action |
|---|---|
| Exact or near-overlap with an existing skill | Do not create. Either use the existing skill (re-read its body) or propose an *edit* to its SKILL.md. Surface this to the user. |
| Partial overlap (existing covers half) | Narrow the candidate to the uncovered delta. Re-state the gap. Loop back to Phase 1. |
| No overlap | Proceed to Phase 3. |

If the existing skill is close but stale or wrong, **do not silently re-author it as a new skill**. Open the original SKILL.md and propose a patch. Duplication is worse than imperfection.

### Phase 3 — Decide whether a skill is the right shape

A skill is the right shape only when all four hold:

- **Procedural** — the answer is steps, not facts.
- **Reusable** — the procedure plausibly applies to at least two future tasks.
- **Self-contained** — it does not hardcode values that change between contexts (versions, paths, customer-specific tokens, ephemeral API endpoints).
- **Testable** — there is a concrete "this worked" condition the agent can check.

If any criterion fails, route the gap to its proper home using the *Alternatives* table at the end of this file. Default to **not creating**. The cost of a skill — its presence in the activation context forever, its description competing in the model's top-of-context scan — exceeds the benefit unless all four hold.

### Phase 4 — Draft the candidate SKILL.md

Use the `make-skill` skill for the authoring discipline (frontmatter rules, body structure, density). This skill is the gap-detection front end; `make-skill` is the authoring back end.

Path: `$PWD/.{vendor}/skills/{name}/SKILL.md` in the **current working project directory**, never the home folder. Pick `{vendor}` with this decision order:

1. **`.agents/skills/`** is the default. It is the cross-platform convention (Codex native, Gemini preferred, OpenCode and Antigravity adopt it) and the directory this project uses for its own curated skills. Choose it unless something below applies.
2. **A vendor-specific directory** (`.claude/skills/`, `.opencode/skills/`, `.gemini/skills/`, `.github/skills/`, …) when the new skill genuinely depends on that vendor's frontmatter extensions — `disable-model-invocation`, `user-invocable`, `argument-hint`, `context: fork` for Claude; `policy.allow_implicit_invocation` companion file for Codex; `paths`-scoped activation for Cursor, etc. Document the dependency in the skill's own description.
3. **The same vendor directory that holds the currently-active `improve-self`**. Run `find . -path '*/skills/improve-self/SKILL.md' -not -path '*/node_modules/*' 2>/dev/null` to confirm where it lives — that location reflects the project's stated policy. If found in a vendor-specific directory, prefer the same vendor for the new skill so the library stays coherent.
4. **The user's explicit redirect** trumps the above three. If they say "put it in `.cursor/skills/`", do that.

NEVER write to `$HOME/.{vendor}/skills/` — self-generated skills belong to the project, not the user's global library.

Then call the `init_skill.py` script provided by `make-skill` to scaffold the directory and SKILL.md.

Minimum viable SKILL.md body (the scaffold's `[TODO]` placeholders must be replaced before hand-off):

```markdown
---
name: <skill-name>
description: "<what + when + scope, third person, ≤ 1024 chars>"
---

# <Title>

<One-paragraph rationale: what gap this closes, grounded in the trace evidence
gathered in Phase 1.>

## Trigger

<When the agent should load this skill, restated in agent-facing terms.>

## Procedure

1. <step with inputs and outputs>
2. <step>
3. <step>

## Validation

<How the agent verifies the procedure worked. A concrete check, not a feeling.>

## Anti-patterns

- <patterns that motivated this skill — the things that went wrong in the
  original trace and that the procedure now prevents>
```

The procedure must be exact enough that running it would have prevented the original difficulty observed in Phase 1's trace evidence. If not, the gap is not closed — refine before hand-off.

### Phase 5 — Hand off for user approval, then verify

Do not silently install. The agent is its own author, executor, and inspector for self-created skills; NousResearch/hermes-agent#25833 documents what goes wrong without an external checkpoint (deprecated APIs frozen into procedural memory, transient failures encoded as permanent avoidance). Two checkpoints before the skill counts as installed:

1. **Show the user the draft.** State, in this order:
   - The trigger signal that fired and the trace evidence (quote the messages or tool calls).
   - The Phase 2 result: which existing skills were checked, and why none of them covered the gap (or which one is close and should be edited instead).
   - The draft SKILL.md.

   Then ask explicitly whether to write the file. Do not write before the answer is yes.

2. **Validate** after writing:

Use the `validate_skill.py` script from `make-skill` to check the new SKILL.md against the style rules.

If the validator returns errors, fix and re-run. Manual fallback when no validator is reachable: frontmatter parses, `name` matches the directory, description ≤ 1024 chars and third person, body ≤ 500 lines, references one level deep, forward-slash paths only.

The gap is closed when the validator passes and the new SKILL.md sits in the chosen `.{vendor}/skills/<name>/` directory under the project root.

## Anti-patterns

These degrade the skill library and erode trust in the self-improvement loop:

- **Fabricated gaps.** Inventing a recurring pattern that did not actually occur. Defence: every gap claim cites a trace quotation in Phase 1.
- **Over-broad skills.** "Handles all Postgres questions" is monolithic and will not trigger precisely. Defence: name the *procedure*, not the *domain*.
- **Duplicate skills.** Failing to read existing descriptions before proposing. Defence: Phase 2 is non-negotiable.
- **Self-validation.** Treating the agent's confidence in the draft as sufficient quality control — Hermes Agent's identified failure mode. Defence: the user is the external validator before any write, the script-based validator after.
- **Encoding transient or version-specific behavior.** "Library X v2.3 returns a list" rots the moment v2.4 ships. Defence: skills capture *procedure* (how to find out, how to triangulate, how to verify), not facts that change.
- **Skill-shaped facts.** Information that belongs in `CLAUDE.md` or `AGENTS.md` compressed into an unwieldy skill. Defence: the *Alternatives* table below.
- **Silent installation.** Writing the file before the user has seen the draft. Defence: Phase 5 explicitly forbids it.

## Alternatives to a new skill

When the gap is not skill-shaped, route it elsewhere:

| Gap shape | Better home |
|---|---|
| A project convention everyone needs to know | `CLAUDE.md` / `AGENTS.md` |
| A coding-style rule | `.agents/rules/` or the platform's `rules/` directory |
| A one-off task with no future recurrence | Document in the current conversation; nothing persists |
| A fact about an external API | The research path next time (see `research-it`); do not hardcode |
| A capability the agent cannot do at all (auth, write-API call against a private system) | Propose an MCP server, not a skill |
| A user-triggered template with arguments | A slash command (`.agents/commands/`, `.claude/commands/`, or the platform's equivalent) |
| A repeated investigation pattern in one domain | A skill — proceed |
| A recurring explanation pattern for one topic class | A skill — proceed |

When in doubt, prefer the smaller intervention. Skills are tokens that load forever.

## On honesty

Self-assessment asks the agent to admit that it struggled. The temptation is bipolar: over-claim ("everything was a gap, I need ten skills") or under-claim ("everything went fine, no gaps"). Both are dishonest. The honest report names specific trace evidence, proposes the smallest change that closes the loop, and is comfortable with the result "no skill-shaped gap detected" when that is what the evidence shows.

For agents that load this skill mid-investigation (e.g., `sleuth`): the gaps are usually narrow — a domain-specific source catalogue, a bias-detection pattern for one kind of vendor documentation, a triangulation procedure for one class of claim, a reader-bridge template for one type of explanation. Resist the urge to write a skill called "investigating things"; that is what `research-it` already is.
