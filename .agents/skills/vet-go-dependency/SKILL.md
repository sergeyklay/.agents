---
name: vet-go-dependency
description: "Measure a candidate Go module's real maintenance state and its behavior against the protocol or schema version the project has already pinned, before taking it as a dependency. Use when deciding whether to adopt, replace, or drop a library, when choosing between several modules implementing the same protocol or SDK, when an architecture decision turns on whether a module is still maintained, or when a module looks healthy by stars and release count and the question is whether it can actually reach the project's pin. Separates maintainer commits from pushes, reads the unmerged pull request queue as the maintenance signal, censuses consumer forks, reads the interface at the pinned tag instead of the README, and runs the library in a scratch module against the input class the project has committed to. Do NOT use for a vulnerability in a dependency the project has already adopted (scan-security), a publication-grade weighted comparison document (compare-it), or a library question with no adoption decision attached (research-it)."
metadata:
  author: Serghei Iakovlev
  version: "1.0"
  category: research
---

# Vetting a candidate dependency

A module's landing page reports the wrong variables. Stars measure attention at some point in the past, release count measures how often a tag was cut, and `pushed_at` moves whenever anything touches the repository. None of the three answers the question that decides adoption: can this module reach the version this project has already committed to, and does it behave correctly when it gets there.

The two facts that settle it are both invisible from the README. The first is the queue of pull requests nobody has merged, which measures whether the module can still move. The second is what the library does at runtime with the exact input class this project will feed it, which measures whether moving would help.

The subject here is a module that is not yet a dependency, characterized empirically before it becomes one rather than described from its documentation. It sits beneath `research-it`, which owns source priority, triangulation, and the discipline around absence claims. This skill owns only how a candidate module's health and fitness are measured, and what verdict that measurement supports.

## When this fires

- An architecture decision turns on adopting, replacing, or dropping a library, and the project's rule is to ask before adding a dependency.
- Two or more modules implement the same protocol, SDK, or wire schema, and one must be chosen.
- A module is already a candidate in a draft decision record and the open question is whether it is alive enough to depend on.
- A module the project uses looks stalled and the question is whether to fork, vendor, pin, or leave.

Not this skill: a CVE or advisory against a dependency already in `go.mod`, which is `scan-security`; a publication-grade weighted comparison document, which is `compare-it`; a general question about a library's design with no adoption decision attached, which is `research-it`.

## Fix the pin before measuring anything

The first move is not about the candidate. Establish what the consuming project has already committed to (the protocol revision, the schema version, the wire format, the interface it must satisfy) and write it down as a literal string.

Every later measurement is relative to that pin, and without it the measurements are unfalsifiable. "Actively maintained" is not a finding. "Its newest tag implements revision N-1, and the pull request raising it to N has been open 19 days with no maintainer reply" is a finding, and it is a different one from "the maintainer stopped working."

Derive the pin from the project's own code and specifications, not from the candidate's documentation. A candidate that describes itself as implementing the protocol is describing some revision of it.

## Procedure

Run steps 1 through 5 identically for every candidate. Asymmetric measurement produces a verdict about the candidate that got measured hardest, not about the candidates.

### 1. Separate the maintainer's activity from the repository's activity

```bash
gh api repos/OWNER/REPO \
  --jq '{stars: .stargazers_count, pushed: .pushed_at, created: .created_at, archived, fork: .fork, parent: .parent.full_name}'
gh api repos/OWNER/REPO/commits --jq '.[] | {date: .commit.author.date, author: .author.login}' | head -20
```

`pushed_at` is not a maintenance signal. It advances on a bot commit, a merge of someone else's branch, a tag, a README fix. Read instead the date of the last commit authored by someone with write access, and read `created_at` beside it: a repository three weeks old has no track record to measure, and its silence means nothing yet.

Then look at the maintainer, not only at the repository. A sole maintainer committing daily in other repositories while this one sits still is a deliberate deprioritization, and it forecasts the response to your pull request. A maintainer who has vanished everywhere is a different diagnosis with a different remedy.

`fork` and `parent` change the reading entirely. A fork that is ahead of its parent is a workaround somebody already needed; a fork behind its parent is abandoned. Follow the parent before spending effort on either.

### 2. Read the unmerged pull request queue

```bash
gh api 'repos/OWNER/REPO/pulls?state=open&per_page=100' \
  --jq '.[] | {num: .number, title, created: .created_at, updated: .updated_at, author: .user.login}'
gh api 'repos/OWNER/REPO/issues/NUMBER/comments' --jq '.[] | {user: .user.login, created: .created_at}'
```

This is the highest-yield step in the whole procedure, and it is the one no landing page shows. Merged history reports what the maintainer chose to do; the open queue reports what the maintainer is not doing now.

Read three things from it:

- **The oldest unanswered pull request, in days.** Not the oldest open one, since contributors abandon branches, but the oldest one carrying no maintainer reply. That number is the honest estimate of the latency a bug report from this project would meet.
- **Whether the pin from the section above is sitting in that queue.** A pull request that raises the module to the revision this project needs, unmerged and unanswered, is decisive: the module cannot reach the pin, and adopting it means adopting the fork or the wait.
- **Whether contributors are still arriving.** An empty queue reads as health when contributors have stopped trying, and as health when the maintainer is fast. Distinguish the two by the merged-pull-request rate over the same window.

### 3. Census the consumers for forks and workarounds

The projects that already depend on the module have run the experiment. Search for forks that are ahead of the parent, for vendored copies, and for the module's symbols appearing next to a comment explaining why the upstream one could not be used.

```bash
gh api 'repos/OWNER/REPO/forks?sort=stargazers&per_page=100' \
  --jq '.[] | select(.stargazers_count > 0) | {full_name, stars: .stargazers_count, pushed: .pushed_at}'
```

A significant consumer maintaining its own fork is the strongest available evidence that the upstream module did not survive contact with production. It also tells you what the workaround costs, which is the number the decision actually needs.

### 4. Read the interface at the pinned tag, from source

The README describes an intent; the exported interface at the tag is the contract. Fetch the source at the exact tag under consideration, never at the default branch, and read the types the project would have to satisfy.

```bash
curl -fsSL "https://raw.githubusercontent.com/OWNER/REPO/TAG/path/to/file.go" | tee /tmp/candidate.go
```

**Confirm the tag resolves before believing anything fetched at it,** and run a positive control before reading any zero as absence. A scoped code search that returns zero hits is consistent with two different worlds: the symbol is absent, or the scope is invisible to the index. `gh api search/code` indexes the default branch only, and it does not index a repository that was created recently at all, so a `total_count` of `0` from it can mean the repository is simply not there yet.

```bash
# If this control also returns 0, the scope is dead and the zero is not evidence.
gh api "search/code?q=repo:OWNER/REPO+package" --jq '.total_count'
```

When the control returns zero, do not soften the claim. Change instrument. Download the release tarball or the raw tree at the tag, grep it locally, and re-run a control against the local copy that must match:

```bash
curl -fsSL "https://github.com/OWNER/REPO/archive/refs/tags/TAG.tar.gz" | tar -xz -C /tmp
grep -rl 'package ' /tmp/REPO-TAG --include='*.go' | wc -l   # positive control: must be non-zero
grep -rn 'SymbolYouAreChasing' /tmp/REPO-TAG --include='*.go'
```

### 5. Probe the one behavior the project has already committed to

Reading the interface tells you the shape. It does not tell you what the library does with input it was not expecting, and that is usually the behavior the decision turns on: whether an unknown enum or union variant is tolerated or rejected, whether an absent optional field decodes to the schema's default or to an error, whether a forward-compatible message from a newer peer survives the round trip.

Build a scratch module outside the repository and run it. The candidate is a public module, so nothing needs to be added to the project's `go.mod` and the working tree stays clean.

```bash
d=$(mktemp -d) && cd "$d" && go mod init probe
go get MODULE@TAG
# main.go: feed the library the exact input class this project will feed it,
# print what came back, and print the error verbatim rather than a summary of it.
go run .
```

Choose the input from the project's committed behavior, not from the library's test suite. The library's own tests exercise what its author expected; the probe must exercise what this project will actually send. Record the verbatim output, because an error string is the real contract and paraphrasing it loses the distinction between "rejected the message" and "decoded it with the field dropped."

A candidate that tracks the pin and fails this probe is disqualified more firmly than one that lags the pin and passes, because a version gap closes and a design decision does not.

## The verdict

State one of three, per candidate, each tied to a dated measurement:

- **Adopt.** Reaches the pin, probe passes, queue latency acceptable.
- **Adopt with a named risk.** Reaches the pin and passes, but a measurement says the module may not move again. Name the risk, name what the project does when it materializes (fork, vendor, or replace) and name the cost.
- **Reject.** Cannot reach the pin, or fails the probe, or the queue shows it cannot move.

Every verdict carries a **reversal condition**: the specific, checkable change that would flip it. "The open pull request raising it to revision N is merged" is a reversal condition. "It becomes more mature" is not.

## Where the findings go

The measurements rot on a schedule. A star count, a `pushed_at`, a queue depth, and an oldest-unanswered-pull-request age are all wrong within weeks, so they belong in the decision that consumed them and nowhere else.

The verdict and its reversal condition belong in the architecture decision record, written through `manage-adr`, which owns numbering, structure, and the immutability rules. Changes under `docs/decisions/` are ask-first in this project; propose the revision, do not land it unasked.

The probe program is working material. Keep it in the scratch directory for the life of the session and let it go; if its behavior matters after adoption, it belongs in the repository as a test that fails when the library changes, not as a note that says the library once behaved a certain way.

Do not deposit the measurements in a durable notes file. A committed sentence naming a star count or a version freezes the file to the day it was written, and the next reader cannot tell whether it was ever re-checked.

## Validation

The vetting is done when:

- The pin is written down as a literal string, derived from this project's code rather than the candidate's documentation.
- Every candidate got all five steps. None was eliminated on a signal the others were not measured against.
- The last maintainer-authored commit date is recorded per candidate, distinct from `pushed_at`.
- The open pull request queue was read, and the oldest unanswered pull request is quoted in days.
- Whether the pin is reachable from the newest tag is stated explicitly, and if it sits in the open queue, that is named.
- The interface claim comes from source fetched at a tag confirmed to resolve, not from the README and not from the default branch.
- Every zero-hit search is paired with a positive control that succeeded; where a control returned zero, the instrument was changed and the search re-run locally.
- The runtime probe ran, and its verbatim output, including any error string, is recorded.
- Each verdict carries a reversal condition that is checkable.

## Anti-patterns

- **Reading `pushed_at` as maintenance.** It advances on bots, tags, and merges of other people's work. The last maintainer-authored commit is the signal.
- **Reading stars as fitness.** Stars measure past attention. The most-starred candidate is routinely the one that cannot reach the pin.
- **Measuring only merged history.** Merged pull requests report what the maintainer did; the unmerged queue reports what the maintainer is not doing, which is what a future bug report will meet.
- **Trusting a zero from a scoped code search.** A repository created recently is not indexed at all, and `search/code` sees only the default branch. Run the control; when the control is also zero, change instrument rather than softening the claim.
- **Reading the README instead of the interface at the tag.** The README describes an intent and is written once.
- **Concluding fitness from the interface alone.** The shape compiles; the decision usually turns on what the library does with an input it did not expect, and only running it shows that.
- **Probing with the library's own test inputs.** They exercise the author's expectations. The probe must send what this project sends.
- **Asymmetric measurement.** Eliminating one candidate on a signal the others were never measured against produces a verdict about the search order.
- **A verdict with no reversal condition.** The measurement expires; without a named trigger, nobody knows when to look again.
- **Depositing the star count, the version, or the queue depth in a durable notes file.** It is wrong by the time it is read, and silently.
