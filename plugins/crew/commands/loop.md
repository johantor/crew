---
description: Outer-loop driver — re-invoke lead across runs on the native /loop until the plan's exit conditions are met (dynamic, self-paced)
---

Given `$ARGUMENTS` (a feature goal — ticket ID, task, or free-form requirement):

Drive the feature to completion across multiple `lead` runs, so work that outlives one
run's `maxTurns` finishes without you re-asking each time. Each tick you launch the
`crew:lead` agent **directly** (the same agent `/crew:feature` launches) — not by nesting
`/crew:feature`, which only forwards the goal and can't tell `lead` a loop is driving it.
This wrapper is the **outer loop**; it lives at the **main-session** level and owns all
scheduling. `lead` never self-schedules — you re-invoke it, one tick at a time, on the
harness's native `/loop` in **dynamic (self-paced) mode**. The durable
`<plan-dir>/plan-<feature>.md` (the `Plan directory` crew-config slot, or `.claude/` when
unset) is the only cross-tick state — no new files, no background daemon.

Run this **foreground** so tick 1's plan checkpoint can prompt.

**Not in plan mode.** Every tick writes the plan file and dispatches editing workers, and plan
mode refuses both (the `plan-guard` hook blocks the dispatch). If the session is in plan mode,
stop and say so — approve a plan through `/crew:feature`, or leave plan mode (Shift+Tab), then
start the loop. No tick ran, so write nothing.

**Start a native `/loop` in dynamic (self-paced) mode wrapping the per-tick logic below** — that
harness loop is what re-fires each tick and lets the work span `lead` runs. Without it you'd
run a single tick and exit, defeating the command. The per-tick logic decides, each firing,
whether to schedule the next wakeup or end.

## Per-tick logic

**Iteration cap syntax.** `$ARGUMENTS` may end with a `max=<n>` token (e.g.
`/crew:loop add SSO login max=5`) — honored **only** when `<n>` is a positive integer, then
stripped; the rest is **`<goal>`** (referred to below), the task handed to `lead`. A trailing
`max=` that isn't a positive integer (`max=0`, `max=-1`, `max=abc`, empty) is **not** treated as
the cap flag — leave it as part of `<goal>`, don't guess. Absent a valid token, `<max>` defaults
to 10.

**The outer-loop note (every tick passes it to `lead`).** Tell `lead`: (a) `/crew:loop`
is driving this as an outer-loop tick and **loop mode is authorized** — the user's `/crew:loop`
invocation is the loop intent (`loop-engineering`), so don't wait for trigger phrases in the
goal; (b) run this tick **synchronously to a stopping point** — delegate its workers in the
**foreground** (not `run_in_background`) and return only when the plan is quiescent (every step
`done`/`blocked`) or `maxTurns` is hit. There's no interactive user to stay responsive for, and
foreground workers leave **nothing** running when the tick returns — so ticks are genuinely
synchronous, the plan is never mid-worker between ticks, and the next tick can't double-dispatch
a still-running worker.

Each tick, **locate this goal's plan** — the `plan-<feature>.md` whose `feature:` /
`feature-branch:` header identifies this goal, using `lead`'s own durable-resume match rule
(*The plan file is durable state*): match by header, never guess; if more than one could match,
stop and ask the user rather than picking one. Then decide:

1. **No plan yet (tick 1).** Launch `crew:lead` (via the Agent tool) with `<goal>` and the
   outer-loop note. `lead` enters loop mode, explores, writes the plan and its
   `loop:`/`exit-conditions:` header, and runs the plan checkpoint **once** — loop intent
   authorizes the *run*, not the *plan*, so you never skip that gate. When it returns, seed the
   outer-loop counter you own: `iterations: 1/<max>`. Then evaluate the checks below.
2. **Plan exists.** Run the exit checks. If none fires, launch
   `crew:lead` again with `<goal>` and the outer-loop note — it resumes from the plan
   per its durable-resume protocol (a plan with `loop: on` continues in loop mode; it does
   **not** re-plan or re-checkpoint) — then bump `iterations:` **in the header** and re-evaluate.
   The count lives only in the header; a restarted wrapper reads it from there, never re-derives
   it. If a plan exists with no `iterations:` (a hand-edited or truncated file), don't reset to
   `1` — that would bypass the cap; surface it and ask rather than looping blind.

**If launching `crew:lead` fails** (agent won't start / "not found"), stop and surface the
exact error — as `/crew:feature` does. No tick ran, so don't bump `iterations:`; end.

**A crashed prior tick needs nothing special.** `lead`'s resume re-verifies and reconciles
whatever a crash left. Do **not** gate a tick on `in-progress` steps: reconciling those is that
resume's job, and refusing to launch while they exist would **deadlock**, since the tick that
would reconcile them is exactly the one you'd suppress.

**Exit checks (first match ends the loop and surfaces — never auto-push or open a PR):**

- **success.** Every step `done` **and** `gate: GO` → end. Report the run summary. Pushing
  stays behind `/crew:pr`.
- **blocked.** Any step `blocked` on a human decision → end and surface every blocked step
  together (independent unblocked steps have already been drained by `lead`).
- **iteration cap.** `iterations:` `n >= max` → end and surface where the plan stands. The cap
  is enforced here, by you (the model) — it is not a hard runtime budget.

## Ownership

You are the sole writer of the plan file's **outer-loop** bookkeeping only — `iterations:`.
`lead` owns the rest (steps, `loop:`, `exit-conditions:`, `gate:`) and preserves your field
when it rewrites the plan. Ticks are **synchronous** — launch `crew:lead`, wait for it to
return, then update the header and decide — so the two writers never overlap.

Schedule the next tick with the native `/loop` dynamic-mode wakeup only while the loop is still
live. When an exit check fires, stop scheduling and give the user the consolidated status.
