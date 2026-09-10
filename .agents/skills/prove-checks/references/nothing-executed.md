# Runs that execute nothing and report success

Every shape below was measured on go1.26.2. Go is the worked example; the classes are properties of any runner that reports a result per suite rather than per executed check.

Every claim about the event schema carries the version it was measured at, because these claims rot quietly: the documentation rendered for tip describes fields that a released toolchain does not emit, so a count of actions or fields read from a doc page is a claim about some version, rarely the one in your hand. Re-measure the pinned numbers against your own toolchain before relying on them.

## The states, and which defense reaches them

| Shape | What the stream shows | Reached by |
|---|---|---|
| Gate set, helper skips | test-level `skip`, package-level `pass`, exit 0 | floor above zero |
| Filter matched nothing | no test-level events at all, package-level `pass` | floor above zero |
| Package has no test files | package-level `skip`, exit 0 | floor above zero |
| Cached replay | test-level `pass` with the earlier run's `Elapsed`, exit 0 | `-count=1`, or refusing a `(cached)` marker |
| Parent of skipped subtests | subtests `skip`, parent emits its own test-level `pass` | naming leaf tests in the manifest |
| Two packages share a test name | one copy `pass`, the other `skip`, both in one shard | keying the manifest by package and test together |
| Fuzz target with an empty seed corpus | test-level `pass`, no descendant events | requiring a corpus subtest under every fuzz target |
| `TestMain` returns without `m.Run` | no test-level events, no `PASS` line either | floor above zero |
| Helper returns instead of skipping | test-level `pass`, no `skip` anywhere | **nothing below the source** |
| Assertion inside a false condition | test-level `pass`, no `skip` anywhere | **nothing below the source** |

Ten modes, and a floor above zero reaches four of them. The middle four each need one more clause rather than a new mechanism. The last two are the limit: read on.

Two of these deserve their own note. A test's identity in the stream is the `Package` and `Test` pair, never the name alone, so a manifest keyed on the name is satisfied by whichever same-named copy happened to pass. Resolve the ambiguity by refusing it, not by picking a package. And `TestMain` returning instead of calling `os.Exit(m.Run())` prints `ok <pkg> 0.001s` with no `PASS` line and no annotation of any kind, which makes it the quietest member of the set.

## The limit worth stating plainly

A `pass` event says a body ran to completion without failing. It does not say the body asserted anything, and no field in the event distinguishes a test that exercised its subject from one that returned early on a missing credential. A helper written as

```go
if os.Getenv("TOKEN") == "" {
    return
}
```

produces a clean test-level `pass` and no `skip` event of any kind, so it satisfies a floor and a manifest naming it. Counting events cannot reach this. What reaches it is a review rule (an unmet precondition ends in `t.Skip` or `t.Fatal`, never a bare `return`) plus an assertion the covered work itself records, such as a request counter read from the dependency rather than from the test.

Prefer the skip. A skip is at least a distinct outcome that a floor and a manifest can both see; a silent return is indistinguishable from success by construction.

**That review rule does not reach every shape the limit covers.** A fuzz target whose seed corpus is empty contains no bare `return` to forbid, and no precondition check at all, yet it reports a test-level `pass` over a callback that never ran: without `-fuzz` the target replays its corpus, and an empty corpus replays nothing. Measured on go1.26.2, `FuzzNoSeeds` emitted one `pass` carrying its own name and no descendant event, while a target holding a single `f.Add` value emitted a `FuzzWithSeed/seed#0` subtest first. So the corpus is what executed the body, and the handle is structural rather than editorial: require at least one descendant event under every fuzz target the manifest names, and treat a bare parent `pass` as an empty corpus. A target whose seeds live only in `testdata` inherits the same exposure the moment that directory is absent from the checkout.

## Cache replay is the easiest one to miss (measured at go1.26.2)

A cached run is not a fast run. The toolchain replays the previous run's output through the JSON converter, so the stream carries test-level `pass` events with the original `Elapsed` value, and the only marker is a package-level output line ending `(cached)`. Measured: a package whose single test sleeps two seconds returned in 0.123s on the replay against 2.183s fresh, and emitted an identical `"Elapsed":2`.

Two consequences. A repeat loop that omits `-count=1` measures the cache after its first iteration, which is the same defect as the unset gate wearing different clothes. And the documentation's claim that the `Time` field "is conventionally omitted for cached test results" does not hold under `go test -json`: every event of the replayed stream carried a fresh `Time`. Do not use the presence of `Time` to detect a replay.

## The documented event schema is incomplete (measured at go1.26.2)

At go1.26.2, `go doc cmd/test2json` lists nine action values (`start`, `run`, `pause`, `cont`, `pass`, `bench`, `fail`, `output`, `skip`) and a seven-field `TestEvent`. That same toolchain emits more than it documents. Measured actions `attr` (from `t.Attr`) and `artifacts` (from `t.ArtifactDir` under `-artifacts`) appear in neither list, and they carry fields `Key`, `Value`, and `Path` that the documented struct does not declare. The emitter is `src/cmd/internal/test2json/test2json.go`, whose internal `event` struct declares all three at that version and whose scanner recognizes `=== ATTR` and `=== ARTIFACTS`. Both the nine and the seven are version-bound counts; the sets only grow.

So a parser written against the documented action set meets values it does not know. Match on the actions you count and ignore the rest, rather than switching exhaustively and failing on an unknown one.

## Counting rule (measured at go1.26.2)

Count `pass` events carrying a non-empty `Test`. The package-level `pass` omits `Test` and is emitted even when every test skipped, so an unqualified count of `pass` reads one on a suite that executed nothing. That single qualifier is what separates the guard from a vacuous check.
