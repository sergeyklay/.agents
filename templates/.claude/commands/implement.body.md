## Delegation primitive

Every subagent invocation uses the delegation tool with the appropriate `subagent_type` (the implementation subagent, the tester subagent, or any specialized subagent the project ships). That tool is named `Agent` in an interactive Claude Code session and `Task` in the headless runtime (`claude -p`, Agent SDK). Read your toolbox and call whichever of the two is actually present; do not assume a particular name and do not conclude the other one is missing. The task-list tools `TaskCreate` / `TaskUpdate` / `TaskGet` / `TaskList` are a separate todo mechanism, not delegation, and were previously called `TodoWrite`.

Omit the `name` parameter on every delegation call: pass `subagent_type` and the prompt only. These subagents never message each other, so a name buys nothing, and with agent teams enabled a named spawn is registered as a team member - which cannot spawn further agents and fails this pipeline at its next delegation.


## Implementation Request

$ARGUMENTS
