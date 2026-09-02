# Per-ecosystem commands

Three operations in the vetting procedure differ per ecosystem. Everything else in SKILL.md is the same everywhere.

| Operation | Used by | What it answers |
|---|---|---|
| Resolve package to repository | Step 0, gating steps 1-3 | Which repository do the maintenance signals describe |
| Obtain the published artifact | Step 4 | What do consumers actually link against |
| Isolated probe | Step 5 | What does the library do with this project's input |

## Contents

- Go
- npm
- PyPI
- Cargo
- Maven and Gradle
- An ecosystem not listed here
- Verification status

## Go

Resolution is usually free because the module path is the repository path, and the artifact equals the repository tree at the tag because the module is served from version control. Both properties fail on the cases below.

```bash
# resolve: a vanity path is not the repository
curl -sS "https://golang.org/x/sync?go-get=1" | grep -o '<meta name="go-import"[^>]*>'
# -> <meta name="go-import" content="golang.org/x/sync git https://go.googlesource.com/sync">

# versions and publication dates
curl -sS "https://proxy.golang.org/github.com/pkg/errors/@v/list" | sort -V | tail -3
curl -sS "https://proxy.golang.org/github.com/pkg/errors/@v/v0.9.1.info"
# -> {"Version":"v0.9.1","Time":"2020-01-14T19:47:44Z"}

# artifact
curl -sSO "https://proxy.golang.org/<escaped-module>/@v/<version>.zip"

# probe
d=$(mktemp -d) && cd "$d" && go mod init probe && go get MODULE@VERSION && go run .
```

**Uppercase must be escaped in proxy paths.** Each uppercase letter becomes `!` plus its lowercase form. `https://proxy.golang.org/github.com/BurntSushi/toml/@v/list` returns 404; `.../github.com/!burnt!sushi/toml/@v/list` returns the version list. A 404 here is an encoding bug, not an absent module.

**A vanity path can host outside a forge.** `golang.org/x/*` resolves to `go.googlesource.com`, which has no pull request queue. Step 2 is unavailable and the verdict must say so rather than silently omitting it.

## npm

The published tarball is a build product. Never read the git tag as the contract.

```bash
# resolve
curl -sS "https://registry.npmjs.org/PACKAGE" | jq -r '.repository.url'
# -> git+https://github.com/microsoft/TypeScript.git   (typescript)
# -> git+ssh://git@github.com/stevemao/left-pad.git    (left-pad)

# artifact
npm pack PACKAGE@VERSION && tar -tzf PACKAGE-VERSION.tgz

# probe
d=$(mktemp -d) && cd "$d" && npm init -y >/dev/null && npm i PACKAGE@VERSION
# write probe.mjs feeding the project's own input class, then:
node probe.mjs
```

**`repository.url` needs normalizing before it is a forge address.** Observed forms include `git+https://github.com/OWNER/REPO.git` and `git+ssh://git@github.com/OWNER/REPO.git`; the shorthand `github:OWNER/REPO` and a bare URL are also legal. Strip the `git+` prefix and the `.git` suffix, and convert the `ssh` form, before passing it to a forge API.

**A monorepo package points at the repository root.** `repository.directory` names the subdirectory when the publisher set it; without it, steps 1-3 measure the whole monorepo and the queue depth belongs to every package in it, not to this one. Say which.

## PyPI

```bash
# resolve
curl -sS "https://pypi.org/pypi/PACKAGE/json" | jq -c '.info.project_urls'
# -> {"Documentation":"https://requests.readthedocs.io","Source":"https://github.com/psf/requests"}
# -> {"Homepage":"https://github.com/benjaminp/six"}
# -> {"Changelog":"...","Code":"https://github.com/urllib3/urllib3","Documentation":"...","Issue tracker":"..."}

# artifact: wheel is what most consumers install
pip download --no-deps --dest . PACKAGE==VERSION
# artifact: sdist requires the flag
pip download --no-deps --no-binary :all: --dest . PACKAGE==VERSION

# probe
d=$(mktemp -d) && cd "$d" && python3 -m venv .venv && .venv/bin/pip install -q PACKAGE==VERSION
.venv/bin/python probe.py
```

**`project_urls` has no fixed schema.** The repository has been observed under `Source`, `Homepage`, and `Code` across three widely used packages. Do not read a single key. Scan the values for a forge host, and when several disagree, prefer the one whose path is a repository over one that is a documentation site.

**Wheel and sdist are different trees.** A wheel carries installed layout, an sdist carries packaging inputs, and neither is the git tag. Read whichever one the project's installer will actually resolve.

## Cargo

```bash
# resolve: crates.io requires a User-Agent
curl -sS -H "User-Agent: <project-or-contact>" "https://crates.io/api/v1/crates/CRATE" \
  | jq -c '{repo: .crate.repository, newest: .crate.newest_version}'
# -> {"repo":"https://github.com/serde-rs/serde","newest":"1.0.229"}

# artifact, and the exact commit it was cut from
curl -sSL -H "User-Agent: <project-or-contact>" \
  -o CRATE.crate "https://crates.io/api/v1/crates/CRATE/VERSION/download"
tar -xzf CRATE.crate CRATE-VERSION/.cargo_vcs_info.json && cat CRATE-VERSION/.cargo_vcs_info.json
# -> {"git":{"sha1":"7fc3b4c30c94f73a96ebd1553f2b090d928fc3a8"},"path_in_vcs":"serde"}

# probe
d=$(mktemp -d) && cd "$d" && cargo new probe && cd probe && cargo add CRATE@VERSION && cargo run
```

**A missing `User-Agent` returns HTTP 403 with an empty body.** `curl` without `-f` exits 0, so a pipeline reads the empty response as "no such crate". Send the header and check the status code.

**`.cargo_vcs_info.json` beats the repository field.** It records the exact commit the artifact was published from, and `path_in_vcs` names the subdirectory inside a workspace. That is a stronger join than a URL a maintainer typed into `Cargo.toml`, and it also detects an artifact published from an unpushed tree, where the field is absent.

## Maven and Gradle

Both resolve from the same repositories, so the commands are identical; only the manifest the consuming project edits differs.

```bash
# find published versions
curl -sS "https://search.maven.org/solrsearch/select?q=g:GROUP+AND+a:ARTIFACT&core=gav&rows=5&wt=json" \
  | jq -c '.response.docs[] | {g,a,v}'

# artifact POM: group dots become path separators
curl -sSf "https://repo1.maven.org/maven2/com/google/code/gson/gson/2.11.0/gson-2.11.0.pom" -o pom.xml

# resolve: scm is frequently inherited, and the tag carries attributes
grep -nE "<scm[ >]|<parent>|<connection>" pom.xml
# gson-2.11.0.pom declares <parent>gson-parent</parent> and no scm at all
curl -sSf "https://repo1.maven.org/maven2/com/google/code/gson/gson-parent/2.11.0/gson-parent-2.11.0.pom" \
  | grep -E "<connection>|<url>" | head -3
# -> <url>https://github.com/google/gson</url>
# -> <connection>scm:git:https://github.com/google/gson.git</connection>

# contract: the published jar, obtainable without a Maven install
curl -sSf "https://repo1.maven.org/maven2/com/google/code/gson/gson/2.11.0/gson-2.11.0.jar" -o a.jar
unzip -l a.jar | grep -E "module-info|MANIFEST"
# -> META-INF/MANIFEST.MF, com/google/gson/Gson.class, META-INF/versions/9/module-info.class (244 entries)

# probe
mvn dependency:get -Dartifact=GROUP:ARTIFACT:VERSION
# then a scratch pom declaring the single dependency, or jshell --class-path against the resolved jar
```

**`grep '<scm>'` is a false negative.** The real element in `gson-parent-2.11.0.pom` opens as `<scm child.scm.url.inherit.append.path="false" ...>`, which the literal pattern misses. Match `<scm[ >]`.

**Resolve `<parent>` before concluding a project declares no repository.** The artifact's own POM commonly carries only coordinates and dependencies; `<scm>`, `<url>`, and `<issueManagement>` live one or more levels up.

**The jar is the contract, not the sources jar.** A `-sources.jar` is optional and may lag. Read the published jar, or the `module-info` and public signatures inside it.

## An ecosystem not listed here

Answer the three questions the table above asks, in this order, before running any forge command:

1. **Is the package identity the repository identity?** Only Go's module path is. Everywhere else, find the registry's metadata endpoint and read whatever repository field it carries, then treat that field as a claim: follow it, confirm it resolves, and record it.
2. **Is the published artifact the repository tree at the tag?** Assume no wherever a build, transpile, or packaging step exists. Download the artifact the installer resolves and read that. Where the registry publishes provenance (a recorded commit, a build attestation), prefer it over a self-declared URL.
3. **Can the probe run without touching the project?** Every package manager has a way to install into a throwaway directory or virtual environment. Use it; never add a candidate to the project's manifest to test it.

## Verification status

Every command in the Go, npm, and PyPI sections, plus every `curl` in the Cargo and Maven sections, was executed on 2026-09-02 and the quoted output is verbatim. `cargo new`, `cargo add`, `cargo run`, and `mvn dependency:get` were not executed here; their syntax comes from `doc.rust-lang.org/cargo/commands/cargo-add.html` and `maven.apache.org/plugins/maven-dependency-plugin/get-mojo.html`. Version numbers in the examples are the ones that were current when the command ran, not recommendations.
