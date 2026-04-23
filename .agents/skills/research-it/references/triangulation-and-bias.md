# Triangulation and Bias

## Contents

- Why triangulation is the core discipline
- What "independent" means
- The triangulation procedure
- Classifying conflicts
- Source authority assessment
- Mitigating known LLM-investigation failure modes
- Calibrated uncertainty in the output
- When to stop

How to verify what you find, weight conflicting sources, and calibrate the uncertainty markers in the output. Read this when sources disagree, when a single source is making a load-bearing claim, or when assessing whether something you found is actually authoritative.

## Why triangulation is the core discipline

A single source supporting a claim is not evidence - it is a hypothesis about evidence. Independent confirmation is what turns a hypothesis into a fact you can responsibly state in the output.

The discipline matters because:

1. **Authoritative-looking sources are routinely wrong.** Project documentation lags implementation. Vendor blog posts oversell. Even RFCs have errata.
2. **LLMs systematically over-trust the first plausible source they find.** This is anchoring, and it shapes every search query that follows.
3. **AI-generated SEO content has flooded search results since ~2023.** Many high-ranking pages are confidently wrong syntheses of older confidently wrong pages. Independent confirmation is the only defence.

## What "independent" means

Two sources are independent only if **one being wrong does not imply the other is wrong**. Two sources that both derive from the same upstream are the same source counted twice.

| Apparently two sources | Actually one source if… |
|---|---|
| Two blog posts | Both cite the same primary source uncritically |
| A Wikipedia article and a Medium post | The Medium post was written by paraphrasing the Wikipedia article (common, hard to detect - check publication dates) |
| Two Stack Overflow answers | Both reference the same older answer or the same official doc page |
| The official docs and a vendor blog post | Same publisher; not independent |
| Source code and the project README | Both maintained by the same authors; partially independent - the README can lie about the code, but the code cannot lie about itself |

**Strong independence** comes from sources with different authorship, different incentives, and different time periods. A 2018 academic paper plus a 2024 reverse-engineering write-up by an outside party plus the current source code is strong triangulation.

**Weak independence** is two posts on the same topic from the same publisher. Treat as a single source.

## The triangulation procedure

For each claim that will appear as fact in the output:

1. **Locate the first source.** Often easy.
2. **Identify the *type* of evidence** the first source offers. Is it primary (source code, spec text)? Secondary (a write-up of a primary source)? Tertiary (a write-up of a write-up)?
3. **Search for an independent second source.** A source that, were the first source to disappear or be wrong, would still let you verify the claim.
4. **If found and consistent**, the claim is triangulated. Cite both.
5. **If found and inconsistent**, you have a *conflict*. Apply the conflict-classification procedure below.
6. **If not found**, the claim is single-sourced. Either:
   - Search harder (different vocabulary, different source type), or
   - Mark the claim as single-sourced in the output: "Per [source], …", or
   - Drop the claim from the output.

## Classifying conflicts

Not all conflicts mean what they look like. When two sources disagree, classify the conflict before deciding how to present it:

| Class | Example | What to do |
|---|---|---|
| **Terminology mismatch** | "Both call it 'context' but mean different things." | Resolve the terms, then check whether the underlying claims actually differ. |
| **Version skew** | "One source is from 2021, the other 2025; the API changed." | Note both versions. The current behaviour is the answer; the historical behaviour is context. |
| **Scope mismatch** | "One is talking about the default config; the other about the config under flag X." | Specify the scope of each claim in the output. |
| **Genuine disagreement** | "Two equally authoritative sources contradict each other on the same version, same scope." | Report both with citations. Do not silently pick. The reader needs to know there is uncertainty. |
| **One is wrong** | "The lower-tier source repeats a misconception that the higher-tier source corrects." | Cite the higher-tier source. Optionally note the misconception explicitly to head off the reader's likely follow-up. |

## Source authority assessment

When deciding how much weight to give a source, walk this checklist:

### For documentation and blog posts

- [ ] **Author is named and verifiable.** Anonymous "expert" content is tier-down at best.
- [ ] **Author has a track record on this specific topic.** Generalist content farms have many bylines on many topics with no specialisation.
- [ ] **Publication date is visible.** Undated posts about technology that changes are uncitable.
- [ ] **Code examples actually work.** AI-generated tutorials often have subtly broken examples. If a code example references methods that do not exist in the current API, the article is likely AI-generated and untrustworthy.
- [ ] **Citations to primary sources exist.** A confident technical article that cites nothing is reciting received wisdom - useful as a pointer, not as evidence.

### For source code

- [ ] **The repository is the actual upstream.** Mirrors and forks can be stale. Cross-check against the canonical URL.
- [ ] **The branch matches the version you are claiming about.** `main` contains unreleased work; tagged releases are the reliable reference for "what version X does".
- [ ] **The code path is actually reached.** Feature flags, build conditionals, and `#ifdef`-equivalents can make code look authoritative that never executes in the configuration you mean.
- [ ] **The function is the one actually called.** Multiple implementations may share a name across files; trace the import.

### For academic papers

- [ ] **Venue is named.** arXiv pre-prints have not been peer reviewed. Top-tier conferences (USENIX, ACM, IEEE flagship) are stronger than workshops.
- [ ] **Reproductions exist.** Especially in ML, the gap between "reported result" and "reproducible result" is large. Check whether independent replications were published.
- [ ] **Date is checked against the current state of the field.** A 2019 paper on LLM behaviour is reporting on systems that no longer exist in production.

## Mitigating known LLM-investigation failure modes

These failure modes are documented in the literature on LLM-driven research (Anthropic engineering, OpenAI's Deep Research write-up, the GAIA benchmark literature). They are not theoretical - they are predictable ways the present investigation will fail unless actively defended against.

### Hallucinated citations

**Symptom.** Plausible-looking links and titles that do not actually exist when fetched.

**Defence.** Only cite URLs that have been actually fetched in the current session. Only cite files that have actually been read. If a citation cannot be verified by re-fetching it now, do not cite it - find a real one or drop the claim.

### Confidence miscalibration

**Symptom.** Stating a single-sourced or unverified claim with the same confidence as a triangulated one.

**Defence.** Use **explicit uncertainty markers** for every claim that is not triangulated:

- "Per [source], …" - single source, hedge implied by the citation
- "Based on the [source], my best inference is …" - derivation, not direct evidence
- "I could not find authoritative confirmation of …" - explicit unknown

The reader does not need everything answered. The reader needs to know which answers they can build on and which they should verify themselves.

### SEO content-farm preference

**Symptom.** The first search result is a cleanly-written, recently-dated "Top 10 Things You Need to Know About X" post from a domain that publishes on every topic. It looks authoritative because it is well formatted.

**Defence.** Actively prefer the source-priority hierarchy from `SKILL.md` over Google ranking. Skip past content-farm domains. If a content farm is the only source for a claim, the claim is unsupported, not single-sourced.

Detection heuristics for content farms:

- The domain publishes on dozens of unrelated technical topics.
- No named authors with verifiable track records.
- Heavy boilerplate ("In this comprehensive guide we will explore…").
- Code examples that do not compile or use deprecated APIs.
- Repeated keyword stuffing.

### Anchoring on the first source

**Symptom.** The first source's vocabulary, framing, and biases shape every follow-up search query, narrowing the investigation to confirmation of the first source's worldview.

**Defence.** After the first source, deliberately search using **different vocabulary** - synonyms, the opposing-camp terminology, the academic term if the first source was a blog post (or vice versa). The second search should not look like a refinement of the first.

### Snippet summarisation

**Symptom.** Building an answer from the 2-line previews shown in search results, without ever loading the full pages.

**Defence.** Fetch and read full pages before citing. If full content is not available (paywalled, deleted, hostile bot detection), explicitly note this - do not silently substitute a snippet.

## Calibrated uncertainty in the output

The reader needs to know which parts of the output are bedrock and which parts are tentative. Use these markers consistently:

| Marker | Means |
|---|---|
| Plain assertion with citation | Triangulated; multiple independent sources |
| "Per [source], …" | Single-sourced from a tier-1 or tier-2 source |
| "According to [source], … - I could not independently confirm this." | Single-sourced from a lower tier |
| "The available sources disagree: [X] says …, while [Y] says …" | Conflict reported honestly |
| "I could not find authoritative information on …" | Explicit unknown |

Avoid:

- "It is well known that…" - citationless assertion
- "Studies have shown…" - unspecified studies
- "Most experts agree…" - unspecified experts
- "It is widely believed that…" - vague consensus claim

These are **evasions**. They make the output look authoritative while hiding the absence of evidence.

## When to stop

Stop investigating when:

1. Every claim that will appear as fact in the output is triangulated, OR
2. Every non-triangulated claim has an explicit uncertainty marker, AND
3. The remaining unknowns are either named in the output or genuinely irrelevant to the question.

Do not stop because:

- The first source seemed convincing.
- The training-data answer "looks right".
- It feels like enough.
- The user is waiting.

The user is better served by a smaller answer with sound foundations than a larger answer with fictional citations.
