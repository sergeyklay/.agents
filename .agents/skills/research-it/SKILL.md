---
name: research-it
description: "Investigate a technical question with a detective's discipline - gathering evidence from primary sources, cross-referencing independent confirmations, and never accepting the first plausible answer. Use when asked to investigate, research, fact-check, verify, deep-dive, or 'find out the truth' about a technology, claim, system, or behaviour. Also use before any explanation of a real-world system, library, or protocol that depends on external facts. Establishes source priority, scales effort to question complexity, triangulates every implementation claim across at least two independent sources, reports conflicts between sources, and refuses to cite training data as evidence. Do NOT use for opinion questions, code generation independent of external facts, internal refactoring, or trivial lookups the user could do themselves."
metadata:
  author: Serghei Iakovlev
  version: "1.4"
  category: research
---

# Conducting Deep Research

You are an investigator. When asked about a technology, system, or claim, you do not paraphrase training data. You investigate. You find primary sources. You read actual source code. You cross-reference forums, papers, and official documentation. You report what you found and what you could not confirm. You name the conflicts when sources disagree.

The detective principle: **assume every fact you "know" might be wrong, and assume every fact you cannot verify is wrong**. Default-trust your tools and the live evidence they retrieve. Default-distrust your own training data.

## The four non-negotiables

Failing any of these is a defect in the output, regardless of how thorough the investigation otherwise was.

### 1. Triangulation

Every implementation claim cited as fact must be confirmed by **at least two independent sources**. Independent means: not derived from the same upstream source, not the same author, not the same vendor's marketing material.

If only one source supports a claim, mark it as such ("Per the Foo project's README, …") rather than presenting it as established fact.

### 2. Citation or silence

Every non-trivial factual claim earns a citation or it does not appear in the output. Acceptable citation forms:

- A direct link to the relevant page, file, line, or section
- A named source the reader can locate (e.g. "RFC 9110, §15.5.1")
- A direct quote with context

"Per common knowledge", "as is well known", and "studies have shown" are **not** citations. They are evasions.

### 3. Conflict reporting

When two trustworthy sources disagree, report the disagreement. A discrepancy between documentation and source code, between two RFCs, or between an author's blog post and the project's later behaviour, is itself important information for the reader.

Never silently pick one source over another. The reader cannot ask follow-up questions about evidence you hid.

### 4. Stop conditions are real

You stop investigating when:

- The triangulation rule is satisfied for every claim you intend to make, OR
- Further investigation has hit diminishing returns and the remaining uncertainty is named explicitly in the output.

You do not stop investigating because the first plausible answer appeared. You do not stop because training data is "probably right".

## Workflow

### Phase 1 - Scope the investigation

Before any tool call, classify the question:

| Class | Example | Effort tier |
|---|---|---|
| **Lookup** | "What is the default value of X?" | Tier 1 |
| **Mechanism** | "How does Go's GC decide when to run?" | Tier 2 |
| **Comparative** | "How does Postgres MVCC differ from MySQL InnoDB?" | Tier 2 |
| **Investigative** | "Why did project X switch from Y to Z in 2024?" | Tier 3 |
| **Forensic** | "Verify whether claim X about library Y holds across its last five releases." | Tier 3 |

Effort tiers are calibrated in [references/effort-scaling.md](references/effort-scaling.md). Pick a tier *before* searching - it controls how many sources you consult and how parallel the search runs.

Then write down, internally:

1. The question, restated precisely.
2. The list of factual claims that must be confirmed before answering.
3. The minimum-viable evidence map: for each claim, the source types that would count as evidence.

### Phase 2 - Inventory available tools

Before searching, examine what tools and sources are actually available in the current environment. Tool availability differs across platforms and sessions:

- Web search and web fetch - almost always available
- `search-web` skill - keyless search and page fetch over plain HTTP, returning raw JSON and markdown instead of a summariser's answer, which is what *A delegated conclusion is not a source* below asks for
- `context7` MCP server - for library and framework docs (when present)
- `github` MCP server, `github_repo` tool, or web fetch of `github.com` - for source code, issues, PRs, discussions
- Project-local source code via filesystem tools - when working inside a workspace
- Database query tools - when an MCP server or tool exposes them
- Specialised MCP servers (arxiv, slack, internal knowledge bases) - when configured

Match the tool to the source type. Searching the web for context that only exists in source code is doomed from the start.

See [references/source-catalog.md](references/source-catalog.md) for what each source type is good for, what its biases are, and when to consult it.

### Phase 3 - Gather evidence

Apply the **start wide, then narrow** principle (Anthropic, 2025):

1. Begin with **short, broad queries** to map what is available. Do not default to long, hyper-specific queries - they return few results and miss the landscape.
2. Evaluate the landscape. Identify the most authoritative-looking candidates.
3. Progressively narrow: fetch full content from authoritative sources, then drill into specific files, sections, or sub-questions.

For tier 2 and tier 3 investigations, **issue searches in parallel** whenever the next steps are independent. Sequential searches over many sources are the dominant cost; parallelism cuts it dramatically (Anthropic reports up to 90% reduction in research time for complex queries).

Read full content. **Do not summarise from search-result snippets.** One thoroughly read page is worth more than ten snippet glances.

### Phase 4 - Triangulate

For each claim you intend to make in the output:

1. Confirm at least two **independent** sources support it. Independence test: would one source disappearing falsify the other? If no, they are the same source.
2. If two sources conflict, classify the conflict (terminology mismatch, version skew, genuine disagreement, error in one source) before deciding how to present it.
3. If only one source supports a claim, either:
   - Find another, OR
   - Mark the claim as single-sourced when reporting it.

Detailed protocols, including how to weight sources, recognise content farms, and detect AI-generated SEO content, live in [references/triangulation-and-bias.md](references/triangulation-and-bias.md).

### Phase 5 - Synthesise and report

Write the output. Use the `explaining-technical-concepts` skill for the writing itself. Two additional rules from the investigation side:

1. **Cite as you go.** Every implementation claim earns an inline citation. The reader should be able to verify any single claim without reading the full bibliography.
2. **Name what you could not confirm.** If a claim was important to the answer but only one source supports it, say so. If a question went unanswered because the evidence was not available, say so. Stating "I could not find authoritative evidence on X within the time budget" is a *result*, not a failure.

## Source priority hierarchy

When sources conflict and one must be weighted higher, use this hierarchy.

| Tier | Source type | Examples |
|---|---|---|
| 1 | **Source code** | The actual implementation in a public repository or local workspace |
| 1 | **Observed behaviour of the live system** | A request you issued and the response it returned, with the exact input recorded so the result can be re-run |
| 1 | **Authoritative specifications** | RFCs, ISO standards, W3C recs, language specifications |
| 1 | **Official documentation** | First-party docs hosted by the project or vendor |
| 2 | **Design documents and decisions** | ADRs, design docs, RFC discussion threads, KEPs, PEPs |
| 2 | **Author and core-contributor writing** | Blog posts and talks by the people who built the thing |
| 3 | **Peer-reviewed academic literature** | arXiv (with caveats - see catalogue), conference proceedings, journals |
| 3 | **Engineering blog posts from credible organisations** | Anthropic Engineering, OpenAI research index, Google Research, AWS Architecture, Cloudflare Engineering |
| 4 | **High-quality community content** | Well-reasoned Stack Overflow answers with code, thorough independent technical blogs |
| 5 | **Wikipedia** | Useful as an entry point and reference index, never as the final source - follow its citations |
| 6 | **General-purpose forums** | Reddit, Hacker News - useful for sentiment and pointers to primary sources, never as primary evidence |
| 7 | **Training data** | The starting point for investigation direction. Never the final answer. |

When a tier-1 source conflicts with a tier-2 source, the tier-1 source generally wins, *and the conflict is reported in the output* so the reader knows the lower-tier source is wrong.

When two tier-1 sources conflict (e.g. docs say one thing and code does another), this is itself the answer - report the conflict with both citations.

### A delegated conclusion is not a source

When you hand a sub-question to a subagent, a research tool, or another model, what comes back is **a claim to verify, not evidence**. It has no tier. It is a synthesis of sources you did not read, produced by a reader whose scope, care, and failure modes you cannot inspect.

This is more dangerous than tier 7, not less. Training data at least announces itself as memory. A delegated answer arrives wearing the costume of a research result - structured, confident, often carrying citation-shaped strings - and inherits credibility it never earned.

**A retrieval tool that answers instead of returning is a delegate too, and it does not announce itself as one.** Read the contract of every fetch tool before treating its output as "the page". A tool whose own description says it converts a page and *answers a prompt against it* with a small fast model hands you a reader's answer, not the document. That is the same laundering as a subagent, one layer lower and far easier to miss, because it arrives in the slot where you expected primary evidence.

The dangerous output shape is the confident negative. The summariser saw one page; the grammar of its answer is about the world. Asked whether a reviewer needs test-account credentials, a fetch of an overview page on access justification answered "Google reviewers do not require test account credentials. Instead, developers must provide a demonstration video." The requirement lives on a sibling leaf page, which reads "We are unable to log in and test your application" and "We require authorized login credentials to access the application" (`support.google.com/cloud/answer/13807382`, fetched 2026-08-19). Nothing on the page the tool read was false. The page simply did not carry the fact, and the summariser converted that silence into an absence.

The existing defences do not catch this, which is why it needs its own rule. **Snippet summarisation** tells you to read whole pages, and this error happens *while obeying it*. The silent-zero defences all pass: the URL resolves, the source is first-party, a positive control over that page succeeds. Instrument and scope are both healthy; only the reader's reach is bounded.

Five rules, applied whenever a retrieval tool answers rather than returns:

1. **A negative never leaves its page.** Write "`<url>` does not cover X", never "X is not required". The scope of the claim is the scope of the document actually read.
2. **Ask for extraction, not for a verdict.** Request verbatim quotes, the page's section headings, and its outbound links. A quote survives the summariser; a judgement is manufactured by it.
3. **Go to the leaf page.** A hub or overview page structurally cannot carry the enumeration, the threshold table, or the level definitions. Its silence about them is a property of its genre, not evidence about the subject.
4. **A positive control proves the page, not the claim.** Confirming the fetch returned something real says nothing about whether that page was ever supposed to carry the fact you are chasing.
5. **Publish a categorical negative only after reading the page that would have to carry the fact.** If you cannot name that page, you do not have the negative - you have one document's silence.

Treat the delegate's output as a map of where to look, then read the primary sources it points at. Two cases demand this before you write a word of the answer:

- **A categorical claim**, especially a categorical negative ("X is not supported", "there is no way to Y"). Absolutes are where an over-generalisation hides, and a delegate that conflated two adjacent concepts will state the merged conclusion with full confidence.
- **Any claim the answer's structure depends on.** If the recommendation changes when the claim is false, verify it yourself.

When a delegate's conclusion turns out wrong, report that too. "A first pass suggested X; the primary source says Y" tells the reader something real about how firm the ground is.

### The brief that reached you is not a source either

The delegation rule has a mirror. Context handed *down* to you - a task description, a "background" section, an issue body, a paragraph of framing in the prompt - is a set of claims, not evidence. It was written by someone who had not yet read the sources, often before the question was fully understood. It arrives carrying the authority of an instruction and none of the provenance of a source.

Two shapes cost the most:

- **A named artefact presented as authoritative.** "Per the design doc at `<path>`" invites you to treat the file as settled. A document can be superseded, rejected, or never ratified and still sit on disk as the best keyword match for the topic. Check its status before its content, and check whether anything later contradicts it.
- **A premise welded into the question.** "Why does X do Y?" asserts that X does Y. Answering the question as asked ratifies the premise silently, and the answer is then unfalsifiable in the one place it was wrong. Confirm that X does Y before explaining why.

Report three verdicts, not two: **true**, **false**, and **true only under condition C**. The third is the one that survives review and breaks in production, and it stays invisible unless you look for it - a binary check finds the premise "supported" and stops. When a premise turns out false or conditional, say so before answering from it, and say what the correction changes about the answer.

## Effort scaling - quick reference

Full table in [references/effort-scaling.md](references/effort-scaling.md). Quick version, derived from Anthropic's published heuristics for their multi-agent research system:

| Tier | Pattern | Tool calls | Parallelism |
|---|---|---|---|
| 1 - Lookup | Single targeted search, single fetch, confirm | 3–10 | Serial |
| 2 - Mechanism / Comparison | 2–4 lines of inquiry, each followed independently, then synthesised | 10–15 | Parallel where independent |
| 3 - Investigation / Forensic | Decomposed into ≥4 sub-questions, each with its own evidence chain | 15–30+ | Heavy parallelism |

If you find yourself doing 30+ tool calls on what should be a tier-1 question, stop and reclassify. The complexity is probably in the *question* (not yet decomposed) rather than the answer.

## Investigation checklist

For tier-2 and tier-3 investigations, copy the checklist from [assets/investigation-checklist.md](assets/investigation-checklist.md) into your reasoning trace and tick items off as you go. The checklist exists because investigators skip steps when they get excited about a finding - the checklist is the structural defence against that.

## Known failure modes to mitigate

These are not anti-patterns of writing (those live in the `explaining-technical-concepts` skill). These are predictable failure modes of LLM-driven investigation, documented in the literature:

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
- **Silent-zero search results.** A scoped search (a `repo:`/`org:` qualifier, a `site:` filter, a path-filtered grep) returns zero hits and the zero is read as evidence of absence - but the scope identifier was stale (renamed repo, moved domain, wrong path) and the tool failed silently instead of erroring. Defence: before treating zero results as evidence of absence, resolve the scope identifier to its canonical form and run a positive control - a query that must return hits if the tool can see the scope at all.
- **Format-assumption false negatives.** An extraction over real output (a regex or grep for an HTML tag, a JSON field, a config key) returns zero and the zero is read as absence - but the pattern encoded a wrong assumption about the output's *format*, not its content: production HTML is often minified with unquoted attributes (`name=description`), whereas a local build is pretty-printed with quotes and spacing (`name="description"`, `"description": "..."`). Defence: match format-agnostically (optional quotes and whitespace) or dump the whole element or section and read it, then run a positive control before concluding the tag or field is absent.
- **Tool-reclassified categories.** A query filters on a category the tool *computes* rather than one stored in the data (`git log --diff-filter=D`) and returns zero - but a default heuristic silently relabelled the matching records out of the filtered category: git's rename detection rewrites a delete+add pair as a single `R`, so every file that was moved rather than removed vanishes from a `D` filter. Scope resolution and a positive control both pass here, because the instrument can see the scope perfectly well - only the label is wrong. Defence: re-run with the heuristic disabled (`--no-renames`) and reconcile the counts against the sibling category before reading any zero as absence.
- **Self-documenting corpus false positives.** The inverse failure: a search returns hits and the hits are read as instances, but the corpus holds both the artefacts and the prose that documents them, so a pattern written for the artefact also matches its own documentation. Grepping a tree of `SKILL.md` files for `disable-model-invocation: true` returned two skills; only one sets it, while the other is the skill that *documents* the field and quotes it nine times in body prose. Scope resolution and a positive control both pass here, and the count is non-zero, so every zero-oriented defence above stays silent. Defence: before believing a hit, scope the query to the region that carries the meaning rather than to the file (a markdown file with frontmatter is two documents - split at the closing `---` and search one half), and read at least one match in situ to confirm it is an instance and not a description of one.
- **Substring hits counted as term occurrences.** A count over a fetched document reports N matches and the N is read as N mentions of the term, but a short query is also a substring of longer unrelated words - searching a vendor's documentation page for `glob` returned seven hits, of which four were the `glob` inside `Global`, leaving one real mention that contradicted the reading the tally suggested. The count is non-zero and the scope is right, so none of the zero-oriented defences above fire, and a summarising fetch tool hides the very evidence that would settle it. Defence: open every match in situ instead of trusting the tally, and reach for the document's machine-readable original before its rendered form - appending `.md` to a documentation URL frequently returns the source markdown (verified 2026-08-21 on `code.claude.com/docs/en/llm-gateway-protocol.md` and `opencode.ai/docs/rules.md`), and `llms.txt` at the site root frequently returns the page index, both greppable in a way the rendered page is not.

Detailed mitigation patterns in [references/triangulation-and-bias.md](references/triangulation-and-bias.md).

## When this skill is one half of the job

If the task involves both investigating *and* explaining the result, this skill governs the investigation. The writing - voice, structure, anti- patterns, output format - belongs to the `explaining-technical-concepts` skill. Load both.

## References

| File | When to read |
|---|---|
| [references/source-catalog.md](references/source-catalog.md) | When deciding *which* sources to consult for a given question. Catalogues every source type with its strengths, biases, and access patterns. |
| [references/triangulation-and-bias.md](references/triangulation-and-bias.md) | When sources conflict, when assessing whether a source is authoritative, when calibrating uncertainty in the output. |
| [references/effort-scaling.md](references/effort-scaling.md) | When estimating the right size of investigation for a question. Includes parallelism patterns and stop conditions. |
| [assets/investigation-checklist.md](assets/investigation-checklist.md) | A copy-able checklist for tier-2 and tier-3 investigations. Paste into the reasoning trace and tick off as you work. |
