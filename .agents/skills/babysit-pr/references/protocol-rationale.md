# Protocol rationale

The nine principles the protocol's rules follow from. Read this when a rule above and the situation in front of you seem to disagree.

## Reading project context

Project context (AGENTS.md, CLAUDE.md, architecture documentation) is reference material consulted *while* walking through this skill's steps - not a prerequisite to read end-to-end before starting. If a wrapper prompt that invoked this skill lists its own prerequisite reading, honor those reads first; the wrapper has authority to add such a gate. The "not a prerequisite" rule applies only to the project context files named here - it is not a blanket prohibition against preliminary reading the wrapper requires.

## Guiding principles

1. **Library claims are falsifiable.** A reviewer asserting an API behavior is making a verifiable claim. Context7 verifies it. Accepting or rejecting without verifying is the root cause of both false approvals and false rejections.
2. **Quality over harmony.** Never apply a change that makes the work worse, regardless of who suggested it or how confidently.
3. **Architecture wins over library capability.** When the project's architecture documentation and Context7 conflict, architecture wins. Context7 describes what a library *can* do; architecture specifies what the project *will* do.
4. **Spec-first, code-second.** For architecture-domain feedback, the specification is the source of truth; code follows. Revising code without revising the spec is drift.
5. **Think like a maintainer, not a people-pleaser.** The goal is not to mark every comment resolved. The goal is to ship correct, maintainable work.
6. **Be thorough but surgical.** Apply the minimum change that fully addresses the concern. Every changed line must trace to a classified comment.
7. **Every decision needs evidence.** Document reasoning, source, and conclusion for every apply, skip, or reject. Assertions without citations are opinions.
8. **Defer wisely, not reflexively.** "Not now" is only valid when paired with a tracked ticket - Deferred ↔ ticket, regardless of which tracker the project uses. A deferred comment without a ticket reference is forbidden: it is a promise the agent has no way to keep. If Step 4b cannot produce a ticket, the comment was misclassified; move it to Rejected or Needs Discussion.
9. **A ticket is not free.** Its prose and the re-derivation it imposes on a future reader are the price of deferring. When that price exceeds the change itself, the honest move is to propose the edit, argue the cost, and let the human decide - not to file, and not to act unilaterally.
