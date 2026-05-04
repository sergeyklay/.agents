---
description: "Use the toolchain the project already pins; detect runtime, package manager, and scripts before acting."
applyTo: "**/*.{ts,tsx,mjs,cjs,js,jsx},**/package.json,**/package-lock.json,**/yarn.lock,**/pnpm-lock.yaml,**/bun.lock,**/bun.lockb"
---

# Node Toolchain

Each TS/JS project pins its own runtime and package manager. Detect them; never substitute.

## Detect

**Package manager**: `package.json#packageManager` first; otherwise the lockfile present in the repo root.

| File | Manager |
|---|---|
| `package-lock.json` | npm |
| `pnpm-lock.yaml` | pnpm |
| `yarn.lock` | yarn |
| `bun.lock` / `bun.lockb` | bun |

Multiple lockfiles indicate misconfiguration — flag it, do not pick one. Never mix managers in a repo.

**Runtime version**: first file present — `.tool-versions`, `.nvmrc`, `.node-version`, or `engines.node` in `package.json`. Match exactly. Do not switch the active version manager (asdf / nvm / fnm / volta / mise).

## Activate

Coding-agent shells often start without the version-manager hook loaded, so `node` and `npm` silently resolve to a system-wide binary on the wrong version. Before running any command, check `node --version` against the pin. If they disagree, do not proceed on the bare PATH — invoke through the manager:

- **Shim-based** (asdf, mise, proto, volta): use the shim path. Shims re-read the pin file on every call.
  - `~/.asdf/shims/<bin>` (asdf)
  - `~/.local/share/mise/shims/<bin>` (mise)
  - `~/.proto/shims/<bin>` (proto)
  - `~/.volta/bin/<bin>` (volta)
- **Hook-based** (nvm, fnm): use the exec subcommand — `nvm exec <version> <bin>` or `fnm exec --using=<version> <bin>`. Shell-activation `nvm use` does not survive across tool calls.

Never reference absolute system paths (`/usr/bin/node`, `/usr/local/bin/npm`).

## Run

Use scripts from `package.json#scripts` via the detected manager: `npm run <name>` / `pnpm <name>` / `yarn <name>` / `bun run <name>`. Reach for `npx` / `pnpm dlx` / `yarn dlx` / `bunx` only when the tool is genuinely not wrapped by a script.

## Lockfile

- CI and Docker: install from lockfile only — `npm ci`, `pnpm install --frozen-lockfile`, `yarn install --immutable`, `bun install --frozen-lockfile`.
- Outside CI: do not run mutating `install` unless the dependency change is intentional or explicitly approved/asked by the user.
- Never run `audit fix --force` (or its analogues).

## CI and Dockerfiles

Pin Node.js to the version declared in the project's runtime file. No `latest`, no unversioned base images. Do not reference absolute paths to `node` or the manager binary — let the user's PATH or version manager resolve.
