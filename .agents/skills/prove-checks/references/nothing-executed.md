# Runs that execute nothing and report success

Every shape below was measured on go1.26.2. Go is the worked example; the classes are properties of any runner that reports a result per suite rather than per executed check.

## The states, and which defense reaches them

| Shape | What the stream shows | Reached by |
|---|---|---|
| Gate set, helper skips | test-level `skip`, package-level `pass`, exit 0 | floor above zero |
| Filter matched nothing | no test-level events at all, package-level `pass` | floor above zero |
| Package has no test files | package-level `skip`, exit 0 | floor above zero |
| Cached replay | test-level `pass` with the earlier run's `Elapsed`, exit 0 | `-count=1`, or refusing a `(cached)` marker |
| Parent of skipped subtests | subtests `skip`, parent emits its own test-level `pass` | naming leaf tests in the manifest |
| Helper returns instead of skipping | test-level `pass`, no `skip` anywhere | **nothing below the source** |
| Assertion inside a false condition | test-level `pass`, no `skip` anywhere | **nothing below the source** |

The first three are what a floor is for. The next two defeat a floor and a naive manifest, and both are recoverable by a clause rather than a new mechanism. The last two are the limit: read on.

## The limit worth stating plainly

A `pass` event says a body ran to completion without failing. It does not say the body asserted anything, and no field in the event distinguishes a test that exercised its subject from one that returned early on a missing credential. A helper written as

```go
if os.Getenv("TOKEN") == "" {
    return
}
```

produces a clean test-level `pass` and no `skip` event of any kind, so it satisfies a floor and a manifest naming it. Counting events cannot reach this. What reaches it is a review rule (an unmet precondition ends in `t.Skip` or `t.Fatal`, never a bare `return`) plus an assertion the covered work itself records, such as a request counter read from the dependency rather than from the test.

Prefer the skip. A skip is at least a distinct outcome that a floor and a manifest can both see; a silent return is indistinguishable from success by construction.

## Cache replay is the easiest one to miss

A cached run is not a fast run. The toolchain replays the previous run's output through the JSON converter, so the stream carries test-level `pass` events with the original `Elapsed` value, and the only marker is a package-level output line ending `(cached)`. Measured: a package whose single test sleeps two seconds returned in 0.123s on the replay against 2.183s fresh, and emitted an identical `"Elapsed":2`.

Two consequences. A repeat loop that omits `-count=1` measures the cache after its first iteration, which is the same defect as the unset gate wearing different clothes. And the documentation's claim that the `Time` field "is conventionally omitted for cached test results" does not hold under `go test -json`: every event of the replayed stream carried a fresh `Time`. Do not use the presence of `Time` to detect a replay.

## The documented event schema is incomplete

`go doc cmd/test2json` lists nine action values (`start`, `run`, `pause`, `cont`, `pass`, `bench`, `fail`, `output`, `skip`) and a seven-field `TestEvent`. The installed toolchain emits more than that. Measured actions `attr` (from `t.Attr`) and `artifacts` (from `t.ArtifactDir` under `-artifacts`) appear in neither list, and they carry fields `Key`, `Value`, and `Path` that the documented struct does not declare. The emitter is `src/cmd/internal/test2json/test2json.go`, whose internal `event` struct declares all three and whose scanner recognizes `=== ATTR` and `=== ARTIFACTS`.

So a parser written against the documented action set meets values it does not know. Match on the actions you count and ignore the rest, rather than switching exhaustively and failing on an unknown one.

## Counting rule

Count `pass` events carrying a non-empty `Test`. The package-level `pass` omits `Test` and is emitted even when every test skipped, so an unqualified count of `pass` reads one on a suite that executed nothing. That single qualifier is what separates the guard from a vacuous check.
