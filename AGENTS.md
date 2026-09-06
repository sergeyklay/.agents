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

## Boundaries

These constraints protect canonical source files and installed host views.

### Always

- Keep behavior shared by hosts in `.agents/`; add host-specific frontmatter or prompt fragments only in `templates/`.
- Run `make validate` after changing a skill.
- Follow the surrounding style. Do not refactor adjacent legacy content without a separate task.

### Ask first

- Changes to host-wide settings in `.claude/`, `.gemini/`, or `.opencode/`.
- Installer destinations or stale-file migration behavior.
- Canonical skill content, its validators, or vendor templates.

### Never

- Edit installed files under `$HOME` as a substitute for updating this source repository.
- Copy a path-scoped Claude rule into OpenCode's global rules.
