## Runtime notes for Gemini CLI

This protocol runs in the primary session, because that is the only session Gemini grants `invoke_agent`. Gemini has no forked command context, so the session history you already have is part of this run. Start from a clean session with `/chat clear`, or invoke the pipeline as `gemini -p "/specify ..."` in a fresh process.
