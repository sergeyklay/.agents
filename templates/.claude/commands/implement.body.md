## Delegation primitive

Every subagent invocation uses the `Agent` tool with the appropriate `subagent_type` (the implementation subagent, the tester subagent, or any specialized subagent the project ships). The `Agent` tool was previously called `Task` in older Claude Code releases and may still be referenced that way in some documentation; do not look for a `Task` tool in your toolbox - it does not exist in current Claude Code versions. The task-list tools `TaskCreate` / `TaskUpdate` / `TaskGet` / `TaskList` are separate from `Agent` and were previously called `TodoWrite`.


## Implementation Request

$ARGUMENTS
