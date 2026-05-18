# My VS Code Configuration

## Global Settings

```json
{
  // ── Search ────────────────────────────────────────────────────────────────

  // I tested "auto" and "manual" and I prefer "manual" because in "auto" mode
  // I get too many irrelevant results when I search for something that is not
  // a code symbol. I prefer to have more control over when to use semantic
  // search and when not to.
  "search.searchView.semanticSearchBehavior": "manual",

  // ── Terminal settings ─────────────────────────────────────────────────────

  "terminal.integrated.automationProfile.linux": {
    "path": "/bin/bash",
    "icon": "terminal-linux",
  },

  // I use login shells in the terminal because I want to have all my environment
  // variables, PATH modifications, and other configurations that are set in my
  // shell's login files. Yes, it a bit slower to start, but I prefer having the
  // full environment available and tools like asdf, which are configured in
  // ~/.profile, ~/.bashrc, etc. work correctly in VSCode terminal.
  "terminal.integrated.profiles.linux": {
    "bash (login)": {
      "path": "/bin/bash",
      "args": ["-l"],
      "icon": "terminal-linux",
    },
  },
  "terminal.integrated.defaultProfile.linux": "bash (login)",

  // ── Git ─────────────────────────────────────────────────────────────────── 

  "scm.defaultViewMode": "tree",

  "git.confirmSync": false,
  "git.openRepositoryInParentFolders": "never",
  "git.closeDiffOnOperation": true,
  "git.enableSmartCommit": false,

  // ── Chat Settings ─────────────────────────────────────────────────────────

  // Automatically add instruction files referenced via Markdown links to chat requests.
  "chat.includeReferencedInstructions": true,

  // Enable the use of AGENTS.md file for agent configuration including nested agents. See:
  // - https://code.visualstudio.com/docs/copilot/customization/custom-instructions#_use-an-agentsmd-file
  // - https://agents.md
  "chat.useAgentsMdFile": true,

  // Enable the use of CLAUDE.md file for agent configuration. See:
  // - https://code.visualstudio.com/docs/copilot/customization/custom-instructions#_use-a-claudemd-file
  "chat.useClaudeMdFile": true,

// Note: As of 13 January 2026 this feature is in Experimental stage.
  "chat.useNestedAgentsMdFiles": true,

  // ── Agent Configuration ───────────────────────────────────────────────────

  // Increase the maximum number of requests an agent can make in a single session.
  // Default is usually 25.
  "chat.agent.maxRequests": 250,

  // Enable the use of agent skills: https://agentskills.io
  // Note: As of 13 January 2026 this feature is in Experimental stage.
  "chat.useAgentSkills": true,
  "chat.experimental.useSkillAdherencePrompt": true,

  "chat.unifiedAgentsBar.enabled": true,
  "chat.restoreLastPanelSession": true,
  "chat.viewProgressBadge.enabled": true,
}
```
