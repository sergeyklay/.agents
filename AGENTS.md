# .agents

`.agents/` is the canonical source. `templates/` may contain only host-specific differences; do not duplicate canonical content there.

## Commands

- Before finishing any change: `make check` (runs every CI gate from ci.yml locally)
- After changing `scripts/install.sh` or installer behavior: `bats test/`
- Before finishing a shell-script change: `shfmt -d scripts`
- Before finishing an installer change: `shellcheck scripts/install.sh`

Run `asdf install shfmt` or `asdf install bats` when a tool is unavailable.

## Gotchas

- The installer skips a host whose root directory does not exist; inspect its output.
- `--rules` does not remove stale destination files. Legacy Working Agreement cleanup happens only after a successful `--context` installation.
- A Claude `paths` overlay marks a rule that must not become an OpenCode global instruction.
- `--context` overwrites the host-native context file and removes only legacy rules that match the canonical content.
- `lint`, `typecheck` and the other file-selecting gates read `git ls-files`; an untracked file is skipped silently and the gate can still exit 0. Stage it first.
- Everything tracked under `.agents/skills/` ships to five host directories; keep tests and fixtures in `test/`, which ships nowhere.
- `make validate` applies its 17,500-byte ceiling to the skill body, not to `SKILL.md` as a file: `split_frontmatter` hands `_check_body` only the text after the closing `---`. No gate lints a skill as Markdown either; `lint-markdown` selects `README.md` and `docs/`.

## Boundaries

These constraints protect canonical source files and installed host views.

### Always

- Keep behavior shared by hosts in `.agents/`; add host-specific frontmatter or prompt fragments only in `templates/`.
- Run `make validate` after changing a skill.
- Follow the surrounding style. Do not refactor adjacent legacy content without a separate task.
- Give each agent its own worktree off `main`: `git worktree add -b <branch> <dir> main`. One agent per worktree, and it owns that worktree alone.
- Treat every other checkout of this repository as read-only, including the one the brief was written from.
- Write scratch files to `.scratch/<task>/`, which is git-excluded and scoped to one session. Delete your own subdirectory when you finish, and move anything that must outlive the task into `.tasks/`.
- Stage a new file with `git add <path>` before running any gate, for the reason under Gotchas: the file-selecting gates read `git ls-files`, skip an untracked file, and still exit 0.
- Run a negative control before reporting any green. `prove-checks` owns what that requires.
- Land a delegate's branch only in the form you were asked for. Verification finishes the work; it does not authorize merging, pushing, or opening a PR. When the form was not named, ask before the branch moves anywhere.

### Ask first

- Changes to host-wide settings in `.claude/`, `.gemini/`, or `.opencode/`.
- Installer destinations or stale-file migration behavior.
- Canonical skill content, its validators, or vendor templates.
- Any write outside the assigned worktree.

### Never

- Edit installed files under `$HOME` as a substitute for updating this source repository.
- Copy a path-scoped Claude rule into OpenCode's global rules.
- Run the destructive git commands the Working Agreement lists under "Surgical Changes". In a shared checkout they destroy a parallel session's uncommitted work.
- Write into an installed host directory. `sync_context` in `scripts/install.sh` names them: `$HOME/.claude`, `$HOME/.codex`, `$HOME/.copilot`, `$HOME/.gemini`, `$HOME/.config/opencode`.
- Revert or reformat a change you cannot trace to your own brief.
