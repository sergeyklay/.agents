# Agent Toolchain Source

Every skill, command, rule, hook, and context file this agent loads is installed content. The canonical source for all of it is the repository at `~/work/.agents`, and it is the only place any of it may be changed.

## Why this exists

One source installs into five host directories: `$HOME/.claude`, `$HOME/.codex`, `$HOME/.copilot`, `$HOME/.gemini`, and `$HOME/.config/opencode`. A skill fixed once is fixed for every host and every project.

The cost of that design is a trap. The installed copies are ordinary readable files in obvious places, so editing one looks like the direct fix. It is not: the next installer run overwrites it, the other four hosts never receive it, and nothing reports either outcome. The edit simply disappears, usually long after the session that made it ended.

## Never

- **Never edit an installed copy.** `$HOME/.claude`, `$HOME/.codex`, `$HOME/.copilot`, `$HOME/.gemini`, and `$HOME/.config/opencode` are install destinations, not sources. This includes `~/.claude/skills/`, `~/.claude/rules/`, `~/.claude/commands/`, and the host context files. Change the source and reinstall.
- **Never put a project-specific fact into anything tracked there.** Everything in that repository installs into every project on the host, so a repository or service name, a schema, a port, a ticket prefix, or a team convention belongs in that project's own context file instead. A worked example that invents a product is fine; a worked example lifted verbatim from a real codebase is not.
- **Never run destructive git commands in that checkout.** It is shared with parallel sessions, and `git checkout --`, `git restore`, `git reset --hard`, `git stash`, and `git clean` destroy their uncommitted work.

## What belongs there

Only what is useful to every project on the host: agent skills, slash commands, cross-project rules, hooks, and the shared working agreement.

Anything true of one repository belongs in that repository's own `CLAUDE.md` or `AGENTS.md`. Anything true of one ticket belongs in the ticket. The test is whether a reader working on an unrelated project would be helped or confused by the sentence.

## How to change it

1. Read `~/work/.agents/AGENTS.md` first. It is repo-local, it is not distributed, and it carries the current gotchas and boundaries. This rule does not replace it.
2. Take a worktree off `main`: `git worktree add -b <branch> <dir> main`. One agent per worktree, and it owns that worktree alone. Treat every other checkout as read-only.
3. Edit under `.agents/`. Host-specific differences go in `templates/`, and only differences; canonical content is never duplicated there.
4. Stage by name, `git add <path>`. Never `git add -A`.
5. Run `make validate` after changing a skill, and `make check` before finishing. `make check` runs every CI gate locally.
6. Write scratch files to `.scratch/<task>/`, and delete that subdirectory when finished.
7. Commit with Conventional Commits, scoped to the skill or area, then open a PR. Do not merge or push to `main` unless asked.

## Gotchas the gates will not catch

- The file-selecting gates read `git ls-files`. An untracked file is skipped silently and the gate still exits `0`, so stage a new file before believing any green.
- The skill size ceiling applies to the `SKILL.md` body, not to the file: frontmatter is excluded before the body is measured. A skill near the limit fails on the next contributor's change, not on the one that consumed the headroom.
- No gate checks for project-specific facts, personal information, or a real codebase's internals leaking into a skill or its assets. That audit is manual, and it is required before opening a PR.
- Editing the source does not update the installed copies. The running session keeps using the old content until the installer runs again.
