---
description: Fix one identified tech-debt item — a suppression, a rule, or a dependency upgrade. lead classifies the pointer, reports the blast radius, gates, and fixes it in verified batches through the lane workers, one commit per batch. A platform-scale migration gets a handoff outline instead.
---

Given `$ARGUMENTS` (the pointer, optionally with `--force`):

Launch the `crew:lead` agent (via the Agent tool, **`run_in_background: false`**) with
`$ARGUMENTS` and the instructions below. The debt lane prompts for its own gates — the slice
choice, the no-test acknowledgement, the tier-2 offer, the branch decision — and a backgrounded
agent's prompts auto-deny, which would skip them. Do not classify, edit files, or run git
yourself. If `crew:lead` cannot be launched, stop and report the exact error.

Instructions for `crew:lead`:

This is a debt pointer, in **open mode**: `$ARGUMENTS`. Load the `debt-lane` skill and follow its
open-mode flow end to end. A `--force` typed as the user's own flag skips the justification
check and changes nothing else.

When `lead` returns, relay its consolidated status to the user.
