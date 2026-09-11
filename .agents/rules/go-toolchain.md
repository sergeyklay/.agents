
# Go Toolchain

Go carries its version in two places at once: the pin the project declares, and the `GOROOT` the shell exports. When those disagree the build still starts. Detect both; never substitute.

## Detect

**Version pin**: first file present - `.tool-versions`, the `toolchain` directive in `go.mod`, the `go` directive in `go.mod`, `.go-version`. Match exactly. Do not switch the active version manager (asdf / mise / goenv).

## Activate

`go` on a bare PATH is usually a shim that re-reads the pin on every call, and that is the right way to invoke it (`~/.asdf/shims/go`, `~/.local/share/mise/shims/go`). A shim resolves the pin from the working directory, so run every one of these commands from inside the repository. The same command in a temporary directory reports whatever the home pin says.

An exported `GOROOT` overrides the shim only in part: the shim still dispatches to the pinned `go` binary, while the compiler, linker and standard library come from the tree `GOROOT` names. A shell that exports it from an older install therefore fails every build, and the message names the split:

```
compile: version "go1.26.1" does not match go tool version "go1.26.2"
```

Clear it and let the shim resolve, or point it at the install that carries the pin. Do it once for the whole session, not per command. `GOPATH` and `GOBIN` inherited from that same older install do not cause this failure, but they aim the module cache and `go install` at the wrong tree, so clear all three together.

```
unset GOROOT GOPATH GOBIN
```

Never reference an absolute system path (`/usr/bin/go`, `/usr/local/go/bin/go`).

## Verify before measuring

`go version` reports the `go` binary the shim chose. It does not report the toolchain that compiles, and the two disagree exactly when `GOROOT` is stale, which is the case worth catching. Read the compiler back instead:

```
go env GOROOT GOVERSION GOTOOLDIR
"$(go env GOTOOLDIR)/compile" -V=full
```

`GOROOT` and `GOTOOLDIR` must sit inside the install that carries the pin, and `compile -V=full` must name the pinned version. `GOVERSION` does not settle it on its own: it follows the `go` binary, so it reads correct while the compiler underneath is a different release.

A number measured before this read-back belongs to an unknown toolchain. Re-measure it; do not reconcile it.
