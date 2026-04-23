# Quality Attributes

## Contents

- Why this vocabulary matters
- ATAM core concepts
- The utility tree
- Scenarios - use case, growth, exploratory
- ISO/IEC 25010:2023 characteristics
- Related evaluation methods (SAAM, ARID, CBAM, QAW)
- Applying this in a review (pragmatically)
- Sources

The working vocabulary for quality attributes and the ATAM method. Load this file when the system under review has non-trivial tradeoffs, when the stated priorities are ambiguous, or when the review needs to cite a methodology by name rather than by feel.

Architecture reviews stop being opinionated the moment they ground their findings in **established methodology**. Saying "this is a risk" is weak. Saying "this is a sensitivity point for availability in the ATAM sense, with no compensating strategy" is a finding the author can engage with - because it is grounded in a vocabulary both reviewer and author can reach for.

## Why this vocabulary matters

Two observations drive the use of named methodology in reviews:

1. **Vocabulary is leverage.** Once both sides of the review agree on what a "sensitivity point" means, the argument stops being about whether the reviewer's gut is right. It becomes about whether the named structural property is present.
2. **Named risks survive the review meeting.** "I felt something was wrong with the availability here" is forgotten after lunch. "Sensitivity point identified at the order-service database write path; a minor schema change propagates to six downstream consumers" is in the ADR.

Use ATAM and ISO/IEC 25010 not as bureaucratic overhead, but as shared anchors.

## ATAM core concepts

The Architecture Tradeoff Analysis Method (ATAM) was published by Kazman, Klein, and Clements in CMU/SEI-2000-TR-004 (August 2000) and expanded in *Evaluating Software Architectures: Methods and Case Studies* (Clements/Kazman/Klein, Addison-Wesley 2001, ISBN 978-0-201-70482-2). Its four load-bearing concepts are *sensitivity point*, *tradeoff point*, *risk*, and *non-risk*.

### Sensitivity point

**Definition** (paraphrased from SEI TR-004): a property of one or more components, or of relationships between components, that is critical for achieving a particular quality-attribute response.

**What it means in practice.** A decision or configuration where a **small change produces a large effect on one quality attribute**. The buffer size in front of a disk queue is a sensitivity point for latency. The thread-pool ceiling in a request handler is a sensitivity point for availability under load. The cache TTL is a sensitivity point for consistency.

**Why it matters in a review.** Sensitivity points are where accidental change during implementation or operations causes a quality-attribute regression. Flag them so the team can put guardrails around them - benchmarks, regression tests, configuration freezes, or at minimum comments in the code that say "this value is a sensitivity point for X, see design doc Y".

### Tradeoff point

**Definition** (paraphrased): an architectural element where changing it materially affects **more than one** quality attribute in competing directions. Equivalently, a sensitivity point that is sensitive to more than one attribute, and where the attributes compete.

**What it means in practice.** Choosing a larger cache improves read latency at the cost of memory budget and potential stale reads. Choosing synchronous replication improves consistency at the cost of latency and partition availability. Choosing a wider service boundary improves internal cohesion at the cost of deployment coupling.

**Why it matters in a review.** Tradeoff points are **where the stated priorities have to be applied.** You cannot evaluate a tradeoff without knowing which quality attribute the organisation is willing to sacrifice. If the priorities are missing, you cannot evaluate tradeoff points; surface that in Open Questions before making judgements.

### Risk

**Definition** (paraphrased): an architectural decision whose consequences are **potentially problematic** given the quality-attribute goals for the system.

Every sensitivity point and every tradeoff point is a **candidate** risk - by the end of ATAM, each one is classified as either a risk or a non-risk.

**What it means in practice.** A sensitivity point becomes a risk when the mechanism that depends on it is fragile *given this team, this context, and these priorities*. A tradeoff point becomes a risk when the tradeoff is made in the direction opposite to the stated priorities.

### Non-risk

**Definition** (paraphrased): a decision whose consequences are **sound** - no apparent negative quality-attribute implications given the scenarios at hand.

**Why non-risks matter in a review.** They anchor the "Strengths" section. The review is more credible when it lists a small number of explicit non-risks than when it lists zero positives, because the reader can see the reviewer actually looked. Keep the list short; do not enumerate every good decision.

## The utility tree

The utility tree is ATAM's tool for **prioritising quality attributes** before evaluating tradeoffs. It is a hierarchy rooted at an abstract node labelled "utility", decomposed into quality-attribute categories, then into refinements, then into concrete scenarios. Each leaf scenario is annotated with a pair of priorities - usually **(business importance, architectural difficulty)** - rated H (high), M (medium), or L (low).

```
Utility
├── Performance
│   ├── Latency
│   │   └── Scenario: order confirmation returns in <200ms at p99 [H, M]
│   └── Throughput
│       └── Scenario: 10k orders/second sustained [M, H]
├── Availability
│   ├── Failover
│   │   └── Scenario: region loss tolerated with <5min RTO [H, H]
│   └── Graceful degradation
│       └── Scenario: payment-service outage does not block browsing [H, M]
├── Security
│   └── ...
└── Modifiability
    └── ...
```

**How to use a utility tree in a review.** You do not need to build a full utility tree in the review itself - that is the team's job. But you do need to be able to **walk it mentally** for the system under review. If you cannot name at least two leaf scenarios per significant quality attribute, the review has not characterised the system well enough to evaluate its tradeoffs.

A common review finding is "the utility tree is not explicit - the team has not named the concrete scenarios that would distinguish a sufficient design from an insufficient one." This is a Dimension 1 alignment finding, not a Dimension 5 gap.

## Scenarios - use case, growth, exploratory

ATAM classifies scenarios by the kind of system behaviour they probe:

- **Use-case scenarios.** Typical operational behaviour. "A user places an order; the system returns confirmation in under 200ms at p99."
- **Growth scenarios.** Anticipated evolution. "Within 12 months, order volume doubles; the architecture supports the increase without fundamental redesign."
- **Exploratory scenarios.** Extreme or hypothetical stressors. "Two regions fail simultaneously; the system maintains read-only order history for existing users."

In a review, each of the three scenario types exercises the architecture differently. A design that is strong for use-case scenarios can fail on growth (does the current throughput limit end in months or years?) or on exploratory stress (what happens when the region your database is in goes dark?). A complete review exercises at least one growth and one exploratory scenario for each stated high-priority quality attribute.

## ISO/IEC 25010:2023 characteristics

ISO/IEC 25010:2023 (published November 2023, superseding the 2011 edition) defines nine top-level quality characteristics for a software product. Each has sub-characteristics; the top level is what matters for naming findings.

| # | Characteristic | What it covers |
|---|---|---|
| 1 | **Functional suitability** | Does the system do what it is supposed to do, correctly and completely? |
| 2 | **Performance efficiency** | Time behaviour, resource utilisation, capacity under defined conditions. |
| 3 | **Compatibility** | Coexistence and interoperability with other systems and components. |
| 4 | **Interaction capability** | Learnability, accessibility, user-interface quality. *(Was "usability" pre-2023.)* |
| 5 | **Reliability** | Availability, fault tolerance, recoverability, faultlessness. |
| 6 | **Security** | Confidentiality, integrity, non-repudiation, accountability, authenticity, resistance. |
| 7 | **Maintainability** | Modularity, reusability, analysability, modifiability, testability. |
| 8 | **Flexibility** | Adaptability, installability, replaceability, scalability. *(Was "portability" pre-2023.)* |
| 9 | **Safety** | New top-level characteristic in 2023: risk identification, fail-safety, hazard warning, safe integration. |

### Changes from the 2011 edition

The renames and additions in 2023 are not cosmetic; they change what belongs at the top level:

- **Usability → Interaction capability.** "Usability" is now broader than UI; it includes inclusivity and user assistance as sub-characteristics. In a review, this means accessibility and self-descriptiveness are evaluated alongside UI quality, not separately.
- **Portability → Flexibility.** Adds scalability as a sub-characteristic. In a review, this means "can the system scale" is a Flexibility finding, not a Performance finding. Worth noting when scoping: scalability sits with Flexibility in the ISO sense even though many practitioners colloquially file it under Performance.
- **Safety added.** For systems with physical-world consequences (transportation, medical, industrial control), Safety is now a distinct top-level dimension. If the system under review has any safety surface, the review must include it.

### Using this in findings

Name the characteristic when flagging a risk. Instead of "this will be slow", say "this is a Performance efficiency risk - specifically, time behaviour under the stated 10k-orders/sec scenario". The ISO name makes the finding:

1. Searchable across the organisation's other reviews.
2. Traceable to any team policies or regulatory obligations that reference ISO 25010.
3. Harder to dismiss, because it is grounded in a recognised vocabulary.

## Related evaluation methods

ATAM is not the only scenario-based evaluation method. Knowing when each applies keeps the review from over-reaching into methodology that does not fit the artefact.

| Method | When to use | Focus |
|---|---|---|
| **SAAM** (Kazman/Bass/Abowd, 1994) | Earliest stage; comparing candidate architectures | Primarily modifiability; qualitative |
| **ARID** | Partial designs, before the architecture is finalised | Active review of intermediate designs |
| **ATAM** | Architecture is complete enough to evaluate | Quality-attribute tradeoffs; full scenario analysis |
| **CBAM** (Asundi/Kazman/Klein, SEI-2001-TR-035) | Prioritising architectural investments with cost/benefit | ROI and uncertainty over ATAM findings |
| **QAW** (Quality Attribute Workshop) | Before architecture exists | Elicits scenarios from stakeholders |

Most architecture reviews you will run are ATAM-flavoured (the architecture exists; you are evaluating its tradeoffs). If the artefact under review is a pre-architecture design document, QAW-flavoured elicitation is more appropriate than full ATAM analysis. If the review is asked to choose between two candidate architectures, SAAM's qualitative comparison is lighter-weight than ATAM.

You do not need to **run** a full ATAM. ATAM proper involves multiple stakeholder sessions, utility-tree construction workshops, and explicit risk/non-risk classification. An architecture review borrows the **vocabulary and lens** from ATAM without running the full process. That is the correct usage.

## Applying this in a review (pragmatically)

The goal is not to produce a compliant ATAM report. The goal is to produce a review that is **grounded**, and ATAM is the grounding.

### What to actually do

1. **Before writing findings**, mentally walk the utility tree. Name 2-4 leaf scenarios per priority quality attribute. If you cannot, that is the first finding (Dimension 1).
2. **For each significant decision**, identify whether it is a sensitivity point, a tradeoff point, or neither. Most decisions are neither; the ones that are, are where the review's attention goes.
3. **When flagging a risk**, cite the quality attribute by its ISO/IEC 25010:2023 name and tie it to a specific scenario (use case, growth, or exploratory). "This is a Reliability risk under the exploratory scenario 'single-region loss', because the design has no cross-region replication strategy for the order journal."
4. **When acknowledging a non-risk**, be brief. "The choice of Postgres over a new datastore is a non-risk: the operational maturity of Postgres covers the stated Reliability and Maintainability priorities."

### What to avoid

- Inventing utility-tree nodes the team did not declare. If the team has not declared performance priorities, you cannot identify a sensitivity point **for** performance in this system; you can only surface that the performance priorities are not declared.
- Citing ISO characteristics by their 2011 names ("Usability", "Portability"). The current edition is 2023.
- Using ATAM vocabulary without meaning it. "This is a sensitivity point" is not a finding; "this is a sensitivity point because a change to X propagates to Y with no boundary" is a finding.

## Sources

- Kazman, R., Klein, M., Clements, P. *ATAM: Method for Architecture Evaluation*. CMU/SEI-2000-TR-004 / ESC-TR-2000-004, August 2000. [sei.cmu.edu/documents/629/2000_005_001_13706.pdf](https://www.sei.cmu.edu/documents/629/2000_005_001_13706.pdf). Primary source for sensitivity points, tradeoff points, risks, and non-risks.
- Clements, P., Kazman, R., Klein, M. *Evaluating Software Architectures: Methods and Case Studies*. Addison-Wesley, 2001. ISBN 978-0-201-70482-2. Book-length treatment with worked examples.
- ISO/IEC. *ISO/IEC 25010:2023 Systems and software engineering - SQuaRE - Product quality model.* November 2023. [iso.org/standard/78176.html](https://www.iso.org/standard/78176.html). Current edition of the quality-attribute catalogue.
- arc42. *Update on ISO 25010, version 2023.* [quality.arc42.org/articles/iso-25010-update-2023](https://quality.arc42.org/articles/iso-25010-update-2023). Plain-language summary of the 2011 → 2023 changes.
- Kazman, R. *A Life-Cycle View of Architecture Analysis and Design Methods.* CMU/SEI-2003-TN-017. Positions SAAM, ARID, ATAM, CBAM, and QAW along the development life cycle.
- Barbacci, M., et al. *SEI Architecture Analysis Techniques and When to Use Them.* SEI asset 5883, 2002. [sei.cmu.edu/library/asset-view.cfm?assetid=5883](https://www.sei.cmu.edu/library/asset-view.cfm?assetid=5883). Catalogue of SEI methods with usage guidance.
