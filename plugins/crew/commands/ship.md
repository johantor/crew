---
description: Unattended feature run for `claude -p --agent crew:lead` — plan, build, gate, push and open the PR with no prompts
---

Given `$ARGUMENTS` (a ticket ID, task, or free-form requirement):

Run the whole feature with no one at the keyboard, from the task to an open pull request. Every
prompt in this run auto-denies, so nothing here may wait on an answer. **Invoking this command is
the user's standing authorization** for the three gates a run would otherwise ask at: the plan
checkpoint, the push, and the PR. It authorizes nothing else: the guards, the lanes, `lead`'s sole
ownership of git, and "never force-push" are unchanged.

## 1. Preflight — stop before anything is written

End the run with the one-line reason and the status line (*4*) when:

- you are not `crew:lead` running as the session's main thread. A subagent cannot launch
  workers, so the run must start as `claude -p --agent crew:lead '/crew:ship <task>'`: name that
  command;
- the session is in plan mode (the run writes the plan and dispatches editing workers);
- `.claude/crew.md` is missing, or a slot the run needs is `unset` → name `/crew:init`, which
  asks questions and cannot run here;
- a file has uncommitted changes or is untracked (an unattended run must not commit what it did
  not write); only the plan directory (`<plan-dir>`, `.claude/` when unset) is exempt, so a
  resume keeps its plan;
- the task is a pointer to known debt: the debt lane never pushes, so name `/crew:debt`.

## 2. Run your flow unattended

Run your standard flow on `$ARGUMENTS`, express lane included, with these changes:

- **No checkpoint.** The invocation is the go-ahead for the plan (*Honor standing
  authorization*): write it and proceed.
- **Loop mode is authorized** (`loop-engineering`): the invocation is the loop intent, so skip the
  handshake and run to the terminal gate under the retry caps.
- **Delegate every worker in the foreground** and run until the plan is quiescent (every step
  `done` or `blocked`). An ended turn ends a `claude -p` run, so never end one while a worker runs.
- **A question becomes a default or a blocked step.** Take the default that crew config, the task
  or the repository's own conventions give, and record it in the plan as an assumption. With no
  such default, mark the step `blocked` with the question in its `evidence:`, and drain the
  independent steps. `branchNaming` unset → `crew/<slug>`, recorded the same way.

## 3. Push and open the PR

This section is the one exception to your rule that push and PR are not yours: the invocation is
the push confirmation, so do not ask. Follow `/crew:pr` with these changes. Step 1's hard stop on
a protected branch still applies; its stop on NO-GO is replaced by the draft below. In the express
lane, the quick self-review stands in for the gate (no Blocking item counts as GO).

- **Every step `done` and the gate GO** → push the feature branch with upstream tracking and open
  a **ready** PR.
- **Committed work, but a step `blocked`, or the gate NO-GO or not run** → first run
  `/crew:review quick` over the branch for its `## Blocking` items, then push and open a **draft**
  PR. The body opens with what stopped the run: every blocked step with its question, and the
  Blocking items. The container ends with the session, so a draft is how the work survives.
- **No push at all** when no commit exists beyond the base branch, when the current branch is the
  base branch or a protected one (`/crew:pr` step 1), or when a Blocking item is a security
  finding (a secret, a credential, an exploitable flaw). Report it instead.

Never force-push. When the push or the PR call is refused, report the exact error and the
`/crew:pr` step 4 fallback (the push command and a ready-to-paste title and body).

## 4. Report

Emit your run summary, then the PR URL, then one last line a script can match:

`crew-ship: <ready|draft|stopped> <PR URL or reason>`

`ready` and `draft` name the outcome, not the PR: a branch pushed under the `/crew:pr` step 4
fallback keeps its outcome, with `no PR: <reason>` in place of the URL. `stopped` means nothing
was pushed.
