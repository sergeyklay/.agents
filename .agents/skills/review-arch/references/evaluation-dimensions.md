# Evaluation Dimensions

## Contents

- How to use this file
- Dimension 1 - Alignment with business drivers
- Dimension 2 - Quality-attribute tradeoffs
- Dimension 3 - Structural integrity
- Dimension 4 - Anti-patterns
- Dimension 5 - Gaps and unknowns
- Cross-dimension: where does this finding belong?
- Scope calibration

The working checklist for Step 4 of the review workflow. Read this file on the first review of a session - it is what you tick against while you look at the system. Each dimension names the questions to ask, what counts as evidence of a finding, and the common failure mode that makes reviewers chase the wrong signal.

## How to use this file

Walk the dimensions in order. Dimension 1 is a gate: if the team has not declared what the system is optimising for, you cannot evaluate anything else, because every tradeoff in dimensions 2-5 is measured against those priorities. Once Dimension 1 is confirmed, the other four can be worked in parallel - they overlap less than they look.

Not every dimension applies to every review. A review of a single component's internal design does not need a full Dimension 1 pass. A review of a high-level decomposition does not need Dimension 3's line-level coupling analysis. Scope the dimensions to the review.

## Dimension 1 - Alignment with business drivers

**What you are checking.** Whether the architectural decisions support the stated business goals, or contradict them. An architecture is correct or incorrect only *relative to what the business needs from it*. An excellent architecture for the wrong problem is the wrong architecture.

### Questions to ask

- What is the system's purpose, and who are its users? If the answers are fuzzy, the review cannot proceed.
- What are the primary business drivers? Time to market, regulatory compliance, low operational cost, high availability, rapid learning, market differentiation?
- What are the quality-attribute priorities, in order? Which is the organisation willing to trade for which?
- Have these priorities been written down, or are they only in one person's head?
- Does any architectural decision directly contradict a stated driver?

### What counts as a finding

- A stated business driver (e.g. "must support 99.99% uptime") with an architectural decision that cannot satisfy it (e.g. single-region deployment with no DR plan). This is a critical risk.
- A stated business driver with no corresponding architectural decision at all (e.g. "must support GDPR data erasure" with no data-lineage or deletion mechanism). This is a gap.
- Priorities that have not been declared. This is an open question, not a finding - you cannot evaluate tradeoffs without them.

### Common failure mode

Assuming the priorities. If the review says "for a high-availability system this approach is wrong", but the team never said this was a high-availability system, the entire line of reasoning collapses. Always ground Dimension 1 in stated goals; if they are missing, surface that in Open Questions before making judgements elsewhere.

## Dimension 2 - Quality-attribute tradeoffs

**What you are checking.** Whether the tradeoffs between quality attributes are acknowledged, intentional, and aligned with the Dimension 1 priorities. Every significant architectural decision improves some attribute at the expense of another; your job is to make the tradeoff visible and judge whether it points in the right direction.

### Questions to ask

- For each significant decision: which quality attribute does it favour? Which does it degrade?
- Is that direction consistent with the stated priorities from Dimension 1?
- Where are the **sensitivity points** - decisions where a small change would produce a large effect on one attribute?
- Where are the **tradeoff points** - decisions where improving one attribute degrades another?
- Have the authors named the tradeoffs explicitly, or are they implicit (and therefore likely to be re-litigated later)?

The ATAM vocabulary (sensitivity point, tradeoff point, risk, non-risk, utility tree, scenarios) and the ISO/IEC 25010:2023 quality characteristics are defined in [quality-attributes.md](quality-attributes.md). Load that file when the system has non-trivial tradeoffs or when the priorities from Dimension 1 are ambiguous.

### What counts as a finding

- A tradeoff made in the **wrong direction** given Dimension 1 priorities (e.g. "consistency was optimised at the expense of availability" in a system where availability is the stated priority).
- A tradeoff that is **undeclared** - the design has consequences the authors have not acknowledged (e.g. synchronous chains that multiply latency are presented as if each hop's latency is the only cost).
- A sensitivity point that is **not guarded** - a decision where a small change breaks something critical, with no tripwire or regression protection.
- Missing quality-attribute scenarios - the design has no stated availability target, no stated latency budget, no stated throughput ceiling, and therefore cannot be evaluated against them.

### Common failure mode

Treating quality attributes in isolation. "Security is good" or "performance is good" without naming what each costs the other is not a tradeoff analysis; it is a checklist. The finding should always take the form "attribute X is favoured at the cost of attribute Y, because Z".

## Dimension 3 - Structural integrity

**What you are checking.** Whether component boundaries, data ownership, and communication patterns are appropriate. Good structure is not about looking neat; it is about whether the boundaries are drawn along the lines on which the system is likely to *change*.

### Questions to ask

- Are component boundaries and responsibilities clear? Does each component have a single, describable responsibility?
- Is coupling between components appropriate? Loose coupling across service boundaries; tight cohesion within a module.
- Where is the **source of truth** for each domain entity? Is ownership declared or diffused?
- Is the chosen communication pattern - sync vs. async, request-response vs. event-driven, push vs. pull - appropriate for each interaction? A payment confirmation that does not need to be synchronous does not need to be synchronous.
- Does the module decomposition align with the **likely change vectors**? A component that must change whenever any of three others changes is in the wrong place.

### What counts as a finding

- A component whose responsibility cannot be stated in one sentence. It is doing more than one thing; flag it.
- Two services that must be deployed together to work. This is a **distributed monolith** signal.
- Data owned by two places. This is a **shared-database** signal or an ambiguous ownership signal; in either case it is a concrete risk.
- Synchronous call chains three or more hops deep. Latency and failure probability multiply.
- A component that changes whenever a neighbour changes. The boundary is drawn in the wrong place.

For the named anti-patterns (distributed monolith, shared database, synchronous call chain, and the rest), symptoms and fixes are catalogued in Dimension 4 below.

### Common failure mode

Evaluating structure against a generic "clean architecture" template rather than against the likely change vectors of this specific system. A design that looks messy on paper may be correct if the messy lines are exactly where change is cheap; a design that looks clean may be wrong if the clean lines are where change is expensive.

## Dimension 4 - Anti-patterns

**What you are checking.** Whether the architecture matches any known structural failure mode. Anti-patterns are not just things that "feel wrong"; they are patterns documented in the literature with specific, predictable failure modes. Naming the anti-pattern gives the finding teeth, because it names the mechanism of failure.

### Questions to ask

Walk the catalogue in [anti-patterns.md](anti-patterns.md) and ask, for each one, whether this architecture exhibits it. The catalogue names:

- Distributed monolith
- Shared database
- God service
- Synchronous call chain
- Missing failure handling
- Premature distribution
- Premature optimisation
- Resume-driven architecture
- Dual-write
- Chatty services
- Event-sourcing misuse
- Vendor lock-in optimism

### What counts as a finding

An architectural decision that matches the **symptom** of a documented anti-pattern, where the anti-pattern's specific risk applies to this system. The finding cites:

1. The anti-pattern by name ("this is a distributed monolith because...").
2. The symptom in this system ("services A, B, C cannot be deployed independently; changing A requires coordinated releases of B and C").
3. The specific mechanism of failure ("deployments are serial, blast radius is global, and the team will lose the main claimed benefit of microservices - independent deployability").
4. The fix or mitigation.

### Common failure mode

Using "anti-pattern" as a cudgel rather than a diagnostic tool. "This is an anti-pattern" is not a finding; "this is the **distributed monolith** anti-pattern because [symptom], which produces [specific failure mode]" is a finding. If the cited symptom is not actually present, cut the finding.

## Dimension 5 - Gaps and unknowns

**What you are checking.** What the architecture does **not** address that it should. Every architecture makes implicit assumptions; the review's job is to surface them and decide whether they are safe.

### Questions to ask

- **Failure domains.** What happens when the database is down? When the message broker is down? When a dependency returns 500s? When a region is lost? Is there an explicit strategy for each?
- **Data lifecycle.** How is data migrated? How is it archived? How is it deleted? Is retention declared?
- **Capacity.** What is the projected load? At what point does the current design cease to support it? What is the plan beyond that point?
- **Multi-tenancy / isolation.** Are tenants isolated at the data, compute, or both layers? What guarantees does the architecture make about cross-tenant data exposure?
- **Regulatory / compliance.** Are there stated compliance obligations (GDPR, HIPAA, SOX, PCI)? Does the architecture support them, or does it require features that are not yet in the design?
- **Disaster recovery.** RPO (recovery point objective) and RTO (recovery time objective) - are they declared? Does the design meet them?
- **Upgrades and migrations.** How does the architecture evolve? Are backwards-compatibility rules stated?
- **Observability.** Can the system be debugged in production? Can operators answer "what is wrong right now" from the data the system emits?

### What counts as a finding

- A gap that **affects a stated priority from Dimension 1** is a risk of the corresponding severity. If the system must support GDPR and has no deletion path, this is a critical risk, not an observation.
- A gap that does **not** affect any stated priority is an open question. Surface it; the team may have answered it elsewhere.
- An **implicit assumption** that the architecture depends on, without the team having validated it. ("The database can handle this load" - was this benchmarked?) These belong as observations unless the assumption is load-bearing for a stated priority.

### Common failure mode

Treating "missing section in the design document" as automatically a risk. Some gaps are genuine risks; others are just things the design did not need to spell out because the team's operational practice already covers them. Ask: *is this gap actually going to bite someone?* If not, it is an observation at most.

## Cross-dimension: where does this finding belong?

Many findings look like they belong in multiple dimensions. Use this routing rule:

| Finding type | Belongs in |
|---|---|
| "The business driver X is not served by this architecture" | Dimension 1 |
| "The design optimises for attribute A at the cost of attribute B, contrary to stated priorities" | Dimension 2 |
| "Component boundaries are drawn wrong because..." | Dimension 3 |
| "This matches the [named] anti-pattern" | Dimension 4 |
| "The design does not address [named concern]" | Dimension 5 |

When a single issue fits multiple dimensions, put it in the **earliest** matching dimension (lower number = higher level). A missing DR plan in a high-availability system is a Dimension 1 alignment failure *and* a Dimension 5 gap - record it in Dimension 1 because the Dimension 1 framing makes the severity clear.

## Scope calibration

Not every review goes deep on every dimension. Calibrate effort to the artefact under review:

- **Early-stage design doc / RFC.** Heavy on Dimensions 1 and 5 (alignment, gaps). Light on Dimensions 3 and 4 (not enough detail yet to evaluate boundaries or detect anti-patterns). Dimension 2 moderate.
- **Mid-implementation architecture review.** Heavy on Dimensions 2, 3, 4 (tradeoffs, structure, anti-patterns). Dimension 5 moderate (gaps relative to what has been committed). Dimension 1 checks that the original priorities still hold.
- **Post-deployment audit.** Heavy on all five dimensions, plus operational reality: is the architecture *actually* doing what it was designed to do, or have runtime patterns diverged?
- **Targeted review of a single component or decision.** Dimension 2 and 3 only, applied at the component level.

Mismatched scope is itself a review defect: a full five-dimension review on a single-paragraph design question wastes the reader's time; a surface-level scan on a full system architecture misses the load-bearing findings.
