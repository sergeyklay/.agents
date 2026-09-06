# What belongs in a changelog

The include, exclude, and edge-case signals behind Step 3 of `SKILL.md`. Read this before drafting, and again for any change whose relevance to a consumer is not obvious.

**ALWAYS include:**

| Signal                                                                                     | Why it matters to consumers           |
| ------------------------------------------------------------------------------------------ | ------------------------------------- |
| New user-facing feature (CLI flag, integration, config option, API surface, UI capability) | Consumers discover new capabilities   |
| Changed behavior of existing feature                                                       | Consumers must adjust usage           |
| Bug fix for incorrect behavior                                                             | Consumers know issues are resolved    |
| Security or vulnerability fix                                                              | Operators must act on upgrades        |
| Deprecation of public interface                                                            | Consumers prepare for removal         |
| Removal of feature or public interface                                                     | Consumers must adapt before upgrading |
| Performance improvement with measurable impact                                             | Consumers benefit from upgrading      |
| New or changed persistence schema (migration)                                              | Operators plan upgrade procedures     |
| Changed CLI flags, env vars, deployment, or config file format                             | Operators must update deployment config |

**NEVER include - these are noise, not signal:**

| Noise                                                     | Why it does not belong                |
| --------------------------------------------------------- | ------------------------------------- |
| Internal variable/function/type renames                   | No observable effect on consumers     |
| Code formatting, whitespace, linting fixes                | No observable effect on consumers     |
| Test-only changes (new tests, test refactors)             | Not shipped to consumers              |
| CI/CD pipeline changes (workflows, actions)               | Not shipped to consumers              |
| Dotfile changes (`.gitignore`, `.github/*`, `CODEOWNERS`) | Not shipped to consumers              |
| Documentation-only changes (README, CLAUDE.md, AGENTS.md, comments)  | Not shipped to consumers              |
| Merge commits                                             | Infrastructure artifact, not a change |
| Internal refactoring with no behavior change              | No observable effect on consumers     |
| Dev-only dependency bumps                                 | Not shipped to consumers              |
| Project scaffolding and repo housekeeping                 | Not shipped to consumers              |

**Edge cases - include only when the threshold is met:**

| Change                         | Include when...                                                  | Omit when...                            |
| ------------------------------ | ---------------------------------------------------------------- | --------------------------------------- |
| Dependency bump                | Major version, security fix, or changed behavior                 | Routine patch/minor with no user impact |
| Refactoring                    | It changes observable performance, error messages, or log output | Purely internal restructuring           |
| New internal module/package    | It introduces a new adapter or public API surface                | It reorganizes existing code            |
| ADR or architecture doc update | It records a decision that changes system behavior               | It clarifies existing behavior          |
