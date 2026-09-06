# Project constants

How to detect each of the seven constants `SKILL.md` requires, and what to fall back to when the first probe fails. Read this at the start of a changelog session, before Step 1 of the workflow.

1. **GitHub repository slug (`OWNER/REPO`).** Read existing comparison links at the bottom of CHANGELOG.md (preferred). Fall back to `git remote get-url origin` and parse the slug from the URL.
2. **Issue tracker.** Look for tracker references in existing CHANGELOG entries, PR templates, contributing docs, and recent commit messages:
   - **GitHub Issues** - links of the form `https://github.com/OWNER/REPO/issues/NNN`, or closing keywords `closes/fixes/resolves #NNN` in commit/PR bodies.
   - **Jira** - task keys of the form `[A-Z]+-[0-9]+` (e.g. `ABC-123`) or links to `*.atlassian.net/browse/...`.
   - **Linear** - keys like `ENG-123` or links to `https://linear.app/...`.
   - **Other trackers** - distinct ID schemes or links in commit/PR bodies.

   For non-GitHub trackers, also detect the tracker base URL and the project key prefix (e.g. `BP`, `ABC`, `ENG`).
3. **Subsystem labels.** Read existing CHANGELOG entries to learn which subsystem prefixes the project already uses (e.g. `API:`, `CLI:`, `Auth:`). If none exist, propose labels that match the project's top-level directory or package layout. The human reviewer will correct any that are wrong.
4. **Entry unit.** Count tracker references per bullet in the newest released section to learn whether the project groups distinct but related user-facing changes by epic, milestone, or roadmap checkpoint. This convention controls whether separate logical changes may share a bullet; it never splits one logical change by PR, commit, or implementation task.
5. **Bullet order within a category.** Keep a Changelog fixes the order of versions and categories but says nothing about bullets inside a category, so every project has its own convention. Recover it from git rather than guessing: for three or four bullets in the newest released section, run `git log --format='%h %ai %s' -S'<key unique to that bullet>' -- CHANGELOG.md | tail -1` to find the commit that *added* it. Descending timestamps down the section mean newest-first (prepend); ascending mean oldest-first (append). Default to newest-first when the file is new or the signal is mixed - it matches the reverse-chronological rule the file already applies to versions.
6. **Audience.** Decide who reads the file: operators and consumers of a distributed artifact (published package, self-hosted service, OSS release), or an internal team plus non-technical stakeholders such as a client, manager, or leadership. This governs whether deploy mechanics belong in an entry at all - see Step 4. Detect it from the project's distribution setup (release workflow, package manifest, install docs); ask once if that is inconclusive.
7. **Product surface.** Detect whether the project ships an application, CLI, service, library, or framework from its install and usage documentation. In applications, CLIs, and services, implementation types, functions, modules, protocol states, and internal error taxonomies are not user-facing merely because they have names. In libraries and frameworks, include a symbol only when it is part of the supported public API.
