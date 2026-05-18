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

}
```
