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

### Failure-mode catalog

One line each: the symptom, then the mitigation. The subsections that follow expand the modes that recur most.

- **Hallucination of citations.** Plausible-looking links and titles that do not exist. Defence: only cite URLs you actually fetched in this session, files you actually read.
- **Confidence miscalibration.** LLMs systematically overstate certainty about facts they have not verified (OpenAI, Deep Research limitations, Feb 2025). Defence: explicit uncertainty markers on every unverified or single-sourced claim.
- **SEO content-farm preference.** Search engines surface SEO-optimised content over authoritative-but-less-ranked sources like academic PDFs or personal blogs (Anthropic, 2025). Defence: actively prefer the source hierarchy above over Google ranking.
- **Anchoring on the first plausible source.** The first source found shapes the search vocabulary for everything afterwards. Defence: always consult at least one source from a different tier or vocabulary domain.
- **Laundering a delegated conclusion into a fact.** A subagent or research tool returns a confident, well-formatted verdict, and it enters the answer as though it were sourced - often because it *looks* more like a research result than a raw page does. The delegate's own conflations and scope errors travel with it, invisibly. Defence: treat every delegated conclusion as an unverified claim, and check categorical statements and load-bearing claims against the primary source yourself before citing them.
- **Snippet summarisation.** Building an answer from search-result snippets rather than full content. Defence: fetch and read full content before citing.
- **Summariser-bounded negatives.** A retrieval tool that answers a prompt against a page rather than returning the page reports "X is not required" when the page it read merely did not mention X. The reader's scope was one document; the grammar of its answer is the world. Every silent-zero defence passes - the URL resolves, the source is first-party, a positive control over that page returns content - because instrument and scope are both fine and only the reader's reach is bounded, so this needs its own check. Defence: ask for verbatim quotes, section headings and outbound links instead of a verdict; keep the negative attached to its URL ("`<url>` does not cover X"); go to the leaf page, since a hub cannot carry an enumeration; and treat a categorical negative as unpublishable until you have read the page that would have to carry the fact.
- **Inherited premises treated as given.** The task's own framing - a background paragraph, an issue body, a named artefact - enters the investigation as settled fact because it arrived as an instruction rather than as a source. A premise welded into the question ("why does X do Y?") is ratified by any answer that addresses it, and a cited document can be superseded and still be the best match on disk. Defence: verify the premise before answering from it, check an artefact's status before its content, and report the conditional verdict ("true only when C") rather than collapsing it to true or false.
- **Rendered-page omissions.** A vendor's documentation page loads in full and simply lacks the field, enum value or list the product has - no error, no truncation marker. Unlike a silent zero the instrument is healthy and the scope is right, so reading the page harder cannot recover what it never carried. Defence: the rendered page is the last source, not the first. Work down the machine-readable originals - the published OpenAPI description (curl to disk and grep locally; a condensing fetch tool drops what you came for), the GraphQL schema by introspection or published SDL, then the docs repository's raw markdown, searching the fragments a page includes and not just the page file, since enumerated lists usually live in a fragment. Prove each rung before trusting its zero: grep the artifact for something you know it contains.
- **Spec-omitted enforcement.** A machine-readable original - an OpenAPI description, a JSON Schema, a published SDL - is read as the contract, but the server enforces constraints it never declares: a numeric bound, an enum, a required pairing, a rejection of unknown fields. The same gap runs the other way, where a parameter the vendor's prose calls unavailable is in fact honoured. Every defence above passes, because the artifact is authentic, the scope is right, and a positive control over it succeeds - the document is simply not the thing that decides. Defence: before writing a parameter, range, default or error code into anything that outlives the session, elicit it. Send one variable per request rather than a combined body, bisect a rejected body down to the offending field, read the server's error text as the real constraint since the validator emits it, pin each bound from both sides (`lo`, `lo-1`, `hi`, `hi+1`), and send a deliberately bogus field to learn whether the validator is strict or lenient. Then execute every code example verbatim after the last edit - fragments that each ran do not prove the assembled block runs.
- **Decode-folded configuration keys.** A declared key appears unused at its consumer and is called dead - but a decode or normalize step upstream folded it into a different field. The key is live and another field decides. The grep is right about the file and wrong about the layer. In `anomalyco/opencode` at `v1.18.27` (fetched 2026-09-05), `normalize()` in `packages/core/src/v1/config/agent.ts` folds the deprecated `agent.tools` into `permission` at decode time, and the consumer reads only `value.permission`. Defence: read the decode and normalize path, not just the consumer, before calling a key unused, and confirm against the tool's own resolved-config output.
- **Stale path in an otherwise correct secondary source.** A blog post, an issue comment or an earlier note of your own cites `<repo>/<path>` for a claim, and the claim is true while the path is not: the file was renamed, split or moved between the version that source described and the version you run. Every defence for a silent zero passes - the source is credible, the scope resolves, the content claim is sound - and the failing grep reads as a refutation of the claim when it refutes only the citation. `ollama/ollama` hardcodes `"cache_prompt": true` in `llm/server.go` at `v0.3.0` and `v0.6.0`, and in `llm/llama_server.go` at `v0.32.15` and on `main` (all four fetched 2026-08-25); a grep of `llm/server.go` at `v0.32.15` finds nothing and proves nothing. Compounding it, GitHub's `search/code` API indexes the **default branch only**, so its one-path answer describes `main` today and is silent about every tag and every earlier state - a zero from it is not evidence about a release you did not query. Defence: pin the tag you actually run and fetch from `raw.githubusercontent.com/<owner>/<repo>/<tag>/<path>` with a positive control before believing a zero; when the path fails, hunt the **symbol** across tags rather than re-reading the path; and report the correction, because a secondary source that was right about the code and wrong about its address is still going to be cited by the next reader.
- **Silent-zero search results.** A scoped search (a `repo:`/`org:` qualifier, a `site:` filter, a path-filtered grep) returns zero hits and the zero is read as evidence of absence - but the scope identifier was stale (renamed repo, moved domain, wrong path) and the tool failed silently instead of erroring. Defence: before treating zero results as evidence of absence, resolve the scope identifier to its canonical form and run a positive control - a query that must return hits if the tool can see the scope at all. When the positive control itself returns zero, do not soften the claim into a hedge: the scope can be real and still be invisible to that index, as a repository created days ago is to a code-search index that has not yet reached it, and a control which cannot see the scope proves nothing about the scope's contents. Switch instrument instead. Fetch the tree or the release tarball at the tag, grep the local copy, and re-run the same control against it, so the control is answered by an instrument that demonstrably can see what you are asking about.
- **Format-assumption false negatives.** An extraction over real output (a regex or grep for an HTML tag, a JSON field, a config key) returns zero and the zero is read as absence - but the pattern encoded a wrong assumption about the output's *format*, not its content: production HTML is often minified with unquoted attributes (`name=description`), whereas a local build is pretty-printed with quotes and spacing (`name="description"`, `"description": "..."`). Defence: match format-agnostically (optional quotes and whitespace) or dump the whole element or section and read it, then run a positive control before concluding the tag or field is absent.
- **Tool-reclassified categories.** A query filters on a category the tool *computes* rather than one stored in the data (`git log --diff-filter=D`) and returns zero - but a default heuristic silently relabelled the matching records out of the filtered category: git's rename detection rewrites a delete+add pair as a single `R`, so every file that was moved rather than removed vanishes from a `D` filter. Scope resolution and a positive control both pass here, because the instrument can see the scope perfectly well - only the label is wrong. Defence: re-run with the heuristic disabled (`--no-renames`) and reconcile the counts against the sibling category before reading any zero as absence.
- **Self-documenting corpus false positives.** The inverse failure: a search returns hits and the hits are read as instances, but the corpus holds both the artefacts and the prose that documents them, so a pattern written for the artefact also matches its own documentation. Grepping a tree of `SKILL.md` files for `disable-model-invocation: true` returned two skills; only one sets it, while the other is the skill that *documents* the field and quotes it nine times in body prose. Scope resolution and a positive control both pass here, and the count is non-zero, so every zero-oriented defence above stays silent. Defence: before believing a hit, scope the query to the region that carries the meaning rather than to the file (a markdown file with frontmatter is two documents - split at the closing `---` and search one half), and read at least one match in situ to confirm it is an instance and not a description of one.
- **Substring hits counted as term occurrences.** A count over a fetched document reports N matches and the N is read as N mentions of the term, but a short query is also a substring of longer unrelated words - searching a vendor's documentation page for `glob` returned seven hits, of which four were the `glob` inside `Global`, leaving one real mention that contradicted the reading the tally suggested. The count is non-zero and the scope is right, so none of the zero-oriented defences above fire, and a summarising fetch tool hides the very evidence that would settle it. Defence: open every match in situ instead of trusting the tally, and reach for the document's machine-readable original before its rendered form - appending `.md` to a documentation URL frequently returns the source markdown (verified 2026-08-21 on `code.claude.com/docs/en/llm-gateway-protocol.md` and `opencode.ai/docs/rules.md`), and `llms.txt` at the site root frequently returns the page index, both greppable in a way the rendered page is not. Do not read a zero off `llms.txt` itself: it indexes whatever granularity the vendor chose, and some sites list documentation *sets* rather than pages, so a term that appears on forty pages can be absent from it. `docs.warp.dev/llms.txt` (fetched 2026-09-06) is 31 lines under a `## Documentation Sets` heading and contains zero occurrences of both `skill` and `MCP` - the positive control fails, so the zero is uninformative - while `docs.warp.dev/llms-full.txt` is 3.3 MB with 42 occurrences of `SKILL.md` and 640 of `MCP`. Escalate to `llms-full.txt`, or to the per-set file the index names, before concluding anything from the short one.
- **Source-vocabulary false negatives.** A search for a claim is written in the words of the source that *reported* it - a ticket's quoted phrasing, a bug report's wording, a reviewer's sentence - and the hits are read as the complete set, but the corpus states the same claim in other words. A screen accused of advertising a capability the product lacks was grepped for the two phrases its ticket quoted; that returned one site, which was reported as the only one, while a second sentence on the same screen made the same promise with a different noun and a softer verb and matched neither pattern. The count is non-zero and every zero-oriented defence above passes - the scope resolves, the format is right, a positive control over the known site succeeds - because instrument and corpus are both healthy and only the vocabulary is borrowed. It also defeats any acceptance gate written from that same quotation: the gate goes green having never been capable of seeing the second site, so it was incapable of failing rather than genuinely passing. Defence: derive the pattern from the claim's *semantic class* rather than from its quotation, varying the object, the verb, and the hedge independently rather than as one phrase; then read the whole surface the claim could live on once by eye before believing any count of its occurrences.
- **Truncated output read as complete.** A command's output is cut by the pipeline rather than by the data - `| head` drops everything past the tenth line, a large JSON blob hits the tool's inline output cap mid-object, a fetch tool elides the middle - and the visible fragment is read as the whole result. This is worse than a silent zero because the output is non-empty and well-formed at the point it stops, so it reads as an answer rather than as a stump: a truncated JSON document surfaces as a *parse error*, which invites debugging the producer instead of the transport. Defence: never terminate an exploratory pipeline in `head`, `tail` or a bare `grep` when the question is "does X exist anywhere" - write the full output to a file, report its byte size and record count, and read the file. Get counts from the producer (`wc -l`, a `count` mode, a `--json` field) rather than from the rows that fit on screen, and treat any parse error over machine-generated output as a truncation hypothesis first.
- **Paginated index read as the whole archive.** A list page - a changelog, a release index, a blog archive - is fetched whole and read as the corpus it indexes, but it is one window onto that corpus: the older entries sit behind a pagination control the fetch never followed. This is the sibling of truncation and its inverse - nothing on this side cut the output, and the server faithfully returned a page that was always partial. Every defence above passes: the URL resolves, the source is first-party, the format assumption is right, and a positive control returns hundreds of hits. A zero here reads as "the vendor never announced it" when it means "not in the most recent N entries". `cursor.com/changelog` (fetched 2026-09-06) serves only the newest entries; the January 2026 entry announcing native `SKILL.md` support sat on `/changelog/page/7`, reachable only after the pagination scheme was recovered by grepping permalinks out of the first page's own markup - and without it the honest-looking conclusion was that the product did not support the format at all. Defence: establish the archive's extent before reading any zero off an index. Find the oldest entry the fetched page carries and compare it against the date range the question needs; if the page stops short, recover the pagination scheme from its markup (`rel="next"`, a `?page=` or `/page/N` permalink) and sweep until the range is covered, or switch to the un-windowed original the site already publishes - a feed, a sitemap, or the release notes in the documentation repository.

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

### Summariser-bounded negatives

**Symptom.** A retrieval tool returns a clean, confident negative - "X is not required", "the API has no Y" - and it enters the answer as a fact about the subject. But the tool did not return the page; it *answered a prompt against* the page with a small model. The reader's evidence was one document. The grammar of its answer was the world.

This is not the snippet trap. It happens **while obeying** the rule against snippets: a full page was fetched and read end to end. It is also invisible to the silent-zero defences - the URL resolves, the source is first-party, and a positive control over that page returns real content. Instrument and scope are both healthy. What is bounded is the reach of a reader you cannot inspect, and the tool has no way to say "this page does not discuss that" instead of "that is not so".

Observed instance: a fetch of a vendor's overview page on access justification answered that reviewers "do not require test account credentials" and want a demonstration video instead. The sibling leaf page on in-app testing says "We are unable to log in and test your application" and "We require authorized login credentials to access the application". The overview page contained nothing false. It simply never addressed the question, and the summariser reported that silence as an answer.

Hub pages make this systematically worse. An index, an overview, or a landing page structurally cannot carry an enumeration, a threshold table, or a set of level definitions - those live on leaves. Asking a hub a leaf question guarantees a bounded reader, and the tool will still answer.

**Defence.**

1. **Read the tool's contract before trusting its output as a document.** If the description says it converts a page and answers a prompt against it with a small or fast model, it is a delegate. Treat its output as a claim to verify, exactly as with a subagent.
2. **Ask for extraction, not adjudication.** Request verbatim quotes matching the terms in question, the page's section headings in order, and its outbound links. Quotes survive the summariser; verdicts are manufactured by it. The headings and links also tell you which leaf to fetch next.
3. **Bound the negative to its URL in your own notes and in the output.** Write "`<url>` does not cover X as of `<date>`", never "X is not required". A negative that has left its page cannot be audited by the reader and cannot be corrected by the next fetch.
4. **Chase the negative to the page that would have to carry the fact.** Name that page before publishing any categorical negative. If you cannot name it, you do not have a negative - you have one document's silence, which is a different and much weaker thing.
5. **Do not let a positive control launder the claim.** A control proves the fetch reached a live page with real content. It says nothing about whether that page was ever the right one. The control to run here is the leaf-page fetch in step 4, not a re-query of the same URL.

### Silent-zero search results

**Symptom.** A scoped search returns zero results, and the zero is cited as evidence of absence ("the project has no X anywhere in its codebase"). But the scope identifier was stale, and the tool reported the dead scope as an empty result rather than an error. GitHub code search is the canonical trap: for a repository that has been renamed or transferred, `search/code?q=repo:old-owner/name+term` returns `total_count: 0` with no error and no redirect notice - while `GET /repos/old-owner/name` follows the rename silently, so a spot-check against the repo appears to confirm the search scope was alive. Re-running the search with different terms returns more zeros, which feels like triangulation but is the same broken instrument consulted twice: instrument-level failures are perfectly correlated across queries.

**Defence.** A zero from one instrument is never evidence of absence on its own. Before citing it:

1. **Resolve the scope identifier to its canonical form** via a path that follows renames, and compare it against the identifier searched. For GitHub: `gh api repos/<owner>/<name> --jq .full_name`. If the canonical name differs, the search scope was dead - re-run against the canonical name.
   For a documentation host, resolve the *whole* redirect chain and print where it landed: `curl -sSL -o /dev/null -w '%{url_effective}\n' <url>`. Check a single hop and a rebrand hides from you, because the first redirect is often intra-domain and innocuous while the cross-domain move sits further down: `docs.windsurf.com/...` hops within its own domain before landing on `docs.devin.ai` (Windsurf's docs are now served from Cognition's), and `kilocode.ai/docs/features/skills` lands on `kilo.ai/docs/customize/skills` - both the domain and the path changed (both fetched 2026-09-06). A page that still returns `200` at the old address is not evidence the old address is canonical, and citing it dates the work.
2. **Run a positive control.** Query the same scope for a term that must exist (the project's own name, `README`, a known top-level symbol). Zero hits on the control means the instrument cannot see the scope, and every zero it produced is void.
3. **Classify surviving hits before re-asserting absence.** When the corrected search does return hits, read each one (implementation vs. CI config, changelog, code comment) before deciding whether the absence claim still holds.
4. **Scope the claim in the output.** Report "no hits for *terms* in *canonical scope* as of *date*", never an unqualified "the project has no X". Absence claims inherit every blind spot of the search tool, such as indexing lag, file-size limits, and default-branch-only indexing.

### Tool-reclassified categories

**Symptom.** A query filters on a category the tool *computes* rather than one stored in the data, and returns zero. The scope is live and the pattern is correct; a default heuristic simply relabelled the matching records out of the filtered category. `git log --diff-filter=D -- <path>` is the canonical trap: rename detection is on by default and rewrites a delete+add pair in one commit as a single `R`, so every file that was moved rather than removed disappears from a `D` filter. This failure is invisible to the silent-zero defences above - the repository resolves, the pathspec matches, and a repo-wide positive control for `D` returns hits - because the instrument can see the scope perfectly well. Only the label is wrong.

**Defence.**

1. **Disable the heuristic and re-run.** Pass `--no-renames` alongside `--diff-filter`. If the count moves, the original zero was an artefact of the default rather than a fact about the history.
2. **Reconcile against the sibling category.** The relabelled records must reappear where the heuristic moved them: `D` (detection on) plus `R` should equal `D` (detection off). In one repository the three counts were 3, 133 and 136 - the zero for a path-scoped `D` filter was hiding every move.
3. **Do not accept a positive control alone here.** A control that returns hits proves the instrument can see the scope; it does not prove the filter's category means what you assume. Query the sibling filter before concluding absence - a wall of renames beside a zero for deletions is the tell.

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
