---
name: review-gate
description: "How the crew runs a build, test or lint gate: one build location with one writer at a time, one-shot bounded commands, full strictness with warnings as findings, contention told from a code failure, findings routed to the implementer. Preloaded by lead and loaded by /crew:review, so the rules hold whichever of the two dispatches the gate. Not for standalone use."
---

# Review gate rules

1. **One build location, one build writer at a time.** Pick one concrete build location at
   session start — a dedicated out-of-tree output/artifacts directory or persistent build
   worktree — and reuse it in **every** build delegation so caches stay warm. Name it as a plain
   absolute path (no `$`, `~`, `.` or `..` segment) so a worker's log redirect into it passes
   `bash-safety`; a worker clears it with `rm -r`, never `rm -rf`. Inside it the
   intermediates are a shared artifact, and a test or lint run that compiles is a writer too:
   never dispatch two writers of one project's outputs at once. Run a lane's gates **one at a
   time**, unless the lane's stack skill has a **Parallel gates** recipe: load that skill
   (`backend-<stack>`) with the Skill tool before deciding — its recipe holds the allow-list,
   the tree check and the flags — and stay serial if it cannot be loaded or has no recipe (today
   `backend-dotnet` and `backend-node` have one). When its conditions hold, dispatch the gates
   together, each with what its recipe needs in its handoff (a `<location>/<lane>/<gate>` path,
   the exact flags, `nocache` on the runner), `unit-tests`'s included — a worker that did not load
   the stack skill cannot derive them. Record the tree-check result with the gate's outcome. Require the location **isolated from any running
   app/dev process** so builds can't contend on locked `bin`/`obj`, `dist`, bundler caches; an
   e2e suite's command owns its own server lifecycle instead.
2. **One-shot, bounded.** Use the project's **build** command, never a watch/dev/serve command
   (`dotnet watch`, `npm run dev`, `vite`, `tsc --watch`) — those never terminate and hang the
   worker. Require `/crew:review`'s wait recipe and a wall-clock budget in the handoff.
3. **Full strictness; warnings are findings.** Require the configured command run **as
   configured** — no narrowed target, no property or flag that relaxes analyzers/type checks, no
   verbosity below the default. A zero exit code is not a pass: require the build's **warnings**
   in the worker's findings — blocking in a file this branch changed, reported elsewhere. If the
   **configured command itself** carries such a weakening, that's a NO-GO naming it — never
   rewrite crew config to strengthen it yourself.
4. **Tell a contention failure from a code failure — and rule out your own dispatch first.** A
   lock/in-use error (`MSB3027`/`MSB3026`, "being used by another process", `EBUSY`/`EPERM`/
   `EACCES`, a locked or corrupted `bin`/`obj`/`dist`) or a build timeout is **contention, not a
   code defect** — don't route it to the implementer. If two of your delegations shared the build
   location, the collision is yours: say so, clear the corrupted intermediates, serialize or split
   the paths, and re-run. Only when none overlapped is it the user's environment — report the
   likely lock (or hang), ask them to stop the dev server/app or confirm the location, then retry.
5. Collect the workers' concise findings, synthesize the go/no-go, and route **genuine
   compile/test failures** back to the implementer.
6. **A lint NO-GO that is formatting only means the format matrix is stale** (a row missing or
   wrong for the files this run touched): route the findings as usual, and in the same report
   say so once and name `/crew:init` — never add or edit a row yourself.
