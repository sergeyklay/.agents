---
description: Run the full specification pipeline - specify, review, revise, and plan - in a single automated step
---

Your task is to run the complete specification pipeline for the request below.

The pipeline:

1. **Assesses the input** - determines the route (tracker-driven, description-driven, review-driven, revise-driven, or plan-already-exists) and selects the appropriate skip path
2. **Specifies** - delegates to the architect agent, which loads the `writing-specs` skill and grounds the spec in project context
3. **Reviews** - delegates to the arch-review agent, which loads the `review-spec` skill and emits a machine-readable Subagent Return Line
4. **Revises if needed** - severity-gated: Significant-only findings trigger one revision; Critical findings enter a Critical Resolution Loop with up to two re-review cycles, then halt if unresolved
5. **Plans** - delegates to the planner agent, which loads the `writing-plans` skill and produces an atomic, layer-aware plan

Follow your protocol strictly. Do not skip any phase. Track progress with the todo list.
