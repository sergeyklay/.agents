## Runtime notes for Gemini CLI

This protocol runs in the primary session, because that is the only session Gemini grants `invoke_agent`. Gemini has no forked command context, so the session history you already have is part of this run. Start from a clean session with `/chat clear`, or invoke the pipeline as `gemini -p "/specify ..."` in a fresh process.

Stage agents receive `write_file` and `replace` only under approval mode `auto_edit` or wider. The installed `~/.gemini/settings.json` sets `general.defaultApprovalMode` to `auto_edit`; a run that overrides it back to `default` cannot write a spec or a plan and reports success anyway.

An automated caller must additionally pass `--output-format stream-json` and fail the run on any `tool_result` carrying `"status": "error"`, because the process exit code reports success when a stage fails. It must also clear workspace trust with `--skip-trust` or `GEMINI_CLI_TRUST_WORKSPACE=true`, or the run stops before the first model call.
