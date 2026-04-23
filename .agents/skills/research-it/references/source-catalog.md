# Source Catalog

## Contents

- Tier 1 — Ground truth (source code, specifications, official docs)
- Tier 2 — Reasoning behind decisions (design docs, author writing)
- Tier 3 — Independent technical sources (academic literature, engineering blogs)
- Tier 4 — Community knowledge (Stack Overflow, technical blogs)
- Tier 5 — Wikipedia
- Tier 6 — Forums and social (Reddit, HN, GitHub issues)
- Tier 7 — Training data
- Cross-cutting investigation tips

A catalogue of source types you can consult during investigation. For each: what it is good for, what its biases are, and how to access it. Read this when deciding *which* sources are worth consulting for a given question.

The catalogue is grouped by tier in the source-priority hierarchy from `SKILL.md`. The hierarchy is the default ranking; this file explains the **when** and **why** behind each tier.

## Tier 1 — Ground truth

These are the sources where the actual behaviour, specification, or authoritative reference lives. Treat them as primary evidence.

### Source code

**Strengths.** The implementation is the implementation. Documentation can be wrong; behaviour cannot lie about itself. Reading code reveals execution paths, data structures, error handling, and edge cases that no other source captures.

**Biases.** Source code without context can be misread — a commented-out block, a feature gate, or a version branch can make an irrelevant code path look authoritative. Always confirm the code path is actually reached for the configuration the question concerns.

**How to access.**

- **Local workspace.** When working in a project, read it directly with filesystem tools.
- **GitHub.** Use the `github_repo` tool (when available), or fetch raw files via the `https://raw.githubusercontent.com/...` URL pattern, or fetch rendered files via `https://github.com/.../blob/...`.
- **Other forges.** GitLab, Codeberg, sourcehut, Bitbucket — all support raw file URLs.
- **Mirrored stdlib / runtime.** For language standard libraries and runtimes (Go, Python, Node, JVM, .NET), the canonical repository is usually on GitHub or the language's own forge.

**Investigation tip.** When tracing a behaviour, search for the **error message text** or **log line text** in the source. This is faster than walking call graphs from the entry point.

### Authoritative specifications

**Strengths.** RFCs, ISO standards, W3C recommendations, language specifications — these are the agreed-on text against which implementations are measured. When the question is "what does the standard say?" this is the only source that counts.

**Biases.** Specifications can be ambiguous, can have errata that supersede the original text, and can be widely ignored by implementations. Implementation-defined behaviour is a real category — when the spec says so, the standard is not the answer; the implementation is.

**How to access.**

- **IETF RFCs.** `https://www.rfc-editor.org/rfc/rfcXXXX` (replace XXXX with the number). Always check the document status — some RFCs are Historic or Obsoleted.
- **W3C.** `https://www.w3.org/TR/<spec-name>/` for current recommendations. Confirm the document is in REC status, not WD or CR.
- **WHATWG.** `https://<spec>.spec.whatwg.org/` — these are living standards, so the URL is always current but the content moves.
- **ISO standards.** Often paywalled; check whether a freely available draft (e.g. `Nxxxx` working papers for C and C++) covers the question.
- **Language specifications.** Each language hosts its own — Go's spec at `go.dev/ref/spec`, Python's at `docs.python.org/.../reference/`, ECMA-262 at `tc39.es/ecma262/`, etc.

### Official documentation

**Strengths.** First-party documentation reflects the maintainers' intent, includes API contracts and supported usage patterns, and is usually the best source for **how something is meant to be used**.

**Biases.** Documentation lags implementation. It can document aspirational behaviour or deprecated patterns. It rarely documents bugs, undocumented flags, or behaviour-by-accident.

**How to access.**

- **Project's own site.** Almost always reachable via the project's homepage or GitHub README.
- **`context7` MCP server.** When available, this gives versioned programmatic access to documentation for many popular libraries and frameworks. Prefer it over web fetch for docs of supported libraries — it returns structured, versioned content.
- **Vendor cloud documentation.** AWS, GCP, Azure, Cloudflare all maintain searchable doc sites with stable URLs.

**Investigation tip.** When the docs say one thing and the source code does another, the conflict itself is the answer. Both should be cited.

## Tier 2 — Reasoning behind decisions

These sources tell you *why* something was built the way it was, which is often necessary to explain it well.

### Design documents and decision records

**Strengths.** ADRs (Architecture Decision Records), design docs, KEPs (Kubernetes Enhancement Proposals), PEPs (Python Enhancement Proposals), TC39 proposals, RFC discussion threads — these capture the alternatives considered, the tradeoffs evaluated, and the reasoning that led to the final decision.

**How to access.**

- **PEPs.** `https://peps.python.org/pep-XXXX/`
- **KEPs.** `https://github.com/kubernetes/enhancements/tree/master/keps`
- **TC39 proposals.** `https://github.com/tc39/proposals`
- **Project ADRs.** Usually in `docs/adr/`, `docs/decisions/`, or `architecture/` within the project repo.

### Author and core-contributor writing

**Strengths.** When the person who built the thing writes about it, you get the design intent and the historical context that no other source contains. Russ Cox on Go internals, Dan Abramov on React, Lin Clark on Rust and Wasm, Hillel Wayne on formal methods — these are primary sources even when published as blog posts.

**Biases.** Authors are not neutral about their own work. They may under-report failure modes, over-claim novelty, or describe an aspirational version of the system rather than the shipped one.

**How to access.**

- The author's personal site or company engineering blog.
- Conference talk recordings (YouTube, InfoQ, Strange Loop archive).
- Long-form interview podcasts (Software Engineering Daily, Changelog).

## Tier 3 — Independent technical sources

### Peer-reviewed academic literature

**Strengths.** Methodological rigour, explicit experimental setup, and (in strong venues) external review. The right place to ground claims about algorithms, performance characteristics, and theoretical limits.

**Biases.** Publication bias toward novel results, gap between research prototypes and production systems, slow update cycle.

**How to access.**

- **arXiv.** `https://arxiv.org/abs/XXXX.XXXXX` — pre-prints, **not** peer reviewed. Useful as the fastest source on current ML research, but treat arXiv-only claims as preliminary unless cross-referenced.
- **Conference proceedings.** USENIX (OSDI, NSDI, ATC, Security), ACM (SOSP, SIGCOMM, SIGMOD, PLDI), IEEE (S&P) — these are top-tier and searchable through their respective digital libraries or open-access proceedings.
- **Google Scholar.** Useful as a search index. Do not cite it; cite the underlying paper.
- **Semantic Scholar.** Better citation graph than Google Scholar for ML/AI work.

**Investigation tip.** For any influential paper, check whether a **follow-up paper or retraction** exists. The ML field in particular has a high rate of "actually X did not reproduce" follow-ups.

### Engineering blog posts from credible organisations

**Strengths.** Anthropic Engineering, OpenAI's research index, Google Research blog, AWS Architecture blog, Cloudflare Engineering, Stripe Engineering, Netflix Tech Blog, Uber Engineering, Discord Engineering — these publish post-mortems, system designs, and benchmarks at production scale that academia rarely matches.

**Biases.** Each is also marketing for the publishing organisation. Claims favourable to the publisher should be triangulated.

## Tier 4 — Community knowledge

### High-quality community content

**Strengths.** Stack Overflow answers (especially highly upvoted ones with working code), independent technical blogs by recognised practitioners (Julia Evans, Dan Luu, Bartosz Ciechanowski, Jay Kreps, Martin Kleppmann), and well-curated awesome-* lists.

**Biases.** Quality variance is enormous. Stack Overflow answers from 2012 may describe behaviour that no longer exists. SEO-optimised "top 10 X" listicles are usually content farming and should be ignored.

**Detection heuristic for content farms.** Multiple short articles on the same domain covering wildly different topics, with thin AI-generated prose and no named author with a verifiable track record. Do not cite these.

## Tier 5 — Wikipedia

**Strengths.** Excellent entry point for unfamiliar topics. The "References" section at the bottom is often more valuable than the article itself — follow those citations to primary sources.

**Biases.** Article quality varies enormously by topic. Heavily edited controversial topics may show a flattened consensus that hides genuine disagreement. Niche technical topics may be out of date.

**Rule.** Wikipedia is for orientation and as an index of further reading. **Cite Wikipedia's sources, not Wikipedia itself**, in the output.

## Tier 6 — Forums and social

### General-purpose forums

**Strengths.** Reddit (especially `/r/programming`, `/r/MachineLearning`, `/r/ExperiencedDevs`, language-specific subreddits), Hacker News, Lobsters, language Discord servers — useful for **sentiment** ("is X widely considered broken?"), **pointers to primary sources** that you would not have found via search, and **post-mortems of failures** that companies never write up themselves.

**Biases.** Confidently wrong answers, hype cycles, recency bias, and Eternal September dynamics on large subs.

**Rule.** Forums point at evidence. Forums are not evidence. If a Reddit thread leads you to an authoritative source, cite the source, not the thread.

### GitHub issues, discussions, and PRs

**Strengths.** When the question is "is this a known bug?", "why was this designed this way?", "what was the rationale for this default?" — GitHub issues, PR discussions, and the `Discussions` tab on a project's repo are often the only place the answer was ever written down. Maintainer comments on issues are de-facto authoritative for the project.

**Biases.** Issues can be stale, opinions in PR threads may have been overruled, and the discussion may have moved to private channels.

**How to access.** Through the GitHub MCP server when available, or via web fetch of the issue/PR URL.

## Tier 7 — Training data

Training data is the **starting point** for investigation. It tells you what to search for, what terminology to use, and what the rough shape of the answer might be.

It is **never** the final source. Anything cited as fact in the output must have been verified against a tier-1 to tier-6 source in the current session.

The reason: training data is a frozen, lossy compression of a snapshot of the internet from before some cutoff date. It does not know about anything released or changed since then. It can confidently produce facts that were never true, that are no longer true, or that were true only in a specific version that is no longer current.

## Cross-cutting investigation tips

- **For any actively maintained library or framework, verify currency before citing.** Versions, defaults, deprecations, and even names change frequently. The library that was "the standard" in 2023 may be unmaintained in 2026.
- **For any cloud service, check the changelog.** AWS, GCP, Azure, and Cloudflare all publish changelogs; a service's behaviour today is the cumulative result of every entry since its launch.
- **For any AI/ML model claim, check the model card and the release date.** "GPT-4 does X" is meaningless without specifying which checkpoint and when — model behaviour shifts across releases.
- **For any historical claim about who built or designed something, check multiple independent biographies.** Founder narratives shift over time and self-aggrandise.
