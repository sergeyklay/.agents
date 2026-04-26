---
name: "Context7 Documentation Retrieval"
description: "When and how to use Context7 MCP to fetch live library documentation instead of relying on training data"
applyTo: '**'
---

# Context7 Usage

Context7 fetches live, version-specific documentation for external libraries, frameworks, SDKs, and APIs. Use it to prevent hallucinated symbols and outdated code patterns. Do not use it as a general knowledge base.

## Two-Step Workflow

Every Context7 interaction follows two calls in strict sequence.

**Step 1 — Resolve the library ID.** Call `resolve-library-id` with the human-readable library name and your current question. Do not guess library IDs.

**Step 2 — Query the documentation.** Call `query-docs` with the resolved ID, a specific question, and optionally a topic filter and token budget.

Do not call `query-docs` without first calling `resolve-library-id`, unless the user has explicitly provided a Context7 ID in `/org/project` format.

## When to Use Context7

Use Context7 when writing or modifying code that depends on an **external library's API surface** and any of these conditions hold:

- The library has had breaking changes between major versions.
- The API in question was introduced or modified after your training cutoff.
- You are unsure whether a function, method, class, or parameter exists in the version this project pins.
- You are about to call a third-party REST API or SDK whose request/response shape you cannot quote verbatim from memory.
- The user asks you to use Context7, "check the latest docs", or verify against upstream.

| Scenario | Context7 useful? | Reason |
|---|---|---|
| Third-party REST APIs (Jira, GitHub, Stripe, Slack, etc.) | Yes | Endpoints, auth flows, and field schemas evolve continuously |
| Web frameworks across major versions (Next.js, Django, Rails, Spring Boot, etc.) | Yes | Routing, middleware, and config shapes change between majors |
| Niche or recently released packages | Check first | May not be indexed — call `resolve-library-id` and fall back to the upstream registry if not found |
| Mature libraries with slow release cycles and stable APIs | No | Training data is usually sufficient |
| Language standard libraries (Python stdlib, Go stdlib, Node built-ins, Java SE, etc.) | No | Backward-compatible, excellent first-party docs |

## When Not to Use Context7

Do not call Context7 when:

- The answer exists in this project's own authoritative documentation (architecture docs, ADRs, `AGENTS.md`, `CLAUDE.md`, READMEs, internal wikis). Project-internal docs are always authoritative over external sources.
- The question is about a general programming concept (data structures, algorithms, design patterns, concurrency theory). Use training knowledge or web search.
- The library is part of the language's standard library and the API in question is mature. Standard libraries are backward-compatible and training data is reliable.
- You already have high confidence in the API from recent, verified training data and the library has not had a major release since.

## Writing Effective Queries

### Query specificity

Context7 uses vector search to rank documentation. Vague queries return diluted, irrelevant content.

```
Bad:  "How do I use Jira API?"
Good: "How do I search issues using JQL in Jira Cloud REST API v3 with pagination?"

Bad:  "Tell me about the database driver"
Good: "How do I execute a parameterized query with a cancellation token in <library> v<major>?"
```

A good query names the library, the major version, the specific operation, and any non-default constraints (pagination, cancellation, streaming, auth scheme).

### Topic filter

The optional `topic` parameter narrows results by keyword. Use it when the library has broad documentation and you need a specific section.

```
query-docs({
  libraryId: "/atlassian/jira",
  query: "How do I transition an issue via REST API?",
  topic: "transitions"
})
```

Use one-word topics matching the library's documentation structure: `authentication`, `pagination`, `webhooks`, `migrations`, `middleware`, `transactions`, `routing`, `caching`, `streaming`.

### Token budget

| Scenario | Tokens | Rationale |
|---|---|---|
| Single API call signature | 3000 | Minimal context needed |
| Feature implementation with examples | 5000 | Default; good balance |
| Multi-step setup or migration guide | 8000–10000 | Broad context needed |

Context7 ranks results: code examples first, API signatures second, prose last. Higher budgets include more prose, not necessarily more useful code.

## Handling Failures

If `resolve-library-id` returns "No libraries found":

1. Try alternative names (e.g., "jira cloud" instead of "atlassian jira", "nextjs" instead of "next.js", "psycopg" instead of "psycopg2-binary").
2. If still not found, the library is not indexed. Fall back to the package's official registry (npm, PyPI, crates.io, pkg.go.dev, Maven Central, RubyGems, NuGet, etc.) or its upstream repository.
3. Do not retry the same query. Do not fabricate a library ID.

If `query-docs` returns irrelevant content:

1. Narrow the `topic` parameter.
2. Rephrase the `query` to be more specific.
3. Reduce the `tokens` budget to force higher-relevance filtering.

## Rules

- Do not call Context7 speculatively "just in case." Each call consumes tokens and latency. Use it when there is a concrete question about an external API.
- Do not trust Context7 output blindly. Cross-check returned APIs against the actual library version declared in this project's dependency manifest (`package.json`, `go.mod`, `pyproject.toml`, `Gemfile`, `pom.xml`, `Cargo.toml`, `*.csproj`, etc.). If Context7 returns docs for a different major than the project pins, the answer may not apply.
- Do not use Context7 to fetch documentation for libraries this project intentionally avoids. If an ADR or architecture document forbids a dependency, do not consult its docs to "see if it would work anyway."
- When Context7 documentation conflicts with the project's authoritative docs (architecture docs, ADRs, `AGENTS.md`, `CLAUDE.md`), the project docs win. Context7 tells you what an external library *can* do; the project docs tell you what this project *will* do.
