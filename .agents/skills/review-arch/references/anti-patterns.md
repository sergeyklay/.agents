# Architecture Anti-Patterns

## Contents

- How to use this catalogue
- 1. Distributed monolith
- 2. Shared database
- 3. God service
- 4. Synchronous call chain
- 5. Missing failure handling
- 6. Premature distribution
- 7. Premature optimisation
- 8. Resume-driven architecture
- 9. Dual-write
- 10. Chatty services
- 11. Event-sourcing misuse
- 12. Vendor lock-in optimism
- Cross-cutting diagnostic: is this actually the anti-pattern?
- Sources

Twelve structural failure modes that recur in architecture reviews across domains and stacks. Each entry is organised the same way: the **symptom** (what you see in the artefact under review), the **specific risk** (the mechanism by which it fails), the **worked example**, and the **fix** (concrete remediation, not vague advice).

Naming an anti-pattern is not a finding on its own - the goal is not to play pattern bingo. The finding is "this architecture exhibits [anti-pattern X], and in *this context* the specific risk is [Y], which compromises [stated priority Z]." Read the cross-cutting diagnostic at the end before citing an anti-pattern you are not certain about.

## How to use this catalogue

Walk the catalogue during Step 4 / Dimension 4 of the review. For each entry, ask: *does this architecture exhibit the symptom described here?* If yes, work through the entry to check whether the risk mechanism applies, then formulate the finding.

Cite the anti-pattern by name in the review. The name is a compressed reference to the mechanism; citing it correctly saves paragraphs of explanation.

## 1. Distributed monolith

**Symptom.** Multiple services are deployed independently in appearance, but in practice they must be released together. Releasing service A without the corresponding change in services B and C breaks the system.

**Specific risk.** The team takes the cost of distribution (network hops, partial failure, eventual consistency, operational overhead of N services) without the benefit (independent deployability, independent scaling, independent team ownership). This is the **worst of both worlds**: the complexity of distribution with the release coupling of a monolith.

**Worked example.** Service A calls service B synchronously. A new field on A's request requires B to parse it. A change in B's response shape requires A to handle it. Three of the team's last five releases have been "deploy A and B together". This is a distributed monolith.

**Fix.** Either re-monolith the tightly coupled parts (a modular monolith is a legitimate architecture, not a regression), or fix the coupling by introducing versioned contracts, backward-compatible schema evolution rules, and tolerant-reader parsing on the consumer side. The architectural question is: were these services ever supposed to be separate? If the answer is "no, they were split because microservices were in fashion", merge them back.

**Primary sources.** Sam Newman, *Building Microservices*, 2nd ed., O'Reilly 2021. Chris Richardson, [microservices.io](https://microservices.io/), "distributed monolith" terminology.

## 2. Shared database

**Symptom.** Two or more services read from and/or write to the same tables in the same database, typically with no explicit contract about who owns which columns.

**Specific risk.** Schema changes become **coordinated releases** that defeat service independence. More subtly, every service's invariants become dependent on every other service's code - a bug in service A can corrupt data that service B relies on, with no enforceable boundary. The database becomes an implicit shared-memory API, and shared-memory APIs across teams are how systems become unmaintainable.

**Worked example.** Orders service writes to `orders`; payments service writes to `orders.payment_status` directly. A schema migration owned by the orders team breaks the payments team's queries. Neither team is sure who should own the column's semantics. Every schema change now requires a coordination meeting.

**Fix.** Assign a single service as the owner of each table. Other services access the data only through the owner's API (synchronous call, event subscription, or read model / CQRS). Do not share write paths. If reads are the only cross-team access, a read replica or a projected view is acceptable; direct writes across teams are not.

**Primary source.** Richardson, ["Shared database antipattern"](https://microservices.io/patterns/data/shared-database.html).

## 3. God service

**Symptom.** One service handles a disproportionate share of business logic, traffic, or both. It is the service that always has to change when a feature ships. Its code base is several times larger than any other service. Its on-call burden is several times higher.

**Specific risk.** The god service becomes the bottleneck for **every dimension**: team velocity (every PR touches it), scaling (hot spot), reliability (its failure cascades), and cost (over-provisioned to cover its worst case). It recreates the release-coupling problem of a monolith in a service that was supposed to be one among many.

**Worked example.** The "orchestration" service in a system with eight microservices, which wraps every cross-service workflow. Ninety percent of new features require changes to it. Its deploys are treated as high-risk. Two senior engineers have become the implicit owners because no one else can navigate the codebase.

**Fix.** Carve out capabilities from the god service into domain-aligned services. Typically the fix is not "more microservices"; it is "align service boundaries with the domain". A coherent monolith with well-factored internal modules is often better than a god service with satellite services orbiting it.

## 4. Synchronous call chain

**Symptom.** A user-visible operation requires three or more synchronous service-to-service calls in sequence.

**Specific risk.** Latency multiplies. Failure probability multiplies. If each hop has 99.9% availability and 100ms p99 latency, a four-hop chain has 99.6% availability and at least 400ms p99 latency - and that is the **floor**, assuming no queueing or retries. One slow hop (for any reason) cascades to the user. One failed hop fails the whole chain, and the retry logic typically amplifies load at the slow layer, making the problem worse.

**Worked example.** User clicks "confirm order". Frontend calls orders service. Orders service calls inventory service. Inventory service calls pricing service. Pricing service calls promotions service. User waits for all four to complete before seeing "Order confirmed" or a failure.

**Fix.** Break the synchronous chain. Decide what must be strictly synchronous (typically: enough to return a meaningful response to the user) and what can be asynchronous (background verification, notification, enrichment). Use eventual consistency where the product can tolerate it. Where the full chain truly is synchronous (rare), at minimum add per-hop timeouts, circuit breakers, and a fallback for each dependency.

## 5. Missing failure handling

**Symptom.** The architecture is silent about what happens when a dependency fails. No circuit breakers. No retry budgets. No timeouts (or default timeouts inherited from HTTP clients). No graceful-degradation strategy. No named failure modes.

**Specific risk.** In production, dependencies **will** fail - the question is never *if*, only *when* and *how often*. A system designed around the assumption that dependencies always respond quickly and correctly will cascade under any dependency incident. Worse, retries without budgets become the amplifier that turns a brief glitch into an extended outage.

**Worked example.** The payments service calls an external gateway. The call has no explicit timeout. Under a gateway incident, payment calls pile up waiting for responses. Thread pools exhaust. Healthy parts of the system (order browsing, session management) fail because the payment service has consumed the shared thread pool. A 15-minute partner incident becomes a 2-hour outage for the whole platform.

**Fix.** For every external dependency, name:

- Timeout (explicit, in the code, not inherited)
- Retry policy (with budget - maximum retries per time window)
- Circuit breaker (opens after N consecutive failures; closes after M consecutive successes through probe calls)
- Fallback behaviour (cached response, degraded experience, fail-fast with clear user message)

These are not implementation details to leave to the developer; they are architectural decisions that should be visible in the design doc.

## 6. Premature distribution

**Symptom.** A system is split into microservices from day one, before the team has discovered the domain boundaries or has operational experience running distributed systems.

**Specific risk.** The team invents service boundaries based on speculation about future scale or future team structure. The boundaries turn out to be wrong (domain understanding improves with time), and redrawing them across services is orders of magnitude harder than redrawing them within a monolith. Meanwhile the team pays the operational cost of N services (deployment, observability, debugging, cross-service transactions) at a point where the system would run comfortably as one.

**Worked example.** A four-person startup builds its MVP as twelve microservices in a Kubernetes cluster. Each feature requires changes across three to five services. Debugging in production requires correlating logs across them. The team spends more time on operational complexity than on product.

**Fix.** Start with a **modular monolith**. Draw logical boundaries inside the monolith where you think the seams are, but ship as one deployment unit. Split out services when you have specific evidence: a scaling bottleneck that benefits from independent scaling, a team boundary that benefits from independent deployment cadence, or a reliability boundary that benefits from isolation.

**Primary source.** Newman, *Building Microservices*, 2nd ed., O'Reilly 2021 - chapter on "when not to use microservices". Also sometimes framed as "distribute when you are forced to, not because you want to".

## 7. Premature optimisation

**Symptom.** Complexity added for scale that is not yet needed and may never arrive. Typically: multi-region deployment, sharding, exotic caching, bespoke queueing, custom datastores - in a system where the baseline single-instance design would serve current load with room to spare.

**Specific risk.** Every optimisation is a **tax on future change**. A sharded datastore is harder to query across, harder to migrate, harder to debug. A custom caching layer is a second source of truth that can disagree with the primary. A multi-region design is harder to test end-to-end and harder to reason about consistency within. Paying these taxes before needed slows the team down without buying anything that matters yet.

**Worked example.** A B2B product with 200 enterprise customers at ~20 QPS of aggregate traffic ships with a sharded Postgres cluster and a Redis write-through cache in front. The sharding strategy is wrong for the actual access pattern (discovered 18 months later). The cache produces a stale-read bug that takes two engineer-months to diagnose. The premature infrastructure cost the team a year.

**Fix.** Optimise based on measured needs. Ship the simplest architecture that meets current requirements with a reasonable safety margin. Add a load-test scenario that matches the projected growth curve; when the scenario fails, optimise. Not before.

Closely related to premature distribution - premature distribution is premature optimisation for team scale, premature optimisation is typically for load scale.

## 8. Resume-driven architecture

**Symptom.** Technology choices that serve the team's **learning goals** or **career incentives** rather than the system's needs. Kubernetes for a three-container workload. Kafka for 50 messages per day. A service mesh for five services. gRPC everywhere because someone read a blog post about it.

**Specific risk.** Operational burden far exceeds the problem being solved. Onboarding new engineers gets harder - they must learn a stack of tools that serve no visible purpose. Debug paths get longer. Dependency surface grows. The team's best engineer spends time on the plumbing instead of on the product.

**Worked example.** An internal admin dashboard used by 30 employees is built on Kubernetes, a service mesh, event sourcing, and CQRS. The actual workload fits comfortably in a single Rails app. Two engineer-quarters are spent on infrastructure complexity that serves no stated priority.

**Fix.** Name the priority that each technology choice serves. If the answer is "we wanted to learn it" or "it is good for our resumes", that is not an architectural justification. Choose the simplest, most boring technology that meets the actual requirements. The phrase "boring technology" is a compliment in architecture reviews.

**Primary source.** Uwe Friedrichsen, [*The cloud-ready fallacy*](https://www.ufried.com/blog/cloud_ready_fallacy/), and his ongoing anti-patterns work. Gregor Hohpe, *Cloud Strategy* (2020), on "options as cost".

## 9. Dual-write

**Symptom.** A single business operation writes to two independent systems - typically a database and a message broker, or a database and an external API - in what the code treats as a single atomic action, without a protocol that actually makes it atomic.

**Specific risk.** **There is no atomicity across the two writes.** If write 1 succeeds and write 2 fails, the state of the world is inconsistent: the database says the order exists, the message was never emitted, and every downstream consumer that was supposed to react is silently broken. The failure mode is silent, intermittent, and only visible in downstream discrepancies much later.

**Worked example.** The orders service writes to the orders table, then publishes an `OrderCreated` event to Kafka. Occasionally (network flap, broker restart), the publish fails after the database write succeeded. The order exists but no consumer reacts: inventory is not decremented, confirmation email is not sent, analytics misses the event. Two weeks later, operations notices a small cohort of customers whose orders appear to never have been fulfilled.

**Fix.** Use the **transactional outbox** pattern: write the event to an outbox table in the same database transaction as the business write. A separate relay reads from the outbox and publishes to the broker reliably. Both writes live in one atomic database transaction; eventual delivery to the broker is the relay's job. This is a solved problem; do not reinvent it.

**Primary sources.** Gunnar Morling / Red Hat Debezium, [*Avoiding dual writes in event-driven applications*](https://developers.redhat.com/articles/2021/07/30/avoiding-dual-writes-event-driven-applications). Confluent, [*The Dual-Write Problem*](https://www.confluent.io/blog/dual-write-problem/). AWS Prescriptive Guidance on [transactional outbox](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html).

## 10. Chatty services

**Symptom.** Satisfying a single user request requires many small calls between services - sometimes dozens. The individual operations are simple, but the aggregate latency and failure probability dominate.

**Specific risk.** Per-call network overhead (serialisation, transport, deserialisation) and per-call failure probability both scale linearly with call count. A request that makes fifty service-to-service calls at 1ms each is already at 50ms floor for just the transport, before any actual work, and any one of those fifty calls failing triggers retry or fallback logic for the whole request. This is the **Death Star** topology at scale.

**Worked example.** Rendering a product page requires: one call for the product, one per image, one per review summary, one per related item, one per availability check. Fifty calls total. In normal operation, latency is acceptable. Under any service-wide slowdown, the tail latency explodes because the slow service gets hit many times per render.

**Fix.** Aggregate at the boundary. Introduce a back-end-for-frontend (BFF) or API gateway that composes the many calls into a single request for the client, and optimises the composition (parallel calls, batching, caching). Push cross-service data into read models where eventual consistency is acceptable. Consider if the service boundary is drawn in the wrong place - if two services exchange dozens of small calls to satisfy every request, they may be one domain artificially split.

**Primary sources.** InfoQ, [*Cloud-Native Architecture Adoption, Part 2: Stabilization Gaps and Anti-Patterns*](https://www.infoq.com/articles/cloud-native-architecture-adoption-part2/). Friedrichsen's microservices anti-patterns materials.

## 11. Event-sourcing misuse

**Symptom.** Event sourcing is adopted wholesale for a domain that does not need it - typically CRUD-shaped data with no meaningful history requirement - because the team read a talk or a blog post about event sourcing.

**Specific risk.** Event sourcing trades read simplicity for audit completeness and temporal queryability. If the domain does not need the audit trail or the temporal queries, the team pays the cost (projection complexity, schema-evolution rules, eventual consistency between projections, replay-on-demand infrastructure) without getting the benefit. Queries that would be trivial on a normalised schema become expensive projection problems. Schema evolution becomes a research exercise.

**Worked example.** A user-preferences service adopts event sourcing. Every preference update is stored as an event; the current preferences are a projection. Six months later, a new preference field requires rebuilding the projection from all historical events - which nobody has tested at scale. Simple queries that would be a single select on a normalised table require navigating the event schema across several versions.

**Fix.** Use event sourcing where the audit trail and temporal queryability are **first-class product requirements** - financial ledgers, regulated workflows, collaborative systems where "show me the history" is core functionality. For CRUD domains, use a normalised schema with an audit log or change-data-capture stream if an audit trail is needed incidentally. Event sourcing is a commitment, not a default.

## 12. Vendor lock-in optimism

**Symptom.** The architecture depends deeply on a single cloud vendor's proprietary services, with an implicit assumption that migration costs will never matter. Alternatively: the architecture is contorted to avoid **any** vendor specificity, paying heavy abstraction costs to preserve theoretical portability the team will never exercise.

**Specific risk.** Both directions fail symmetrically. Deep lock-in becomes a problem when pricing changes, services deprecate, or regulatory requirements force multi-region or multi-vendor operation. Extreme lock-in avoidance becomes a problem when the abstraction layer itself becomes a maintenance burden, underutilises the vendor's specialised services, and slows feature delivery to buy optionality that may never be used.

**Worked example (deep lock-in).** A system built entirely on AWS Lambda, DynamoDB, and SQS; event schemas are defined in proprietary formats. Two years in, the team needs to run in a different region where AWS pricing has changed significantly, and moving the workload to a second provider is a multi-year rewrite.

**Worked example (over-abstraction).** A system built with a database abstraction layer that forbids Postgres-specific features, to preserve portability to "any SQL database". The team cannot use JSONB, range types, or partial indexes, even though they have no actual plan to migrate. The abstraction costs real performance and real feature velocity to defend a theoretical future.

**Fix.** Treat vendor lock-in as a **cost** that is paid against **benefit**. Use proprietary services when their benefit (managed operation, deep integration, specialised capability) clearly exceeds the eventual switching cost. Avoid proprietary services when the benefit is marginal and the switching cost is material. Most systems should land in the middle: use the vendor's managed services, but keep the **data and the core business logic** in portable forms.

**Primary source.** Gregor Hohpe, *Cloud Strategy* (2020), [architectelevator.com/book/cloudstrategy](https://architectelevator.com/book/cloudstrategy/). Multi-cloud decision model: [architectelevator.com/cloud/multi-cloud-decision-model](https://architectelevator.com/cloud/multi-cloud-decision-model/).

## Cross-cutting diagnostic: is this actually the anti-pattern?

Before citing an anti-pattern in a finding, walk this check:

1. **The symptom is present.** You can point to the specific decision or behaviour that matches the symptom description, in the artefact under review - not a general impression.
2. **The risk mechanism applies.** The specific risk described in the anti-pattern entry is actually a risk for **this system's stated priorities**. A distributed monolith is a severe risk for a team that wanted independent deployability; it may be a non-issue for a team that explicitly chose to ship in lockstep.
3. **The fix is actionable.** You can state a concrete fix that is proportional to the problem. If the only fix you can propose is "rearchitect the whole thing", either the anti-pattern is mis-diagnosed or the problem is genuinely structural and must be flagged as such.
4. **No simpler explanation fits.** Before citing an exotic anti-pattern, check that a simpler local problem (missing timeout, wrong service boundary, missing documentation) does not explain the symptom.

An anti-pattern citation without all four checks is name-calling, not a finding.

## Sources

- Sam Newman. *Building Microservices*, 2nd edition. O'Reilly, 2021. ISBN 978-1-492-03402-5.
- Chris Richardson. [microservices.io](https://microservices.io/) - pattern catalogue.
- Gunnar Morling et al. [*Avoiding dual writes in event-driven applications*](https://developers.redhat.com/articles/2021/07/30/avoiding-dual-writes-event-driven-applications). Red Hat Developer, 2021.
- Confluent. [*The Dual-Write Problem*](https://www.confluent.io/blog/dual-write-problem/).
- AWS Prescriptive Guidance. [*Transactional outbox*](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html).
- InfoQ. [*Cloud-Native Architecture Adoption, Part 2: Stabilization Gaps and Anti-Patterns*](https://www.infoq.com/articles/cloud-native-architecture-adoption-part2/).
- Gregor Hohpe. *Cloud Strategy*. 2020. [architectelevator.com/book/cloudstrategy](https://architectelevator.com/book/cloudstrategy/).
- Uwe Friedrichsen. [*The cloud-ready fallacy*](https://www.ufried.com/blog/cloud_ready_fallacy/).
