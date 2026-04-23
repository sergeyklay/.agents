# Investigation Checklist

Copy this checklist into the reasoning trace when starting a tier-2 or tier-3 investigation. Tick items off as you go. The checklist exists because investigators skip steps when they get excited about a finding - it is the structural defence against that.

## Phase 1 - Scope

- [ ] Question restated precisely in my own words
- [ ] Tier classified (1 / 2 / 3) - see `references/effort-scaling.md`
- [ ] Factual claims that must be confirmed listed explicitly
- [ ] For each claim, the source types that would count as evidence named
- [ ] Decomposition into sub-questions written down (tier 3 only)

## Phase 2 - Tool inventory

- [ ] Available web search and fetch confirmed
- [ ] `context7` MCP server availability checked (for library docs)
- [ ] GitHub access confirmed (MCP server, `github_repo` tool, or web fetch)
- [ ] Local filesystem source code checked (when working in a workspace)
- [ ] Database / specialised MCP server availability checked
- [ ] Tool selection matches source-type needs

## Phase 3 - Evidence gathering

- [ ] Started with **short, broad** queries to map the landscape
- [ ] Did not default to long, hyper-specific queries
- [ ] Independent sub-questions issued **in parallel**, not serial
- [ ] Full content of authoritative sources read (not just snippets)
- [ ] Search vocabulary varied across rounds (not anchored on first source)

## Phase 4 - Triangulation

For each claim that will appear as fact in the output:

- [ ] At least two **independent** sources support it
- [ ] Independence verified (not the same upstream, not the same author)
- [ ] If conflict: classified (terminology / version / scope / genuine / one-is-wrong) and resolution decided
- [ ] If single-sourced: marked as such, OR additional source found, OR claim dropped

## Phase 5 - Bias defence

- [ ] No citations to URLs that were not actually fetched in this session
- [ ] No content-farm domains cited as primary sources
- [ ] No claims propagated from training data without verification
- [ ] Confidence calibration walked: every unverified claim has an explicit uncertainty marker
- [ ] First-source anchoring checked: at least one source from a different vocabulary domain was consulted

## Phase 6 - Synthesis

- [ ] Output uses the `explaining-technical-concepts` skill for writing
- [ ] Every implementation claim has an inline citation
- [ ] What could not be confirmed is named explicitly in the output
- [ ] Conflicts between sources are reported, not silently resolved
- [ ] Stop condition genuinely met (not "I got tired", not "the user is waiting")

## Common skipped steps

These are the items that get skipped most often in practice. Pay them extra attention:

- **Phase 1, decomposition.** Tier-3 questions that are not decomposed produce sprawling, anchor-biased answers. The decomposition is the most important step.
- **Phase 3, parallelism.** Sequential searches when parallel was possible is the single biggest waste of effort in tier-2 investigations.
- **Phase 4, independence verification.** Two sources that paraphrase each other count as one source. The independence check is non-trivial.
- **Phase 5, hallucinated citations.** Re-fetch citations before pasting them. LLMs generate plausible-looking URLs that do not exist.
- **Phase 6, named unknowns.** "I could not find X" is a *result*, not a failure. State it.
