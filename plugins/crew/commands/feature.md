---
description: Plan and execute a feature through the lead orchestration flow
---

Given `$ARGUMENTS` (ticket ID, task description, or free-form requirement):

Delegate the entire feature to the orchestrator: launch the `crew:lead` agent
(via the Agent tool) with `$ARGUMENTS` and the instructions below. Do **not** plan,
explore, edit files, run git, or delegate to workers yourself — `lead` owns the
plan, the feature branch, and every worker delegation. If `crew:lead` cannot be
launched, stop and report the exact error; do not improvise the flow inline.

Instructions for `crew:lead`:

The feature request is: `$ARGUMENTS`. Follow your own standard flow end to end — resume
a matching in-flight plan per your durable-resume protocol, or otherwise explore, write
the plan, run the plan checkpoint, delegate, verify, and run the review gate — then
return your consolidated status and run summary.

When `lead` returns, relay its consolidated status to the user verbatim.

**When this session is in plan mode**, `lead` runs as a subagent in plan mode too: it can
explore, but it can neither write its plan file nor present a plan for approval (a subagent has no
`ExitPlanMode`), and the `plan-guard` hook refuses every editing worker it would dispatch. So run
the flow in two launches, passing the plan between them as data:

1. Launch `crew:lead` with `$ARGUMENTS` and, in place of the instructions above: *this session
   is in plan mode — explore, run any read-only triage, and return the plan you would present at
   your checkpoint (scope, the ordered steps with acceptance criteria, the resolved base branch
   and frontend mode, assumptions). Write nothing and dispatch no writer.*
2. Present the returned plan for approval through plan mode's own flow (`ExitPlanMode`), verbatim.
   If the user keeps planning, re-launch `crew:lead` with the draft plan and their correction,
   and present the revision the same way.
3. Once approved, launch `crew:lead` again with `$ARGUMENTS`, the approved plan verbatim, and
   the note that plan mode approved it: it writes `<plan-dir>/plan-<feature>.md` from it and runs
   the rest of its standard flow without a second checkpoint.

Never leave plan mode yourself to get around this, and never run the plan checkpoint twice.
