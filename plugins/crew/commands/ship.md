---
description: Unattended feature run for `claude -p` or CI — plan, build, gate, push and open the PR with no prompts
---

Given `$ARGUMENTS` (a ticket ID, task, or free-form requirement):

Run the whole feature with no one at the keyboard, from the task to an open pull request. Every
prompt in this run auto-denies, so nothing here may wait on an answer. **Invoking this command is
the user's standing authorization** for the three gates a run would otherwise ask at: the plan
checkpoint, the push, and the PR. It authorizes nothing else: the guards, the lanes, `lead`'s sole
ownership of git, and "never force-push" are unchanged.

**Cap syntax.** `$ARGUMENTS` may end with a `max=<n>` token, honored only when `<n>` is a positive
integer, then stripped; the rest is **`<goal>`**. Any other trailing `max=` stays in `<goal>`.
Without a valid token, `<max>` is 3. `<max>` counts `lead` launches.

## 1. Preflight — stop before anything is written

End the run with the one-line reason and the status line (*5*) when:

- the session is in plan mode (every launch writes the plan and dispatches editing workers);
- `.claude/crew.md` is missing, or a slot the run needs is `unset` (`lead`'s own rule) → name
  `/crew:init`, since `/crew:init` asks questions and cannot run here;
- a tracked file has uncommitted changes (an unattended run must not commit what it did not
  write); untracked files, such as a plan under `.claude/`, do not count.

## 2. The unattended note (every launch passes it to `lead`)

Tell `lead`:

- (a) `/crew:ship` drives this run unattended: no user is present, and `AskUserQuestion` and every
  permission prompt auto-deny.
- (b) The invocation is the go-ahead for the plan: write it and proceed without the checkpoint
  (*Honor standing authorization*).
- (c) **Loop mode is authorized** (`loop-engineering`): the invocation is the loop intent, so skip
  the handshake and run to the terminal gate under the retry caps.
- (d) Delegate every worker in the **foreground** and return only when the plan is quiescent
  (every step `done` or `blocked`) or `maxTurns` is hit, so nothing runs when you return.
- (e) A decision you would ask the user: take the default that crew config, the task or the
  repository's own conventions give, and record it in the plan as an assumption. With no such
  default, mark the step `blocked` with the question in its `evidence:`, and drain the
  independent steps. `branchNaming` unset → `crew/<slug>`, recorded the same way.
- (f) A pointer to known debt is out of scope here: return without a change and say so (the
  debt lane never pushes; run `/crew:debt` instead).
- (g) Do not push or open a PR: this command does that after you return.

## 3. Launch until quiescent

Launch `crew:lead` (via the Agent tool) with `<goal>` and the note, then write `iterations:
<n>/<max>` in the plan header — the same field `/crew:loop` owns, and `lead` preserves it. Launch
again with the same input (`lead` resumes from the plan) while all of these hold: a step is still
`pending` or `in-progress`, none is `blocked`, and `n < max`. Read `n` from the header, never from
memory. A plan whose header has no `iterations:` after the first launch → stop and surface it, as
`/crew:loop` does. If `crew:lead` cannot be launched, stop and report the exact error.

**No plan file** means `lead` took the express lane: launch once, and its quick self-review stands
in for the gate (no Blocking item counts as GO). `lead` returned a debt refusal → stop.

## 4. Push and open the PR

Follow `/crew:pr` with these changes. The invocation is the push confirmation, so do not ask.
Step 1's hard stop on a protected branch still applies; its stop on NO-GO is replaced by the draft
below.

- **Every step `done` and `gate:` GO** → push the feature branch with upstream tracking and open a
  **ready** PR.
- **Committed work, but a step `blocked`, the gate NO-GO or not run, or the cap hit** → first run
  `/crew:review quick` over the branch for its `## Blocking` items, then push and open a **draft**
  PR. The body opens with what stopped the run: every blocked step with its question, and the
  Blocking items. The container ends with the session, so a draft is how the work survives.
- **No push at all** when no commit exists beyond the base branch, when the current branch is the
  base branch or a protected one (`/crew:pr` step 1), or when a Blocking item is a security
  finding (a secret, a credential, an exploitable flaw). Report it instead.

Never force-push. When the push or the PR call is refused, report the exact error and the
`/crew:pr` step 4 fallback (the push command and a ready-to-paste title and body).

## 5. Report

Relay `lead`'s run summary verbatim, then the PR URL, then one last line a script can match:

`crew-ship: <ready|draft|stopped> <PR URL or reason>`
