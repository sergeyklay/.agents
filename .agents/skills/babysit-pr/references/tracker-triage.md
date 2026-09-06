# Tracker triage for deferred comments

The Step 4b procedure: discovering the project's tracker and the sibling skill that manages it, weighing the fix against the ticket before either, applying the three triage gates in order, and creating the ticket. Read this whenever a comment ends Step 3 in the Deferred category.

Step 4b begins with **discovery, not action**. Two discoveries happen before any ticket is created.

##### Discover the project's issue tracker

The project uses one of: GitHub Issues, Jira, GitLab Issues, Linear, or another tracker. Identify it from the strongest available signal:

1. **Project context files first.** AGENTS.md / CLAUDE.md / README.md / CONTRIBUTING.md may explicitly name the tracker - "issues live in Jira project ABC", "open a GitHub issue", a Linear board URL, a tracker-specific ticket-key convention. Trust these; they are authoritative.
2. **Repository signals second.** A GitHub remote with a `.github/` directory and an authenticated `gh` CLI suggests GitHub Issues. Atlassian URLs (`*.atlassian.net`) in commit messages, PR descriptions, or branch names suggest Jira. GitLab CI configuration and `gitlab.com` remotes suggest GitLab Issues. Treat these as evidence only when context files do not name a tracker explicitly.
3. **If ambiguous, ask the user.** Do not guess between two equally plausible trackers. State both candidates and the evidence for each, then ask which is canonical for the backlog.

##### Discover sibling skills that manage the chosen tracker

The current session loads a catalogue of skills. Inspect their descriptions for words that match the chosen tracker - typically descriptions naming the tracker, naming a ticket type, or describing operations like "create a ticket", "manage backlog", "triage issues", "manage roadmap", "manage epics". A matching skill is the *correct* tool because it carries project-specific conventions (label taxonomy, body templates, duplicate-detection logic, parent-epic resolution, custom-field handling) that hand-rolled CLI calls do not.

If a matching skill exists, load and apply it for the create operation. Pass the deferred concern with full context: the file:line being deferred, the reviewer attribution, and the gate verdicts below. Let the discovered skill handle the mechanics; this skill's job is to decide *whether* to create a ticket and *what it should contain semantically*, not to format ticket payloads.

If no matching skill exists, fall back to manual creation:

- For GitHub Issues: `gh issue create` with a clear title, a body that names the file:line and the reviewer, and labels inferred from the project's existing issue conventions (read a few existing open issues for examples).
- For Jira / GitLab / Linear: use any available API or MCP tool the session exposes. Compose the description in the project's expected markup.
- Note in the Step 6 summary that ticket creation was hand-rolled (no managing-skill found) so the human operator can verify the result against project conventions.

##### Weigh the fix against the ticket before either

A ticket is a durable artifact with a cost of its own: the prose to write it, and the re-derivation a future reader faces because the context that produced it is gone. When the change it would request is smaller than that cost, the ticket is the more expensive half of the transaction, and filing it is a net loss even though every gate below would pass.

Weigh both sides explicitly:

- **The fix.** Is the whole change a small, local edit whose correctness is evident from the diff, inside code this change already touches, and covered by the verification commands already being run?
- **The ticket.** How much of the body would restate context that exists only right now, and how much re-derivation does a future reader inherit?

When the fix is clearly the cheaper half, do not file. Propose the edit: name the file and lines, state the change in a sentence or two, give the cost comparison that justifies doing it now, and **ask the human for approval, then wait.** On approval, apply it under the boy-scout principle - leave the code better than you found it - and report it in Step 6 as Applied, noting that it was admitted here rather than filed. On refusal or silence, continue to the gates below and file as normal.

Never self-approve this path. The approval is what makes the edit part of the requested work instead of unrequested scope, which is the distinction a surgical-changes convention turns on: the edit traces to the human's decision, not to the agent's taste.

Cheapness alone does not admit an edit. File regardless of size when the change would alter behaviour a user notices, touch a security boundary, require a decision the agent cannot make, or reach code the current work does not already touch.

##### Apply the three triage gates in order

The gates validate the Deferred classification. They are not silent stops: if a gate trips, the comment was misclassified and Step 3's category was wrong. **Reclassify and continue - never leave a Deferred comment without a ticket**, unless the proportionality step above already resolved it into an approved edit.

1. **Architecture-conflict gate.** Read the relevant section of the project's architecture documentation. If the suggestion contradicts the design intent - not merely the current implementation - the comment is **Incorrect or Counterproductive (Category 5)**, not Deferred. Reclassify, cite the architecture rule as the rejection rationale, and document the reclassification in the Step 6 summary's Rejected section. Do not create a ticket.

2. **Duplicate check.** Search open tickets for existing work covering this concern, even partially. If a matching ticket exists, the Deferred classification is validated. The outcome is `{existing ticket reference} (existing)`. Do not create a new ticket.

3. **Scope test.** Would this realistically matter within the scope of the project's open milestones, epics, or roadmap?
   - **Yes** → proceed to creation.
   - **Out of current horizon, but the project has a backlog / icebox / future-ideas lane** → create the ticket in that lane. Deferred stands.
   - **Out of current horizon, with no appropriate lane** → the comment is **Needs Discussion (Category 7)**, not Deferred. Reclassify and flag for the human operator to decide whether the project should track aspirational work at all.

##### Create the ticket and verify

If gates 1 and 3 pass, create the ticket via the discovered skill (preferred) or the manual fallback. Confirm the create operation returned a ticket identifier (the tracker echoed an ID, key, or URL) - a silent failure means no ticket exists, which means the comment cannot stay in Deferred.

Record the outcome in the Step 6 summary as `{ticket reference} (created via discovered skill)` or `{ticket reference} (created via manual fallback)`. If creation failed and cannot be retried in this session, reclassify as **Needs Discussion (Category 7)** with the failure noted, and flag for the human operator to create the ticket manually.
