# `discover_skills.py` reference

Full command surface, output schema, ordering and precedence rules, and the manual bash fallback. Load this only when the default invocation in `SKILL.md › Phase 2` is not enough.

## Default output

XML, one `<skill>` element per installed skill, three fields per record in fixed order. XML is the default because Anthropic's published guidance recommends XML-tagged inputs to Claude, and because freeform `description` text round-trips cleanly through entity escaping.

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

An empty result set is `<skills/>` (self-closing).

## Opt-in fields

Pass any combination when the caller needs extra context.

| Flag | Field added (canonical position) | When to pass |
|---|---|---|
| `--with-type` | `<type>project\|user</type>` before `<name>` | Distinguishing project-local from user-global skills matters to the decision the caller is making. |
| `--with-agent` | `<agent>vendor-name</agent>` between `<type>` and `<name>` | Cross-vendor disambiguation matters (rare — name collisions across vendors are already resolved by the precedence rule). |
| `--with-path` | `<path>…</path>` at the end of the record | The caller actually needs to open or edit a SKILL.md. |

Example with all three:

```bash
python3 scripts/discover_skills.py --vendors "$vendors" \
  --with-type --with-agent --with-path
```

Flags compose: pass any subset. Field order is always canonical (`type, agent, name, category, description, path` — with absent opt-ins collapsed out) regardless of the flag combination.

When `<path>` is emitted, project-scope entries are rendered relative to the project root (e.g. `.claude/skills/foo/SKILL.md`); user-scope entries are abbreviated with a leading `~` (e.g. `~/.claude/skills/foo/SKILL.md`). The path shape itself signals scope, so `--with-path` is informative even without `--with-type`. Anything discovered through a symlink that escapes both roots stays absolute.

## Format

`--format` accepts `xml` (default), `json`, `markdown`, and `csv` (RFC 4180 with a header row — fields containing commas, quotes, or newlines are quoted by the standard library `csv` module, embedded quotes doubled, and the header row is emitted even on empty results so the schema is communicated).

## Ordering

`--order-by` sorts alphabetically; default is `category` with `name` as the stable secondary key. The agent treats every returned skill with equal priority, so a deterministic alphabetical scan is more useful than discovery order. Any field name from the canonical schema is a valid sort key — including opt-in ones (`--order-by path` works without `--with-path` in the rendered output, the sort still applies).

```bash
python3 scripts/discover_skills.py --vendors "$vendors" --order-by name
python3 scripts/discover_skills.py --vendors "$vendors" --order-by type --with-type
```

## Precedence

When the same skill `name` exists in both user (home) and project scopes, the script emits only the user entry and drops the project copy. This matches what every supported agent actually loads at runtime when both are present, so the agent never sees a phantom project version that would never actually win at activation time. If a name appears multiple times within the *same* scope (e.g. installed under two different vendor prefixes), all entries are preserved — that is a genuine multi-install, not a shadow.

## Other flags and exit codes

- `--list-supported` — enumerate the accepted vendor set without triggering a discovery scan.
- `--no-home` — scope to the project, suppress user-scope entries.
- `--help` — full surface.

Exit codes: `0` clean, `1` some SKILL.md unreadable (results still printed), `2` missing/empty/unsupported `--vendors` or contradictory scope flags.

## Manual fallback (no python3)

If `python3` or `discover_skills.py` is unavailable, do the whole job in bash — same detection logic, then awk out each frontmatter block directly:

```bash
{ find . -maxdepth 3 -path './.*/skills/*/SKILL.md' 2>/dev/null
  find "${HOME}" -maxdepth 3 -path "${HOME}/.*/skills/*/SKILL.md" 2>/dev/null
} | while read -r f; do
  echo "=== $f ==="
  awk '/^---$/{c++; if(c==2) exit} c==1' "$f"
done
```
