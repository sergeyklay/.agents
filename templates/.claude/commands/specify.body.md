## Delegation primitive

Every subagent invocation uses the `Agent` tool with the appropriate `subagent_type` (`architect`, `arch-review`, `planner`). The `Agent` tool was previously called `Task` in older Claude Code releases and may still be referenced that way in some documentation; do not look for a `Task` tool in your toolbox - it does not exist in current Claude Code versions. The task-list tools `TaskCreate` / `TaskUpdate` / `TaskGet` / `TaskList` are separate from `Agent` and were previously called `TodoWrite`.

Omit the `name` parameter on every `Agent` call: pass `subagent_type` and the prompt only. These subagents never message each other, so a name buys nothing, and with agent teams enabled a named spawn is registered as a team member - which cannot spawn further agents and fails this pipeline at its next delegation.

## Specification Request

$ARGUMENTS
