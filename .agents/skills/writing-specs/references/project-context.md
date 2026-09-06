# Project context: reading order

The documents a specification must conform to, in the order to read them. Stop reading once you have enough; do not load files that do not exist.

1. **Project-level agent instructions**, in this priority order: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`. Read every file that exists; do not assume any of them is canonical. When they disagree, treat the most recently modified one as authoritative and surface the conflict in your output.
2. **Documentation index**: if `docs/` exists, read `docs/README.md` (or the closest equivalent: `docs/index.md`, `docs/SUMMARY.md`, `docs/DIGEST.md`). Use it as a map. Open the individual documents it references only when they constrain the feature you are specifying.
3. **Architecture and product docs** named by the documentation index: `architecture.md`, `ARCHITECTURE.md`, `design.md`, `PRD.md`, `product.md`, or whatever name the project uses.
4. **Decision records**: `docs/decisions/`, `docs/adr/`, `adr/`, `ADR/`, or whatever path the project uses. Read the index file first; read individual records only when they constrain this feature. Treat accepted decisions as architectural law.
5. **Language and style rules** the project ships under `.agents/rules/`, `.github/instructions/`, `.copilot/instructions/`, `.claude/rules/`, or referenced from the agent-instruction file. These constrain spec prose (RFC 2119 keywords, banned vocabulary, comment style, etc.).
