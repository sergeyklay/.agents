# Runs that execute nothing and report success

Every shape below was measured on go1.26.2. Go is the worked example; the classes are properties of any runner that reports a result per suite rather than per executed check.

Every claim about the event schema carries the version it was measured at, because these claims rot quietly, and the drift is not between a release and some unreleased branch where a reader would think to discount it. It is between one release and another. The default view of `cmd/test2json` on the package site rendered go1.27.1 when this was written, whose `TestEvent` carries an `OutputType` field that go1.26.2 does not have, and nothing on the page marks the difference. So a count of actions or fields read from the current official documentation is a claim about whichever release that page happens to serve, rarely the one in your hand. Re-measure the pinned numbers against your own toolchain with `go doc cmd/test2json` before relying on them.

## The states, and which defense reaches them

| Shape | What the stream shows | Reached by |
|---|---|---|
| Gate set, helper skips | test-level `skip`, package-level `pass`, exit 0 | floor above zero |
| Filter matched nothing | no test-level events at all, package-level `pass` | floor above zero |
| Package has no test files | package-level `skip`, exit 0 | floor above zero |
| Cached replay | test-level `pass` with the earlier run's `Elapsed`, exit 0 | `-count=1`, or refusing a `(cached)` marker |
| Parent of skipped subtests | subtests `skip`, parent emits its own test-level `pass` | naming leaf tests in the manifest |
| Two packages share a test name | one copy `pass`, the other `skip`, both in one shard | keying the manifest by package and test together |
| Fuzz target with an empty seed corpus | test-level `pass`, no descendant events | requiring a passing corpus subtest, on a replay run |
| Fuzz seed whose callback skips | `run` then `skip` under the parent, parent still `pass` | the same passing-subtest rule, and the leaf rule |
| `TestMain` returns without `m.Run` | no test-level events, no `PASS` line either | floor above zero |
| Helper returns instead of skipping | test-level `pass`, no `skip` anywhere | **nothing below the source** |
| Assertion inside a false condition | test-level `pass`, no `skip` anywhere | **nothing below the source** |

Eleven modes, and a floor above zero reaches four of them. Three of the middle five each need one more clause rather than a new mechanism. The two fuzz rows share one clause plus the run's mode, and only the invocation settles that. The last two are the limit: read on.

Three of these deserve their own note. A test's identity in the stream is the `Package` and `Test` pair, never the name alone, so a manifest keyed on the name is satisfied by whichever same-named copy happened to pass. Resolve the ambiguity by refusing it, not by picking a package. `TestMain` returning instead of calling `os.Exit(m.Run())` prints `ok <pkg> 0.001s` with no `PASS` line and no annotation of any kind, which makes it the quietest member of the set. And the cache row reads a marker out of the run's own output, which is safe only because it reads it to refuse: a subject that forges `(cached)` fails its own run. Never read the output that way to excuse a run, which is what the fuzz row's mode would have done.

## The limit worth stating plainly

A `pass` event says a body ran to completion without failing. It does not say the body asserted anything, and no field in the event distinguishes a test that exercised its subject from one that returned early on a missing credential. A helper written as

```go
if os.Getenv("TOKEN") == "" {
    return
}
```

produces a clean test-level `pass` and no `skip` event of any kind, so it satisfies a floor and a manifest naming it. Counting events cannot reach this. What reaches it is a review rule (an unmet precondition ends in `t.Skip` or `t.Fatal`, never a bare `return`) plus an assertion the covered work itself records, such as a request counter read from the dependency rather than from the test.

Prefer the skip. A skip is at least a distinct outcome that a floor and a manifest can both see; a silent return is indistinguishable from success by construction.

**That review rule does not reach every shape the limit covers.** A fuzz target whose seed corpus is empty contains no bare `return` to forbid, and no precondition check at all, yet it reports a test-level `pass` over a callback that never ran: without `-fuzz` the target replays its corpus, and an empty corpus replays nothing. Measured on go1.26.2, `FuzzNoSeeds` emitted one `pass` carrying its own name and no descendant event, a target holding a single `f.Add` value emitted a `FuzzWithSeed/seed#0` subtest first, and a target seeded only from `testdata` emitted its subtest with that directory in place and nothing under itself with the directory moved aside. So on a replay run the corpus is what enters the body, and a manifest entry naming a fuzz target needs at least one descendant `pass` before it counts. A descendant event is not enough: a seed whose callback skips emits `run` and `skip` under the parent while asserting nothing, and the parent still reports `pass`. Read a bare parent `pass` on such an entry as an empty corpus. The requirement is a floor and not a proof, because it establishes that some input entered the callback rather than that the callback covered anything.

**Scope that requirement to replay runs.** An active `-fuzz` run reports no descendant at all. Measured on go1.26.2, `FuzzAlwaysOK` under `-fuzz` for four seconds logged 6,855,065 executions of its callback and emitted exactly one test-level `pass` with no subtest beneath it, so a rule demanding a descendant refuses the single run in this whole set that does the most work. Derive the mode from the invocation the checker itself issues, reading `-fuzz` back out of the argv it passed, and match that flag exactly because `-fuzztime` starts no fuzzing. Do not accept it as a declaration handed in beside the run: a declaration is an account of the invocation, and step 2 of the procedure is about why an account is not the state. Never read it from the output either, which any test can print.

## Cache replay is the easiest one to miss (measured at go1.26.2)

A cached run is not a fast run. The toolchain replays the previous run's output through the JSON converter, so the stream carries test-level `pass` events with the original `Elapsed` value, and the only marker is a package-level output line ending `(cached)`. Measured: a package whose single test sleeps two seconds returned in 0.123s on the replay against 2.183s fresh, and emitted an identical `"Elapsed":2`.

Two consequences. A repeat loop that omits `-count=1` measures the cache after its first iteration, which is the same defect as the unset gate wearing different clothes. And the documentation's claim that the `Time` field "is conventionally omitted for cached test results" does not hold under `go test -json`: every event of the replayed stream carried a fresh `Time`. Do not use the presence of `Time` to detect a replay.

## The documented event schema is incomplete (measured at go1.26.2)

At go1.26.2, `go doc cmd/test2json` lists nine action values (`start`, `run`, `pause`, `cont`, `pass`, `bench`, `fail`, `output`, `skip`) and a seven-field `TestEvent`. That same toolchain emits more than it documents. Measured actions `attr` (from `t.Attr`) and `artifacts` (from `t.ArtifactDir` under `-artifacts`) appear in neither list, and they carry fields `Key`, `Value`, and `Path` that the documented struct does not declare. The emitter is `src/cmd/internal/test2json/test2json.go`, whose internal `event` struct declares all three at that version and whose scanner recognizes `=== ATTR` and `=== ARTIFACTS`. Both the nine and the seven are counts measured at one version, and the drift runs in both directions: at go1.26.2 the emitted set exceeded the documented set by two actions and three fields, while go1.27.1 documents an `OutputType` field that go1.26.2 neither documents nor emits.

So a parser written against the documented action set meets values it does not know. Match on the actions you count and ignore the rest, rather than switching exhaustively and failing on an unknown one.

## Counting rule (measured at go1.26.2)

Count `pass` events carrying a non-empty `Test`. The package-level `pass` omits `Test` and is emitted even when every test skipped, so an unqualified count of `pass` reads one on a suite that executed nothing. That single qualifier is what separates the guard from a vacuous check.
