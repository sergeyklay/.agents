# Platform → vendor mapping

Each agent platform loads skills from a known set of `.{vendor}/skills/` paths. Use the running agent's self-knowledge — its system prompt, its `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` context files, or its platform documentation — to pick the vendor names below. Do not equate "exists on disk" with "I will load this".

| Running agent | Vendor names to pass |
|---|---|
| Anthropic Claude Code | `claude` (also `agents` if the install reads the cross-platform convention) |
| OpenAI Codex | `agents` |
| Cursor | `cursor` (also `agents` if configured to read the cross-platform convention) |
| Gemini CLI | `gemini`, `agents` |
| GitHub Copilot (VS Code) | `github` (project scope), `copilot` (user scope) |
| OpenCode / Antigravity | `agents` |
| Windsurf | `windsurf` |

Treat the table as a reference, not a permanent contract — vendor lists drift as platforms adopt or drop the cross-platform convention.

## Degraded fallback: filesystem probe

If the agent cannot determine its own identity from context (rare, but possible inside sandboxed sub-agents), probe the filesystem and mark the resulting list as uncertain in the response:

```bash
detected=$({
  find . -maxdepth 2 -type d -path './.*/skills' 2>/dev/null
  find "${HOME}" -maxdepth 2 -type d -path "${HOME}/.*/skills" 2>/dev/null
} | awk -F/ '{name=$(NF-1); sub(/^\./, "", name); print name}' \
  | sort -u | paste -sd, -)
echo "detected vendors (uncertain): ${detected:-<none>}"
```

The filesystem probe **over-reads**: it returns every vendor prefix present on disk, including ones the running agent does not actually load. Prefer the self-knowledge table above whenever it applies.

## Empty result

If the resolved list is empty either way (no readable vendor directories), skip the Phase 2 script call and treat the result as "no existing skills to deduplicate against" — the candidate gap proceeds to Phase 3 unimpeded.
