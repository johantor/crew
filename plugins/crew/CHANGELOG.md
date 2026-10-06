# Changelog

All notable changes to the `crew` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [10.12.0] - 2026-10-06

### Added

- `optimizely-commerce-customized` (Commerce Connect 14 and 15) and `optimizely-commerce-configured`
  (Configured Commerce, Spire) skills (#279).
- `optimizely-experimentation` skill: Feature and Web Experimentation, Performance Edge (#280).
- `optimizely-ocp` skill: Connect Platform apps (#282).
- The stack, frontend and CMS skills name the markers of the four new skills.

## [10.11.0] - 2026-10-06

### Added

- `frontendStack: other`, best effort, for a web view with no crew skill (Vue, Svelte, Angular);
  the new `frontendSkill` slot names the project's own skill.

### Changed

- With an `other` stack and no lane paths, `lane-guard` lets `backend` and `frontend` write
  anywhere and `lead`'s plan keeps them apart; `/crew:init` no longer asks for lane paths there.

## [10.10.0] - 2026-10-06

### Added

- `backendStack: other`, best effort, for a stack with no crew skill: `/crew:init` proposes it,
  and the new `backendSkill` slot names the project's own skill (#274).
- `lane-guard` refuses `other` beside a frontend without lane paths, and widens `unit-tests` to
  `test/`, `spec/`, `*_test.*` and `*_spec.*` under it (#274).

## [10.9.1] - 2026-10-06

### Fixed

- `lane-guard` reads a Windows backslash path as `/`-separated, so `lead` can write its plan and
  memory files there and the worker lanes and `..` check apply; a drive-relative path is refused (#298).
- `format.sh` matches a Windows path against `formatMatrix` rows, so per-edit formatting runs there (#298).
- `gate.sh start` works on Git Bash, whose `mkdir -m 700` failed and read as a reused `<id>` (#298).

## [10.9.0] - 2026-10-06

### Added

- `optimizely-opal` (the custom-tool contract, registries, auth) and one tools-SDK skill each
  for .NET, Node and Python; the backend stack skills name the SDK packages (#296).

## [10.8.1] - 2026-10-06

### Fixed

- `bash-safety` no longer lets a write through after a `\"` inside a quoted string: an
  unterminated span stays unmasked instead of being dropped (#297).

## [10.8.0] - 2026-10-06

### Added

- `lead` may write ticket drafts (`tickets/*.md` at any depth) and any path outside the project,
  such as a session scratchpad (#295).

## [10.7.0] - 2026-10-06

### Added

- `/crew:init` asks on the first run whether to commit its output or keep it local:
  `.claude/crew.md` and `CLAUDE.local.md`, excluded through `.git/info/exclude` (#294).

## [10.6.0] - 2026-10-06

### Added

- `frontend-razor` skill: Razor view rules for ASP.NET Core, plus the Optimizely CMS 12/13 view
  rules (`epi-property`, ContentArea, client resources); both halves of a view load it (#293).

### Removed

- The Blade (Laravel) section of `frontend-server-rendered`: the crew supports no PHP stack
  (#293).

## [10.5.0] - 2026-10-06

### Added

- `optimizely-odp` skill: data model, events and profiles, real-time audiences for CMS and
  Experimentation, keys, consent, rate limits; the stack and CMS skills name its markers (#283).

## [10.4.0] - 2026-10-05

### Added

- `optimizely-search-navigation` skill: indexing, typed and unified search, facets, limits, and
  the migration to Graph that CMS 13 requires (#278).

### Fixed

- `optimizely-graph` and `optimizely-cms-saas` facts, checked against the packages and docs:
  the Graph config section name, CMS 13 sync exclusions, tracking setup, SDK imports (#291).

## [10.3.0] - 2026-10-05

### Added

- `optimizely-cms-saas` skill: content types in code, Visual Builder, live preview, webhooks,
  environments and keys for SaaS CMS; `frontend-headless` names its markers (#277).

## [10.2.0] - 2026-10-05

### Added

- `optimizely-graph` skill: detection, sync, querying from .NET and headless front ends, keys,
  caching, search and facets. The CMS skills, `backend-dotnet`, `backend-node` and
  `frontend-headless` name its markers (#276).

## [10.1.1] - 2026-10-05

### Changed

- The README opens on the Optimizely focus and the product skills (#284).

## [10.1.0] - 2026-10-05

### Added

- The Python stack is back (`backend-python`, `tests-pytest`), for Opal tools and other Python
  services beside an Optimizely site (#285).

## [10.0.0] - 2026-10-05

### Changed

- **Breaking:** agents use role names: `morpheus` → `lead`, `tank` → `backend`, `trinity` →
  `frontend`, `oracle` → `unit-tests`, `dozer` → `e2e`, `seraph` → `visual-review`, `neo` →
  `generalist`, `sentinel` → `incident-triage`, `keymaker` → `debt-scout`. Start the crew with
  `claude --agent crew:lead`; agent memory saved under an old name is not carried over (#272).
- **Breaking:** the marketplace is `johantor` and the repository `johantor/crew`: install with
  `claude plugin marketplace add johantor/crew` and `crew@johantor` (#272).
- The guards match only `crew:<name>` agents, so a project's own agent named `backend` or
  `lead` is not put on crew's no-git, lane or format rosters (#272).

## [9.0.0] - 2026-10-05

### Changed

- **Breaking:** `cms-optimizely` is removed, replaced by full `optimizely-cms12` and
  `optimizely-cms13` skills and `optimizely-cms-upgrade` for 12 → 13; a call to the old name fails (#271).

## [8.0.0] - 2026-10-05

### Removed

- **Breaking:** the Python, Go, Rust and Java stacks (`backend-*` and `tests-*` skills); the
  crew now targets .NET with Optimizely, Node and shell, and stops on other stacks (#270).

## [7.0.0] - 2026-10-05

### Changed

- **Breaking:** `/crew:init` is the only detector. `morpheus` reads `.claude/crew.md` and stops
  on an `unset` slot a step needs, naming `/crew:init`; memory no longer holds config (#269).
- **Breaking:** `lane-guard.sh` probes no repo markers; `tank`/`trinity` are refused while
  `backendStack` is `unset`. The framework allowlists and the per-session cache are gone (#269).

## [6.0.0] - 2026-10-05

### Fixed

- The guards read the worker's namespaced `agent_type` (`crew:tank`); bare rosters never
  matched an installed plugin's worker, so lanes, no-git and formatting failed open (#268).

### Changed

- **Breaking:** `format.sh` runs the `formatMatrix` rows `/crew:init` writes and detects
  nothing; without the slot per-edit formatting is off until `/crew:init` is re-run (#268).
- Crew config reading moved to `hooks/lib/guard-lib.sh`, shared by `lane-guard.sh` and
  `format.sh` (#268).
- Stack skills name their matrix row; `review-gate` reports a formatting-only NO-GO as a stale
  matrix; `worker-contract` hands back a `format hook:` line naming `/crew:init` (#268).

## [5.4.0] - 2026-09-30

### Added

- `scripts/gate.sh` caches a green log by working-tree hash, directory and command, so a gate
  on an unchanged tree is answered at once instead of building the same tree twice (#267).
- `backend-node` has a Parallel gates recipe: `tsc --noEmit`, `vitest run`/`jest` and
  `eslint`/`prettier --check` run together under a tree check every run (#267).

### Changed

- `/crew:review` no longer records `HEAD` and a clean status to skip a repeated gate; the runner
  decides from the tree hash (#267).

## [5.3.1] - 2026-09-26

### Changed

- `/crew:notify` is 40 lines instead of 117; every rule it enforced stays (#248).

## [5.3.0] - 2026-09-25

### Added

- `scripts/gate.sh` runs a review gate in one simple command per call, so a headless worker can
  run it under a single allow rule (#245).

### Changed

- `/crew:review`'s wait recipe calls `gate.sh`, and a worker reports a refused or failed call
  instead of improvising another form (#245).

## [5.2.1] - 2026-09-25

### Fixed

- A Bash redirect to a plain, unquoted absolute path outside the project, such as an out-of-tree
  build root, is no longer refused (#240).

## [5.2.0] - 2026-09-25

### Changed

- `bash-safety` refuses a bare `cat <file>` in agent sessions only; your own session may `cat`
  (#249).
- Workers may run one plain `git mv` with relative paths; any other git, a `-C`/`cd`/`..` form
  and a forced `git mv` stay refused (#249).

### Removed

- The worker `git mv` hand-back refusal and `bash-safety`'s `git_owner=` line (#249).

## [5.1.0] - 2026-09-25

### Removed

- The `turn-budget` hook and its per-agent budget table; a worker cut off at `maxTurns` is
  resumed through `morpheus`'s truncated-return reconcile path (#249).
- `/crew:loop`'s `in-flight:` plan-file marker; the next tick's resume reconciles a crashed one
  (#249).

## [5.0.0] - 2026-09-24

### Removed

- **One configuration location: `.claude/crew.md`.** `/crew:init --local` and the legacy
  `## Crew configuration` block in `CLAUDE.md` are no longer written or read (#248). On a project
  still using either, run `/crew:init` on 4.2.x first: it migrates the block, and a `--local` file
  is copied into `.claude/crew.md` by hand.

## [4.2.0] - 2026-09-24

### Added

- **`review-gate` skill**: the build/test/lint gate rules, preloaded by `morpheus` and loaded by
  `/crew:review`, so a standalone gate run follows the same rules (#250).

### Changed

- **`worker-contract` states the gate rule once**: run a gate only as the handoff gives it; the
  handoff's rules are `review-gate`'s and the tool specifics the stack skills' (#250).
- **`/crew:review` classifies lanes without a copy of the guard's list**: frontend extensions or
  documentation, everything else is backend. It points at `morpheus`'s gate rules instead of
  restating them.
- **`/crew:init` §2 is a table; each backend's commands come from its stack skill's *Crew config*
  section.** Its orchestration template matches the live root `CLAUDE.md`.
- `/crew:loop`, `/crew:triage` and `/crew:notify` cite `AGENTS.md` for the crashed-tick and
  split-delimiter rationale instead of restating it.

## [4.1.2] - 2026-09-24

### Changed

- **Debt skills: one mechanism table per stack** (scope, justification slot, stale signal,
  removal) and one upgrade table in `debt-taxonomy`; `debt-lane` routes by them instead of
  restating them (#250).
- **Stack and test skills state only what is specific to their tool.** The docs-MCP rule, the
  run-as-configured rule and the never-skip rule live once, in `worker-contract`, `oracle` and
  `dozer` (#250).
- **`worker-contract`: an e2e suite's command owns its own server**; only a build is isolated from
  a running app.

## [4.1.0] - 2026-09-24

### Added

- **`worker-contract` skill**: the rules shared by `tank`, `trinity`, `oracle`, `dozer` and
  `neo` — no git, the build as the final gate, the completion marker — written once (#250).

### Changed

- **Those five worker prompts state only what is specific to their role**; the shared rules
  moved to `worker-contract`.
- **README: which skills are always on**, per agent, matches the agents' frontmatter (#250).

## [4.0.1] - 2026-09-24

### Changed

- **Hooks have one wiring, `hooks/hooks.json`.** The repo's dev-time mirror
  `.claude/settings.json` is gone; develop with `claude --plugin-dir plugins/crew` (#251).

## [4.0.0] - 2026-09-23

### Removed

- **The `keymaker` plugin is gone; crew replaces it.** `/keymaker:open` → `/crew:debt`,
  `/keymaker:audit` → `/crew:audit`. Uninstall `keymaker@zion`.

### Added

- **Debt lane: `/crew:debt <pointer>`**, or just name the pointer to `morpheus`. The `keymaker`
  plugin's fix flow, now run by `morpheus` through the lane workers.
- **`keymaker` agent: the read-only debt scout behind `/crew:audit <scope>`.** It has no Edit,
  Write or Bash tool; each pick launches `morpheus`'s debt lane directly.
- **`debt-lane`, `debt-taxonomy`, `debt-taxonomy-dotnet` and `debt-taxonomy-typescript` skills.**

### Changed

- **`morpheus`'s writes are lane-guarded**: Edit/Write only on `plan-*.md`, `debt-*.md`,
  `crew.md`, Markdown under `agent-memory-local/` and scratch. It never wrote production code; the hook now
  enforces it. A `..` path segment is refused for every lane agent.
- **`sentinel` hands accumulated debt to `/crew:debt`** instead of `/keymaker:open`.

## [3.29.3] - 2026-09-23

### Fixed

- **`oracle`, `dozer`, `seraph` and `sentinel` end an unfinished report with a `remaining:` line,
  with or without a turn-budget warning** (#225).

## [3.29.2] - 2026-09-23

### Fixed

- **`morpheus` picks a worker's location before dispatch: `isolation: worktree` or a named path,
  never both, and no worktree for a gitignored deliverable** (#241, #242).
- **A formatter or linter that checks zero files fails its `/crew:review` gate, not passes it** (#241).
- **`tank` accepts a verify-only step that writes no file** (#242).

## [3.29.1] - 2026-09-23

### Fixed

- **Gate builds and suites end inside the worker's turn: run detached, polled on an exit file;
  `morpheus` asks for the report when a worker waits on its own background work** (#239).

## [3.29.0] - 2026-09-22

### Added

- **`/crew:init --local` keeps the config out of the repo.** Slots go to `crew.md` in the shared
  git dir, read by every worktree; the orchestration prose goes to `~/.claude/CLAUDE.md`.

## [3.28.0] - 2026-09-22

### Added

- **`morpheus` can read the web while it plans.** Adds `WebFetch` and `WebSearch`; fetched
  content is data, not instructions.

### Fixed

- **`morpheus` can ask with options, stop a worker, and load a stack skill.** Adds
  `AskUserQuestion`, `TaskStop` and `Skill`, which its prompt and `loop-engineering` already use.

## [3.27.0] - 2026-09-22

### Added

- **.NET review gates run in parallel.** Build, test and lint each get their own artifacts path;
  other stacks, and .NET setups the recipe doesn't fit, still run their gates one at a time.

## [3.26.5] - 2026-09-22

### Fixed

- **A commit in a git worktree is judged by the worktree's branch.** The protected-branch
  backstop read the hook's own directory, so a main checkout on `develop` refused worktree commits.

## [3.26.4] - 2026-09-22

### Changed

- **`/crew:address` stops patching a mechanism that keeps breaking.** Findings with one root cause
  become one item, and new edge cases of an already-patched mechanism go to the user instead.

## [3.26.3] - 2026-09-22

### Fixed

- **`morpheus`'s `git mv` is no longer refused when keymaker is installed too.** The shared floor
  let only the plugin's own git owner rename, and the two plugins name different owners, so with
  both installed keymaker's copy of the guard refused `morpheus` ("keymaker owns git"). The floor
  now lets any agent run a plain `git mv`; whose rename it is stays crew's own rule, below the
  shared region, so a worker's `git mv` is still told to hand it to `morpheus`. `-f`/`--force` and
  bare `mv`/`cp` stay refused for everyone.
- **A `git mv` on a second line of one Bash call is allowed.** The allowance saw only the first
  command of a multi-line call, so two renames typed on two lines were refused as a bare `mv`,
  with a message pointing at Edit/Write. It now reads the command as typed and takes a line start
  as a command position; what follows a rename is checked as before, on any line, and `git` on
  one line with `mv a b` on the next is still two commands, the second refused.

## [3.26.2] - 2026-09-22

### Changed

- `oracle` checks that a new test is discovered with the runner's list command, never by reading
  a compiled DLL or class file. Zero tests found is a project-wiring problem to report.
- Each unit-test skill names its tool's list command. `tests-xunit` gains a Running section.

## [3.26.1] - 2026-09-22

### Changed

- `sentinel` and `seraph` no longer load the project's `CLAUDE.md` files on spawn
  (`omitClaudeMd: true`). Both are read-only on code and get what they need from the dispatch
  prompt — a triage signal plus a changeset, or a design reference plus a rendered page — so the
  project's coding conventions were paid for on every spawn and never used. The implementers
  (`tank`, `trinity`, `dozer`, `oracle`, `neo`) keep loading it: they edit project code, and that
  is where its conventions live.

## [3.26.0] - 2026-09-14

### Added

- Plan mode: `morpheus` treats plan mode's approval as its plan checkpoint — one gate, not two.
  As the main thread it presents the plan through `ExitPlanMode` and writes the plan file after
  approval; as a subagent it returns the plan, and `/crew:feature` runs the two launches around
  the approval, passing the plan between them as text. `/crew:loop` and `/crew:address` say they
  don't run in plan mode instead of failing mid-tick.
- `plan-guard` hook (`PreToolUse` on `Agent`/`Task`): in plan mode, a dispatch of a crew worker
  whose tools carry Edit/Write is refused before it spends its turns on refused edits; read-only
  workers and the orchestrator pass. Decided from the worker's own frontmatter, not a roster.
  Fails open.

### Changed

- `morpheus` may launch the built-in `Explore` and `Plan` research agents in a `claude --agent
  crew:morpheus` session, and carries `ExitPlanMode` so such a session can present its plan in
  plan mode.

## [3.25.1] - 2026-09-13

### Fixed

- The three raw-read rules take the same wrapper prefixes as the rest of the guard, so a leading
  `env`, `command` or `VAR=1` no longer walks a read past them (#226).

### Changed

- The `cat` and pager refusals name the `Read` tool, and all three raw-read refusals say why a
  shell read is refused: it reaches no `Read` hook, so `read-guard`'s size bound never applies.
  Nothing replaces a `tail -f`, so that one points at capture/filter instead (#226).

## [3.25.0] - 2026-09-10

### Changed

- `dozer` runs with `maxTurns: 120` (was 84), and the `turn-budget` table follows. E2e work
  is turn-expensive per spec — write, run, read the failure, re-instrument, re-run — and a
  dispatch of a dozen specs exhausted the old budget mid-run twice. The budget now covers
  such a dispatch; keep dispatches at a handful of specs so a truncation stays cheap.

### Fixed

- `tank`, `/crew:notify`, `/crew:triage` and the `mid-run-direction` skill carried a
  description whose prose put a colon before a space in an unquoted YAML scalar, so the
  frontmatter block did not parse and each file loaded with no `name` and no `description` —
  a skill with no description never triggers, and an agent with none is invisible to the
  orchestrator. The four descriptions are now quoted, with their wording unchanged.

## [3.24.0] - 2026-09-04

### Added

- Python, Go, Rust, Java and shell backend stacks: ten skills, plus the `backendStack` values
  and detection that let `/crew:init` and `morpheus` resolve them (#215, #218).
- `format.sh` formats `.py`, `.go`, `.rs` and `.java` after an edit, each gated on the owning
  project's configuration rather than on what is installed, and honouring the project's own
  exclusions (#215, #218).
- `frontendStack: none` states that a project has no view layer, so `morpheus` skips frontend
  resolution and dispatches only `tank`/`oracle` (#218).

### Fixed

- `/crew:review` classified a branch in any of the new stacks as "Neither" and skipped the
  backend build, test and lint gates entirely (#215).
- `lane-guard` denied `trinity` only `.cs`/`.csproj`, so the write lanes stopped separating in
  any other backend — `.sh` included, which is what this repo is written in; `oracle` could not
  author a test in one at all (#215, #218).
- Watch/dev commands were refused only in the .NET/JS ecosystems, so `uvicorn`, `cargo watch` or
  `./gradlew bootRun` could hang an agent's whole turn budget (#215).

### Changed

- Rewrote the plugin description so the plugin directory shows what `crew` does rather than
  what it contains, and added `keywords` for discovery.
- Docs name the supported backend stacks rather than implying web-only, and describe
  `trinity`'s lane as the client-facing layer rather than "the frontend" (#215).

## [3.23.0] - 2026-09-04

### Fixed
- **`morpheus` may run `git mv` (#208).** The Bash guard refused every `mv`, so a rename stalled on
  a command the user had to run by hand. A plain `git mv` is now allowed for the git owner alone;
  `-f`/`--force` and bare `mv`/`cp` stay refused, and a worker's `git mv` is told to hand the rename
  back. Validator §9 pins the hook's `git_owner=` line to the `owns-git: true` agent.
- **The gate build runs as strict as the project configures (#193, #206)** — no narrowed target or
  relaxed analyzers, and warnings reported rather than dropped.
- **Lane gates never race over one shared `obj/` (#194, #205)** — serialize them or split the
  intermediate path per writer, and rule out a crew-caused collision before reporting a lock error
  as the operator's environment.

### Changed
- README: a git worktree keeps only committed files, so local agent memory and an uncommitted plan
  are deleted with it (#197, #204).

## [3.22.0] - 2026-08-31

### Fixed
- **`lane-guard.sh` reads crew configuration from `.claude/crew.md` again (#201).** The slots moved
  there in 3.21.0, and `/crew:init` migrates the legacy block out of `CLAUDE.md`, but the guard
  still looked for `- **Backend lane path(s):** …` bullets in the old file. Every slot it reads —
  both lane paths, both stack pins, and the frontend e2e tool — came back empty in any project
  configured by the current `/crew:init`. In a same-language repo with lane paths set, that turned
  every `tank`/`trinity` edit into a block telling the user to configure the file the values had
  just been moved out of; in a mixed-language repo it silently degraded directory lanes to
  extension lanes and dropped a pinned `Backend stack`. The guard now reads the frontmatter by
  key and falls back to a legacy **Crew configuration** block only when `.claude/crew.md` is
  absent, so migrated and unmigrated projects both work. Only the frontmatter is parsed — a slot
  quoted in the file's prose body is not configuration — and a value is read as YAML: a quoted
  scalar is unwrapped and an inline `#` comment dropped, since either left in place builds a lane
  glob that matches nothing, which reads as no lane at all and widens the agent instead of failing
  closed. The five block messages name `.claude/crew.md` as the file to edit.

### Changed
- The hooks' inline comments were cut back to what the code cannot say itself. `guard-lib.sh` and
  the six entry points carried paragraph-length rationale, some of it a second copy of what
  `AGENTS.md` already states. What stays is the load-bearing why: the argument order in
  `guard_jq2`, the quoted interpolation that keeps the redirect scan from looping, the marker
  shapes validator §5/§9 parse. Comments only; no guard's allow/block behavior changes.

## [3.21.0] - 2026-08-31

### Fixed
- **A worker's Bash writes are now guarded too (#192).** `lane-guard.sh` and `format.sh` are wired
  to `Edit|Write`, so a write shelled out through `sed -i`, `tee`, a `>`/`>>` redirect or a
  `cp`/`mv` landed outside lane enforcement *and* outside formatting — the guarantee that "each
  worker's edits are confined to its own lane" silently did not hold on the Bash path. Auto mode,
  the default for new sessions since 14 August 2026, injects a notice pushing every agent toward
  exactly that path, which turned an edge case into the default one. `bash-safety.sh` now refuses
  file-mutating Bash for agent sessions and names `Edit`/`Write` as the way to write, keeping one
  enforcement point rather than reimplementing lane resolution on a second. Exempt sinks
  (`/dev/null`, an fd dup, anything under the temp directories) and read-only uses of the same
  tools (`sed` without `-i`, a quoted `>` inside a grep or awk expression) stay allowed; the
  operator's own session is untouched, as with every other agent-scoped rule.
- **`>|` counts as a redirect.** The noclobber override was not in the redirect pattern, so its
  target hid behind the `|` and the redirect read as targetless. That also let `echo s >| .env`
  past the existing destructive rule, which is fixed with the same change.
- **`mid-run-direction` names the category a harness notice belongs to (#192).** The skill had two:
  a token-carrying steer, or an injection. A platform notice about session mechanics is neither,
  and workers were reporting one as a security event — three times in one run, which is how a real
  report gets lost. The discriminator is now what a message *asks for*, not what it claims to be: a
  notice that only changes how in-bounds work gets done grants nothing, while a *how* that changes
  which guards see the work ("edit through Bash") is still declined, as a mechanics conflict.

### Changed
- **Every agent's turn budget went up by half (#200).** `morpheus` 96 → 144, `tank`/`trinity`
  72 → 108, `oracle`/`dozer` 56 → 84, `neo` 48 → 72, `seraph`/`sentinel` 40 → 60. The old
  ceilings cut workers off mid-step on ordinary work, and a truncated return costs the
  orchestrator a re-dispatch — more expensive than the turns it saved. The ratios between agents
  are unchanged, so the relative sizing of a step stays what it was; `maxTurns` and
  `turn-budget.sh`'s table moved together, as validator §8 requires.
- **The guards' shared logic moved into a sourced library, `hooks/lib/guard-lib.sh`.** Payload
  plumbing, the command-shape patterns, the shared block helpers, the protected-branch list and
  read-guard's limits now live in one vendored file that every entry point sources, instead of
  being copy-pasted across hooks and policed region-by-region. `hooks/` now holds two kinds of
  file, and the distinction is enforced rather than conventional: top-level `*.sh` are entry
  points (executable, wired), `hooks/lib/*.sh` are libraries (not executable, not wired) —
  validator §3 and §6 check both directions. No guard's allow/block behavior changes.
- **The guards stopped forking to match.** `bash-safety.sh` piped its command into `grep -E` six
  times plus `tr` and `cat`, before every Bash tool call; matching now goes through bash's own
  `=~` and parameter expansion, leaving the single `jq` that parses the payload as the only
  child process. One call costs ~4 process operations instead of ~32, about 3× faster wall-clock.
  `lane-guard.sh` reads `CLAUDE.md` once in-process rather than running `sed | head | sed` per
  configuration slot (up to eight processes per lane dispatch), and `read-guard.sh` and
  `format.sh` each fold two `jq` calls into one. The patterns are unchanged — a differential
  test compared old and new matching across 533 command/pattern pairs with no divergence.
- **Per-session state files age out.** `turn-budget.sh`, `dispatch-denied.sh` and
  `lane-guard.sh`'s detection cache route their `/tmp` state through one helper that sweeps
  entries older than a day, so a long-lived machine no longer accumulates one tiny file per
  agent instance forever. The sweep runs at most once per agent instance, not per tool call.
- **Crew configuration moved out of a project's `CLAUDE.md` into `.claude/crew.md`.** The slot
  block put machine configuration for a dispatcher into the one file every session auto-loads for
  every teammate — including teammates who have never installed the plugin, and who read
  `Backend lane path(s): unset` as noise. Configuration is now YAML frontmatter, one key per slot,
  in `.claude/crew.md`: committed so teammates inherit it, reviewable in a PR, and read on demand
  instead of on every turn. `unset` and `none` are now plain YAML values rather than italic
  markdown that reconcile had to string-match, and `none` keeps its meaning — the project has no
  such tooling, so the gate skips and nobody is asked. Nothing breaks on upgrade: `morpheus`,
  `keymaker`, `/crew:review`, the worker agents, and the stack/test skills all fall back to a
  legacy **Crew configuration** block when the new file is absent, and nudge once to migrate.
  `## Crew orchestration` deliberately **stays** in `CLAUDE.md` — auto mode's permission
  classifier reads that file and nothing else, so moving it would cost worker dispatches their
  only description.
- **`/crew:init` now judges what may go into `CLAUDE.md` instead of filling it.** Slots go to
  `.claude/crew.md`; a `CLAUDE.md` line is proposed only when it clears an explicit bar — *would a
  quick glance give the right answer, or a plausible wrong one?* A `format` script that **writes**
  when asked to check earns a line. The stack, a bare `npm run build`, and the dev URL do not:
  they are one glance from `package.json`, and a written copy rots while `package.json` maintains
  itself. Whatever survives is written tool-neutral, with no crew vocabulary, because its audience
  is anyone working in the repo. A re-run also **migrates** a legacy block: it carries every slot
  value across (values it has no key for become body notes), judges the rest against the bar,
  and removes the section — after showing the diff, since the move is one-way.
- **Validator §11 now pairs `init.md` §1 against `.claude/crew.md`.** Each §1 slot bullet declares
  its key in backticked parentheses, and §11 keeps those keys in lockstep with this repo's own
  config file's frontmatter, both directions. The pairing is on the key rather than the prose
  label, the file's prose body is excluded (a key named in notes is not configuration), and a slot
  bullet that declares no key is reported as unparseable rather than passed over.

### Added
- **`morpheus` and `keymaker` share one operator-facing voice, the `operator-voice` skill.** The
  two orchestrators are the only agents that report to the operator directly — plan checkpoints,
  gates, run summaries, blockers — and each phrased those its own way. Both now preload the same
  skill — ASD-STE-100 (Simplified Technical English), named in the skill along with what the
  standard is: short sentences, active voice, one term per thing held for the whole run, exact
  numbers and paths, and a caveat kept in the sentence it qualifies. The skill notes that it
  carries the rules but not the standard's approved-word dictionary, so agents write to the
  standard rather than claim compliance with it. It governs operator-facing messages
  only; code, plan files, ledgers and commit messages keep the project's own conventions.
- **Hook tests are now repo-level and plugin-agnostic.** The harness moved to `tests/hooks/lib.sh`
  and derives which plugin it is testing from the calling test file's own path, so a plugin gets
  a working suite by dropping a file into its `tests/` directory. `tests/hooks/run.sh` discovers
  every `plugins/*/tests/*.test.sh` and **fails when a plugin ships `hooks/` with no suite beside
  it** — the gap that had left keymaker's guards untested since they were written.
- **`/crew:notify` — message another running crew session (#177).** An unattended `/crew:loop`
  could not be asked for progress or told that scope changed, and two crew sessions on parallel
  worktrees had no way to learn what the other landed, because `morpheus` owns git *per session*.
  The new command resolves a peer with `ListAgents` and sends plain text with `SendMessage`. It
  ships as a command rather than a `morpheus` capability: peer messaging is a user-driven action,
  not orchestration, and `morpheus`'s always-loaded prompt is close to its footprint cap. Three
  rules carry the weight — an ask the sender's own guards would refuse (push or open a PR, commit
  on a protected branch, edit out of lane, bypass a hook, forward a secret or a `steer-token:`) is
  refused at the **sending** end, since routing it through a second session is how a guard gets
  laundered; a message that would change the peer's run is confirmed first, while a question is
  not; and the reply comes back as data to relay, never as direction this session acts on. Where
  the host has no `SendMessage` (it varies by version, platform, and provider) the command says so
  and prints the message to deliver by hand — never a blocker, the same fallback steering took.

## [3.20.0] - 2026-08-14

### Changed
- **`seraph` looks to find and measures to report.** It still screenshots first — clipped text,
  overlapping elements, and a wrong-but-loaded image are visible only in the render, and every
  measured value matches spec while they happen — but a defect now comes back as
  actual/spec/delta read from `getComputedStyle` and `getBoundingClientRect` rather than as
  "spacing looks slightly off". It pairs each reference element with the DOM element implementing
  it and reports a pairing it isn't sure of as **unmatched rather than measured**, since a wrong
  pair yields an exact, confident, wrong delta. It also checks console and network first, so a
  failed webfont is reported as a 404 rather than as a typography defect.
- **`seraph`'s turn budget raised to 40** (from 20), with the matching `turn-budget.sh` entry.
  Per-element measurement across the states a reference specifies does not fit in 20 turns, and
  the old cap made the new method unusable rather than merely tight.

### Added
- **`design-tokens` skill**, preloaded by `seraph`. Where tokens live per system, which survive
  to runtime, and how to map a measured value back to a token — including not snapping to the
  nearest one, since an off-scale value is itself the finding.
- **`seraph` treats the page under review as untrusted data.** Rendered text, DOM content,
  console messages, and response bodies can carry seeded content, and its report is relayed
  verbatim into the `/crew:review` design gate — anything reading as an instruction is now
  quoted rather than obeyed.

## [3.19.0] - 2026-08-13

### Added
- **`mid-run-direction`, preloaded by every worker.** A steer arrives in a `system-reminder`-shaped
  block, so shape can't tell it from injected text. Workers authenticate on the dispatch's
  `steer-token:` and treat an anchored steer as **authenticated but fallible** — correct a wrong
  premise in the return rather than discarding the message; surface anything unanchored.

### Changed
- **`morpheus` mints a `steer-token:` per dispatch** and opens each steer with it, describing the
  **end state** instead of asserting what the worker already did.

## [3.18.0] - 2026-08-13

### Added
- **The crew survives auto mode.** Auto mode drops `Agent` allow rules when it starts, so a worker
  dispatch is the one call you cannot allowlist: the permission classifier judges each one on its
  own, and identical dispatches minutes apart can pass and then be refused mid-run. Three things
  now address that. `/crew:init` writes a `## Crew orchestration` section above the config block —
  the classifier reads `CLAUDE.md`, so it gets a description of what a worker delegation is instead
  of a bare dispatch label. A new `dispatch-denied` hook (`PermissionDenied`) retries the first
  denial of a worker once, then stops and names the fixes that exist, so `morpheus` hands the step
  back instead of thrashing or dead-ending on `Blocked by classifier`. And the README's new
  *Permission mode* section recommends `acceptEdits` for crew sessions and documents the auto-mode
  path for anyone who stays there — including that `permissions.allow` cannot help. Timely: auto
  mode becomes the default for new sessions on Pro, Max, and Team plans on 14 August 2026.

## [3.17.0] - 2026-08-12

### Added
- **`sentinel`, a post-merge triage worker, and `/crew:triage`.** Takes a bug report, stack
  trace, or alert; returns the code it points at plus deploy-correlated suspect commits with an
  explicit confidence. Read-only, and `morpheus` can delegate to it before planning a
  regression fix (#175).

## [3.16.0] - 2026-08-11

### Fixed
- **Chrome DevTools installed as a plugin now reaches `seraph` and `trinity`.** 3.15.0 assumed a
  plugin and the server it bundles share a name; the real `chrome-devtools-mcp` plugin ships a
  server called `chrome-devtools`, so its tools are
  `mcp__plugin_chrome-devtools-mcp_chrome-devtools__*` and the allowlisted
  `mcp__plugin_chrome-devtools_chrome-devtools` matched nothing. Corrected, and Playwright's
  `<name>-mcp` packaging (`mcp__plugin_playwright-mcp_playwright`) added alongside.

### Changed
- Validator §13 pairs the two grant forms on the **server** half by suffix, instead of requiring
  the plugin and server names to be equal — the assumption that hid this.

## [3.15.0] - 2026-08-11

### Fixed
- **A server installed as a plugin no longer reads as missing.** A plugin-bundled MCP server's
  tools are named `mcp__plugin_<plugin>_<server>__<tool>`, which the agents' bare `mcp__<key>`
  grants never matched — the agent saw a configured, running server as unavailable. Every agent
  now allowlists `mcp__plugin_<key>_<key>` alongside each bare key.
- Same gap, two more install paths: `figma-desktop` (the key Figma's own install docs use for the
  Dev Mode server) and the bare `mcp__<Name>` form a claude.ai connector takes on claude.ai's own
  surfaces — previously only the CLI's `mcp__claude_ai_<Name>` was allowlisted, and only for
  Figma. Figma, GitHub, Linear, Atlassian, and Sentry now carry both connector forms.

### Added
- Validator §13: agent `tools:` MCP grants must be server-scoped and carry both install paths.
  Reads either YAML shape of `tools:`, rejects tool-scoped (`mcp__server__tool`) and serverless
  (`mcp__*`) grants, and exempts hosted connectors (`mcp__claude_ai_Figma`) by name.
- `/crew:init` §5 — report-only MCP namespace check (no config slot, nothing written).

### Changed
- Workers name the server they expected when they report one missing, instead of silently
  working without it; `morpheus` relays it with the namespace to check.
- README's *Optional MCP servers*: how to derive the namespace for a plugin-installed server.

## [3.14.0] - 2026-08-09

### Added
- `morpheus`: steers a still-running worker via `SendMessage` for small, in-lane corrections,
  instead of waiting for it to return and re-dispatching (#176). Plan steps carry `agent-id:`
  as the address.

## [3.13.1] - 2026-08-07

### Changed
- `morpheus`: moved design rationale out of the always-loaded prompt into the repo's
  `AGENTS.md` ("Prompt design rationale"), behind a single pointer line. Every behavioral
  instruction, threshold, and edge-path outcome is unchanged.

### Added
- Optional `loaded-lines-cap` agent frontmatter key, enforced by validator §12, which also
  reports every agent's always-loaded footprint (agent file + preloaded skills). `morpheus`
  caps at 480 lines.

## [3.13.0] - 2026-08-06

### Added
- **Agents declare their write-access facts, and CI checks them.** Every crew agent now
  carries `owns-git: true|false` and `lane-guarded: true|false` in its frontmatter, and
  validator §9 keeps those in lockstep with the rosters `bash-safety.sh` and `lane-guard.sh`
  gate on — both directions, the same shape §8 already uses for `maxTurns`.

  Both guards match a hardcoded list of agent names, so a name missing from one **fails
  open**: adding an eighth agent would have silently given it unrestricted git and no write
  lane, with nothing to catch it. §9 makes that a CI failure — an agent that declares
  neither field, a roster entry naming no real agent, a Bash-capable non-owner missing from
  the no-git roster, the git owner wrongly listed in it, or anything other than exactly one
  `owns-git: true` per plugin. Bash-less agents (`seraph`) need no no-git entry, since
  "can run git at all" is already derivable from `tools:`.

  Each roster is preceded by a `# crew-roster: <name>` marker; the marker, the `case` header,
  and the `a|b|c)` arm on the line after it are load-bearing. The parse is pinned to exactly
  that shape rather than "first arm-looking line after the marker" — these hooks hold other
  case statements (`bash-safety`'s protected-branch `main|master|develop)`), and an unbounded
  scan would silently read the wrong roster if the arm's formatting changed. Reformatting the
  arm now reports the roster unverifiable. Removing a marker while agents still declare the
  fields is likewise a failure, so the check can't be silently disabled. The section is
  opt-in per plugin — `keymaker`, which gates git differently, is untouched.

  Not covered: `lane-guard.sh`'s per-agent dispatch arms further down. They sit inside a
  nested `case` on the e2e tool, and a parser that can't reliably separate the two would
  report false lockstep; the hook's own comment still holds those in sync.

## [3.12.0] - 2026-08-06

### Fixed
- **`format.sh`: every formatter now runs under a wall-clock bound** (`CREW_FORMAT_TIMEOUT`,
  default 20s). A hung formatter previously stalled the agent for the hook's whole budget
  after *every* edit, and the harness's kill could land mid `--write`. Uses
  `timeout`/`gtimeout` when present, degrades to an unbounded run when neither is (stock
  macOS/BSD), and reports a hang distinctly from a formatter that failed.
- **`lane-guard.sh`: stack detection walks the tree once instead of up to four times**, and
  publishes its per-session cache by `mv` so parallel workers sharing a session can't read a
  half-written one.

### Changed
- **`turn-budget.sh` bails before forking `jq`** when the payload carries no `agent_type` —
  it is wired to PostToolUse `*`, so it ran on every tool call in every session, including
  the user's own where it always no-ops.

### Added
- **Hook tests for `format.sh`** (previously the one uncovered hook, and the one that mutates
  the user's files), and for `lane-guard.sh`'s marker detection — one fixture per framework
  allowlist entry, so an entry dropped from the hook fails a test instead of silently
  disabling the same-language ambiguity guard.

## [3.11.0] - 2026-08-06

### Added
- **Turn-budget sensor: workers wind down instead of truncating mid-task.** A new
  `turn-budget.sh` PostToolUse hook counts each crew agent's tool calls against its
  `maxTurns` (a deliberately conservative heuristic — tool calls ≥ turns) and warns it once
  at 75% (finish the sub-task in flight, stop at a safe boundary, report `remaining:`) and
  once at 90% (stop now). Near-budget work ends as an orderly partial return `morpheus`
  commits and resumes as a planned stop; the truncation-reconcile path stays as the backstop.
  Advisory by design: the hook fails open on every path where it can't count.
- **Validator §8 keeps the hook's budget table in lockstep with agent frontmatter.** Every
  agent's `maxTurns` must have a matching `budget=` entry (and no stale rows), so a future
  `maxTurns` edit that forgets the hook fails CI instead of silently miscalibrating the
  warnings.

### Changed
- **Turn budgets raised where truncation actually bites.** `morpheus` 80→96, `tank`/`trinity`
  56→72, `oracle`/`dozer` 40→56, `neo` 40→48 (`seraph` unchanged) — test authoring proved as
  turn-hungry as implementation; headroom stays secondary to the wind-down sensor.

## [3.10.0] - 2026-08-06

### Added
- **`morpheus` never counts on continuing a running worker.** `Agent` always spawns a fresh
  worker, and morph can't rely on a `SendMessage`-style continue tool (its canonical
  `claude --agent crew:morpheus` launch typically has none) — so "extend the scope of the
  running worker" just spawned a second worker into the first's scope. `morpheus` now widens an
  in-flight worker by waiting and re-dispatching a fresh, wider step (or splitting at planning
  time), carrying context via the plan file rather than a live agent's memory.
- **One writer per file, one owner per shared artifact.** Workers may author disjoint files
  concurrently, but shared setup (fixtures, helpers, base classes, config) gets a single owning
  step the rest `depends-on` — two blind workers would each recreate it and clash. To collapse an
  overlap or replace a mis-scoped worker, `morpheus` stops one worker, reconciles its partial
  writes against the tree (as for a truncated return), then dispatches a single replacement; it
  never races two writers over the same file or setup.

## [3.9.0] - 2026-08-05

### Added
- **`morpheus` now detects and resumes a worker that was cut off mid-task.** A worker that
  exhausts its own `maxTurns` returns a truncated result as an ordinary completion — previously
  indistinguishable from finished work, so it could be accepted as done. `morpheus` now judges
  each return for completeness — a result that ends mid-step or is missing the required pass/fail
  evidence — keeps and commits whatever sub-part is complete, and
  re-dispatches the remainder as a fresh narrower step — reusing the durable-resume
  "`in-progress` is unconfirmed" rule. A truncation-resume does not consume a retry-cap attempt.

### Changed
- **Dispatch scoping is now explicit: author and verify in separate dispatches, sized to fit
  the turn budget.** Bundling implement + write tests + run + fix into one dispatch is what
  overflows a worker's budget; `morpheus` now splits authoring from a separate `haiku`
  run-and-report step and splits oversized plan steps at planning time.
- **Authoring workers report an explicit completion marker.** `tank`, `trinity`, and `neo` end
  with what they completed plus a `remaining:` line when anything is left undone; `oracle` and
  `dozer` must report an unfinished run as unfinished rather than letting silence read as green.
- **Modest `maxTurns` headroom for the workers that were truncating.** `tank`/`trinity` 40→56,
  `oracle`/`dozer`/`neo` 30→40 (`seraph` unchanged) — headroom for real feature slices, secondary
  to the detection/resume and scoping changes above.

## [3.8.0] - 2026-08-05

### Added
- **`morpheus` now emits a compact status pulse during interactive background runs.** On
  dispatching background workers and on each completion-resume, it surfaces a one-line status
  (what finished, what's still running, what's queued) from the plan file — so a long
  `/crew:feature` run no longer reads as dead air while workers grind. Foreground `/crew:loop`
  ticks are unaffected.

## [3.7.1] - 2026-07-21

### Fixed
- **`lane-guard.sh` framework detection now recognizes more mainstream frameworks.** When the
  stack slots are *unset* and no lane paths are configured, the guard probes `package.json`
  markers to decide whether extension-based lanes are safe. The allowlists had drifted behind
  the ecosystem, so a repo built only on an unlisted framework was read as "no backend/frontend
  detected" and the same-language ambiguity guard silently didn't fire — falling back to
  extension lanes that can't separate tank from trinity. Added `hono`, `elysia`, `@trpc/server`
  (backend) and `nuxt`, `gatsby`, `@remix-run/react`, `react-router`, `@builder.io/qwik`
  (frontend). Documented in `plugins/crew/CLAUDE.md` that the lists need periodic review.

## [3.7.0] - 2026-07-18

### Added
- **Two new principles in the `engineering-principles` skill: `Observability` and `Backward
  compatibility`.** Observability — make failures diagnosable (log with enough context, surface
  errors where they'll be seen, match the repo's logging idiom, keep the happy path quiet).
  Backward compatibility — don't break existing callers or data (preserve public signatures,
  serialized formats, and observable behavior unless changing them is the task; migrate or
  version deliberately). Shipped byte-for-byte by the standalone `engineering-principles`
  plugin too (v1.2.0).

## [3.6.0] - 2026-07-18

### Added
- **New `Security` principle in the `engineering-principles` skill.** Treat external input as
  untrusted (validate/encode at trust boundaries, prefer the framework's safe API over
  hand-rolled escaping), never hardcode or log secrets, and default to least privilege. Closes
  the gap where the crew reviewer's security pillar had no matching rule in the skill. Shipped
  byte-for-byte by the standalone `engineering-principles` plugin too (v1.1.0).

## [3.5.2] - 2026-07-16

### Changed
- **Relicensed from MIT to Apache-2.0** (repo-wide; all plugins move together). Apache-2.0
  adds an explicit patent grant with litigation-termination and a trademark carve-out, and
  clears corporate OSS-policy review more readily. No behavior change; the manifest's
  `license` field and the repo `LICENSE` are updated.

## [3.5.1] - 2026-07-16

### Changed
- **The validator moved out of the plugin: `plugins/crew/scripts/validate-plugin.sh` →
  repo-root `scripts/validate-plugin.sh`.** It is repo tooling, not plugin behavior — it
  validates every plugin, the marketplace, and this repo's dev-time hook mirror, requires the
  marketplace monorepo layout, and never runs in an installed plugin (nothing in any agent,
  command, or hook invokes it). Installed crew trees no longer carry the inert script, and
  future validator-only changes stop being crew releases. CI and all doc references updated;
  the script itself is unchanged.
- **The changelog moved into the plugin: repo-root `CHANGELOG.md` → `plugins/crew/CHANGELOG.md`.**
  The mirror image of the validator move: release notes are consumer docs and every other
  plugin already ships its own, while crew's at the repo root read as a repo-wide changelog
  and needed special cases in both `validate-plugin.sh` §2h and `auto-release.yml` (whose
  root fallback its own comment warned against). Both special cases are gone; changelogs are
  uniform at `plugins/<name>/CHANGELOG.md`.

## [3.5.0] - 2026-07-16

### Added
- **Cross-plugin hook-script sync check (validate-plugin.sh §5).** A hook script filename
  shipped by more than one plugin must now stay in sync across every copy, mirroring §4's rule
  for skills (crew's copy is the reference when crew ships the file). Files with no markers
  must be byte-identical (`read-guard.sh`); files that delimit shared regions with
  `# --- BEGIN/END shared guard: <label> ---` markers (`bash-safety.sh`) may diverge outside
  the marked regions — per-plugin git policy differs — but every marked region must match
  byte-for-byte. Both `bash-safety.sh` copies now carry those markers around the
  destructive-ops, watch-command, and raw-read blocks; the mirror was previously documented
  but unenforced, so a regex fix in one copy could silently drift the other.
- **Hook wiring cross-check (validate-plugin.sh §6).** Every `command` in a plugin's
  `hooks/hooks.json` must resolve through the `"${CLAUDE_PLUGIN_ROOT}"/` prefix to a file that
  exists in that plugin, and every `hooks/*.sh` on disk must be wired by some command — an
  unwired guard script silently never runs, the same failure class §2g catches for agent
  `skills:` references. The former §5 (dev-time settings mirror) is now §7.
- **Marketplace description sync (validate-plugin.sh §2f).** A marketplace entry's
  `description` must equal its plugin manifest's (`plugin.json` is canonical); the two had
  quietly drifted for crew and keymaker.

### Changed
- **`read-guard.sh` allows bounded reads.** A `Read` carrying an explicit `limit` of at most
  2000 lines now passes regardless of file size — a bounded slice is exactly the targeted
  access `context-discipline` asks for, and the guard previously forced grep even for a
  disciplined 100-line read of a large file. Reads with no `limit`, a limit over 2000, or a
  non-numeric limit still hit the 64 KiB size block. keymaker ships the same guard
  byte-for-byte; its copy moves in lockstep (keymaker v0.7.0).
- **CI runs once per PR commit.** `validate.yml`'s `push` trigger is scoped to `main` (PR
  branches are covered by `pull_request` events, so the bare trigger ran everything twice) and
  a concurrency group cancels superseded runs. `auto-release.yml` fetches tags instead of full
  history, and the `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` opt-in is gone — Node 24 has been the
  default Actions runtime since 2026-06-16.

## [3.4.0] - 2026-07-08

### Added
- **`/crew:loop <goal>` — the outer-loop driver (#102).** A thin main-session wrapper on the
  harness's native `/loop` in dynamic (self-paced) mode: each tick re-launches `morpheus`
  directly (the same agent `/crew:feature` runs, told a loop is driving it) so a feature that
  outlives one run's `maxTurns` finishes without the user re-asking each time. The durable `plan-<feature>.md` is the only cross-tick state — each tick
  reads it and ends the loop on the `loop-engineering` contract: success (all steps `done` +
  gate GO — never auto-push/PR), a step `blocked` on a human decision, or the iteration cap
  (`iterations: n/max`, model-enforced). An outer-loop tick runs `morpheus`'s workers in the
  **foreground** and to a stopping point, so a tick returns only when nothing is still running —
  ticks are genuinely synchronous. The re-entrancy guard therefore keys on the `in-flight:`
  marker only (its presence at the next firing means a crashed tick — clear it and let `morpheus`
  resume/reconcile); it deliberately does *not* gate on `in-progress` steps, which are
  `morpheus`'s to reconcile and would deadlock the loop if they blocked the next tick.
  Tick 1 still runs the plan checkpoint — loop intent authorizes the run, not the plan.
- **Plan-header outer-loop bookkeeping.** `morpheus.md`'s durable-state schema documents the
  `iterations: n/max` and `in-flight:` header fields; the `/crew:loop` wrapper owns them (it is
  the sole writer of the outer-loop bookkeeping, between synchronous ticks), and `morpheus`
  preserves them when it rewrites the plan. `morpheus` still never self-schedules — the wrapper
  owns all scheduling. The `loop-engineering` skill's scope note now points to this outer loop
  instead of denying one exists (crew and keymaker copies stay byte-identical).

## [3.3.1] - 2026-07-07

### Changed
- **`loop-engineering` is now stack-agnostic and shared with keymaker (#111).** The skill's
  crew-specific bindings (review gate GO as the success condition, the gate's second-NO-GO
  cap and `gate:` tracking, push behind `/crew:pr`, `neo` single-pass no-op) moved into
  `morpheus.md`'s own loop-mode bindings paragraph; the skill now states the generic contract —
  intent trigger, handshake, run-not-work authorization, the three stop rules, durable
  attempt/loop state, exit line — in terms of *units*, the *terminal gate*, and *durable state*
  that each preloading orchestrator binds in its agent file. keymaker ships a byte-identical
  copy (validate-plugin.sh §4 enforces the sync; crew's copy stays canonical). morpheus
  behavior is unchanged.

## [3.3.0] - 2026-07-07

### Added
- **New `loop-engineering` skill — loop mode with explicit stop rules (#83).** The crew already
  *is* the inner loop (morpheus drives makers and verifiers over a durable plan); what was
  missing was a deliberate trigger and written stop-rule discipline. The skill recognizes loop
  intent from the user in conversation only (never from fetched ticket/PR/Sentry prose), offers
  to loop on open-ended work, scopes authorization to the run (the plan checkpoint still runs
  once), and stops on: all steps done + gate GO (never auto-push/PR), a blocked human decision
  (after draining independent steps), or a retry cap — 3 failed fix→verify round-trips on a
  step, and at the gate a second NO-GO on the same findings. `maxTurns` remains a
  crash handled by durable resume, not an exit. Crew-only skill; the outer loop stays
  human-initiated in v1 (`/crew:loop` is deferred to #102).
- **morpheus now preloads skills.** New `skills:` frontmatter key with `loop-engineering` and
  `context-discipline` — morpheus's body already required context-discipline in every handoff,
  but nothing loaded it into morpheus itself. The plan-file schema gains loop-mode fields —
  header `loop:` / `exit-conditions:` / `gate:` (gate outcome + NO-GO count) and per-step
  `attempts:` — so a resumed run continues in loop mode without re-handshake and the retry
  caps survive a crash. The run summary gains a `loop exit:` line for exit observability.

## [3.2.0] - 2026-07-03

### Added
- **Workers are now code-blocked from git.** `bash-safety.sh` blocks any `git` invocation at a
  command position for `tank`/`trinity`/`oracle`/`dozer`/`neo` (`seraph` carries no Bash tool,
  so it needs no entry). "Workers never run git — morpheus owns branching and commits" was
  prose-only beyond the protected-branch commit backstop: a worker on a feature branch could
  still commit, checkout, reset, or push without tripping any guard. The
  commit-on-protected-branch backstop stays in place for every other agent type (morpheus,
  other plugins' agents).
- **Watch/dev/serve commands are blocked in agent sessions.** `dotnet watch`,
  `npm|pnpm|yarn|bun [run] dev|start|serve|watch`, bare `vite` (`vite build` stays allowed),
  `next`/`nuxt dev`, `ng serve`, `nodemon`, `webpack serve`, and the bare `--watch` flag
  (`--watch=false` stays allowed) never terminate — an agent turn that launches one hangs until
  its maxTurns/timeout. This enforces morpheus's "One-shot build, bounded" rule in code. Scoped
  via `agent_type`, so the user's own session can still run a dev server.

## [3.1.7] - 2026-07-02

### Changed
- **`validate-plugin.sh` now enforces that `.claude/settings.json` mirrors
  `plugins/crew/hooks/hooks.json`.** This repo wires its four crew guards
  twice — once for the installed plugin (`hooks/hooks.json`, resolved via
  `CLAUDE_PLUGIN_ROOT`) and once for developing in this repo without the
  plugin installed (`.claude/settings.json`, resolved via
  `CLAUDE_PROJECT_DIR`). The two had to be kept in sync by hand with nothing
  catching drift; a new check (§5) compares each hook's event, matcher,
  script, and timeout across both files (normalizing away the root-variable
  difference) and fails CI on any mismatch. `AGENTS.md` now also explains why
  both wirings exist and that installing the plugin while developing in this
  repo isn't a supported setup (every guard would run twice).

## [3.1.6] - 2026-07-02

### Changed
- **`validate-plugin.sh`'s skill-drift check is now generic by skill name, not hardcoded to
  crew.** It used to only iterate `plugins/crew/skills/*/` and compare each against same-named
  skills elsewhere — so it would never catch a duplicate skill shared between two *non-crew*
  plugins. It now groups every `SKILL.md` across all plugins by its directory basename and
  compares every plugin shipping that name, so any future duplication is caught regardless of
  whether crew is a party to it. When crew does ship the skill, its copy remains the reference
  (crew is the documented canonical source), matching the existing behavior for today's two
  pairs (`engineering-principles`, `context-discipline`) exactly. `AGENTS.md` documents the
  convention generically and calls out both pairs explicitly (previously only
  `engineering-principles` was documented in prose; `context-discipline`'s sync requirement was
  enforced but unmentioned).

## [3.1.5] - 2026-07-02

### Changed
- **`morpheus.md` trimmed from ~27 KB to ~22 KB (~19%), by consolidating repeated content.**
  The resolution ladder ("`CLAUDE.md` pin → local memory → detect/ask, then remember, then
  pass in the delegation") was restated nearly verbatim across five separate sections —
  frontend mode, backend/frontend stack, frontend e2e tool, frontend unit test tool, and base
  branch/branch-naming. It's now stated once in a new **Resolving crew configuration** section,
  with a compact table (slot · values · detection markers · consuming worker/skill) replacing
  the five prose sections. No slot's values, detection markers, confirm-vs-assume rules, or
  "pass the resolved value in every delegation" requirement were dropped — the anti-drift
  rule's plan-schema restatement was also trimmed to a pointer at *The plan file is durable
  state*, and several other verbose sections were tightened without losing distinct rules.
  This is loaded as `morpheus`'s system prompt on every orchestration session (up to
  `maxTurns: 80`), so the savings apply per session, not once.

## [3.1.4] - 2026-07-02

### Changed
- **`/crew:review`'s design-conformance check is now scoped to the frontend
  lane**, same as the executable build/test/lint gates in step 2. It used to
  delegate to `crew:seraph` unconditionally, spawning a design-conformance
  review (and its browser/Figma MCP traffic) even for a backend-only diff,
  where it's unlikely there's a rendered-UI change to compare — a cost
  heuristic, not a guarantee (`full` mode still runs it unconditionally).
  Skipped runs are reported in the gate summary with reason *lane untouched*,
  consistent with the other gates.

## [3.1.3] - 2026-07-02

### Changed
- **`format.sh`'s per-edit dotnet formatting is lighter weight.** It used to run
  full `dotnet format --include "$path"` (whitespace + style + **analyzer**
  fixes) on every edited `.cs` file — evaluating analyzers against the
  containing project, which can take 10-60s on real solutions. That full check
  already runs once, at the review gate (`dotnet format --verify-no-changes`),
  so paying it again per edit added little. Per edit now: CSharpier when the
  solution configures it (`.csharpierrc`) — it formats a single file directly
  without evaluating the project — otherwise `dotnet format whitespace`, which
  skips analyzer evaluation.
- **`eslint --fix` runs with `--cache`** in the web formatting lane, so repeated
  edits in the same area reuse ESLint's cache instead of re-linting cold.

## [3.1.2] - 2026-07-02

### Changed
- **`lane-guard.sh` and `bash-safety.sh` parse their hook payload in one `jq`
  call instead of three.** Both hooks separately parsed for payload validity,
  `agent_type`, and the relevant field (`path` / `command`) — three process
  spawns on every matching tool call. Each field is now extracted in a single
  `jq` call (whose own exit status doubles as the validity check), joined with
  a record-separator byte and split in the shell.
- **`lane-guard.sh` bails out immediately for the main session and any agent
  without a lane**, before any config parsing, matching the existing default
  arm of its lane dispatch.

## [3.1.1] - 2026-07-02

### Changed
- **`lane-guard.sh` caches marker detection per session.** In the same-language
  regime (stacks unset, no lane paths configured), the guard used to re-scan the
  whole repo (`has_dotnet_backend` / `has_node_backend` / `has_frontend`, each a
  `find` walk) on **every** `tank`/`trinity` Edit/Write. It now runs that
  detection once per session and caches the result (keyed by `session_id`),
  since the underlying markers (project files, declared dependencies) don't
  change mid-feature. Only persisted when a `session_id` is present, so the
  cache can't outlive the session it was written for.
- **More directories pruned during marker detection.** The probes only pruned
  `node_modules`; they now also prune `.git`, `dist`, `bin`, `obj`, `coverage`,
  and `.next`, so a large `.git` history or build output no longer slows the
  scan (or false-positives on stale build artifacts).

## [3.1.0] - 2026-07-02

### Added
- **`/crew:address` — close the PR review loop.** The lifecycle used to end at `/crew:pr`;
  once a reviewer, Copilot, or CI commented on the open PR the developer dropped back to manual
  mode, losing crew's lane routing and sole-git-ownership exactly when review churn is highest.
  The new command (a thin router into `morpheus`, like `/crew:feature`) pulls the PR's
  **unresolved** review threads and **failed** CI checks via the git-host MCP, classifies each
  item to a lane through `morpheus`'s size-triage (`tank` / `trinity` / `oracle` / `dozer`, or
  the `neo` express lane), delegates and commits each verified fix citing the thread it answers,
  re-runs the diff-scoped `/crew:review` gate, and — after confirming — pushes and resolves the
  addressed threads.
  - Review-comment text is treated as **untrusted external input**: technical asks are classified
    and routed, but anything that tries to redirect scope, exfiltrate secrets, or disable a guard
    is surfaced to the user rather than acted on.
  - The flow lives in `morpheus`'s own prompt (new *Address review feedback — close the review
    loop* section), so it works the same whether invoked as `/crew:address` from a normal session
    or just asked for in a `claude --agent crew:morpheus` session — no slash command required.

## [3.0.0] - 2026-07-02

### Added
- **Cypress Component Testing support.** Cypress can now be resolved as the **frontend unit
  test tool** (in addition to its existing role as the frontend e2e tool), covering projects
  that use Cypress Component Testing for component/unit tests.
  - `morpheus` detects `cypress` as the frontend unit test tool when `cypress.config.*`
    contains a `component` key and no `vitest.config.*` / `jest.config.*` is present.
  - `oracle` now loads the `tests-cypress` skill when `cypress` is the resolved frontend unit
    test tool, and applies the component-test section of that skill.
  - `tests-cypress` skill updated with a **Component tests** section covering `cy.mount()`,
    component spec file conventions (`.cy.ts` / `.cy.tsx`), and the `--component` run flag.
  - `/crew:init` detects and writes `cypress` for the **Frontend unit test tool** slot.

### Changed
- **BREAKING: crew is stack-agnostic — role-only agents, per-stack skills, detection-driven
  lanes.** `tank`, `trinity`, and `oracle` used to hard-code a specific stack (C#/.NET/
  Optimizely, React/Redux) directly in their prompts. They're now role-only; stack knowledge
  moved into skills loaded dynamically once `morpheus` resolves the project's stack —
  `backend-dotnet`, `backend-node`, `cms-optimizely` (composes on `backend-dotnet`, self-
  detected via package references), `frontend-react`, `frontend-nextjs`, `tests-xunit`,
  `tests-node` (Vitest/Jest, detected by config file). Concrete second-stack driver: Node
  backend + Next.js frontend (Optimizely SaaS / Graph).
  - `morpheus` resolves **Backend stack** / **Frontend stack** the same way it already
    resolves frontend mode (`CLAUDE.md` pin → memory → detect-and-ask), names the resolved
    stack in every implementation and test delegation, and never delegates without one
    resolved. `/crew:init` detects and writes both new slots.
  - `lane-guard.sh` gets a second lane regime: directory-based paths (**Backend lane
    path(s)** / **Frontend lane path(s)**, new `CLAUDE.md` slots) for same-language stack
    pairs (e.g. Node+Next.js) where a bare file extension can't tell `tank`'s and
    `trinity`'s files apart. Falls back to the existing extension-based globs otherwise. A
    Node backend with no lane paths configured fails closed rather than guessing. A Next.js
    route handler is exempted from `tank`'s deny / added to `trinity`'s deny, since — unlike
    Razor's genuinely bidirectional markup/logic split — route-handler ownership is
    single-owner (tank's, by concern) even though the file lives in the frontend tree.
  - `format.sh` now routes by the edited file's **extension** (restricted to a known set of
    web extensions) instead of a fixed `agent_type → lane` table, so a Node-backend file
    `tank` edits still gets Biome/Prettier/ESLint, a `.cs`/`.csproj` file gets dotnet/
    CSharpier regardless of which agent produced it, and an unrelated extension (e.g.
    `.cshtml`) is skipped cleanly instead of triggering a mismatched formatter.
  - `frontend-server-rendered` reframed from Razor-only to a shared-principles section plus
    per-template-language subsections (Razor, Blade) — Next.js/RSC is deliberately not one
    of them, since Next.js is categorically `headless` in crew's mode vocabulary even though
    it server-renders; RSC conventions live in `frontend-nextjs` instead.
  - `tank`, `trinity`, and `oracle` gain explicit `Skill` tool access (a pre-existing gap:
    trinity's frontend-mode skill loading used "via the Skill tool" without it since #19).
  - Why a major bump: agent descriptions and `lane-guard.sh`'s enforcement semantics change
    — a project relying on the old fixed `tank`=.NET/`trinity`=React assumption should
    re-check its `CLAUDE.md` crew configuration after upgrading (`/crew:init` reconciles it).
  - `dozer` is now also role-only and e2e-tool-agnostic: tool knowledge moved to per-tool
    skills `tests-cypress` (Cypress conventions, extracted from `dozer`'s implicit knowledge)
    and `tests-playwright` (new, Playwright conventions). `morpheus` resolves the **Frontend
    e2e tool** (`cypress` or `playwright`) the same way it resolves the backend/frontend stack,
    names it in every `dozer` delegation, and `/crew:init` detects and writes the new slot.
  - `oracle` is extended from backend-only to all unit test authoring: when `morpheus` also
    resolves a **Frontend unit test tool** (`vitest` or `jest`), it passes it in the `oracle`
    delegation so oracle additionally loads the matching skill (`tests-vitest`) and covers
    frontend component tests. A project can therefore use multiple test tools simultaneously
    (e.g. Playwright e2e + Vitest component tests) — `dozer` handles e2e, `oracle` handles
    unit/component. `/crew:init` detects and writes the new slot. `lane-guard.sh` broadens
    oracle's allowlist to include co-located component test file patterns (`**/*.test.*`,
    `**/*.spec.*`, `**/__tests__/**`). (Closes #82.)
  - `seraph` is unchanged (already tool-neutral via whichever browser-automation MCP is
    configured). keymaker is unaffected (already stack-agnostic by its own design). (Closes
    #46.)

## [2.10.0] - 2026-07-02

### Added
- **`morpheus` right-sizes the process by task size, with a new `neo` express-lane generalist.**
  Small tasks (a typo, a rename, an obvious one-liner, a small localized bug) used to pay the same
  heavyweight process as a full feature — a plan file, the plan checkpoint, lane specialists, and
  the full review gate — which made a one-line fix slow. `morpheus` now triages by size: small,
  low-risk work takes an **express lane** — it delegates to the new `neo` agent (an all-lane
  generalist), skips the plan/checkpoint/full-gate, runs a quick read-only self-review
  (`/crew:review quick`) plus any single directly-relevant test, and commits. Features and anything
  risky, multi-lane, or needing new tests still take the full flow through the specialists, and
  `morpheus` escalates express → full the moment a task proves bigger. `morpheus` stays the sole
  git owner and never writes production code itself — `neo` makes the change, `morpheus` reviews it,
  preserving the maker↔verifier split. `neo` holds the same `engineering-principles` bar as the
  specialists (the express lane is faster, not sloppier), never runs git, and reports back to
  escalate rather than plowing ahead when a task exceeds the express lane. The `lane-guard` hook
  grants `neo` all lanes by design; `format` picks .NET or web formatting by the edited file's
  extension.

## [2.9.0] - 2026-07-02

### Added
- **Fix-verify loops rerun only the affected tests, not the full suite.** Previously, once
  `oracle`/`dozer` reported failures and `morpheus` routed a fix back to the implementer,
  re-confirming the fix meant rerunning the *entire* backend/e2e suite again — even though the
  full suite is already established as the final review gate's job, run once when the work
  queue is drained. `oracle` and `dozer` now re-run only the specific test(s)/spec(s) that were
  previously failing when asked to confirm a fix, and `morpheus` names those failing test(s) in
  the re-delegation so the worker has something to target instead of defaulting to a full run.

## [2.8.1] - 2026-07-02

### Changed
- **Trim `/crew:feature` and the review gate for token cost, behavior-neutral.**
  `commands/feature.md` restated `morpheus`'s own durable-resume protocol, plan schema,
  checkpoint, and run-summary behavior in full on every invocation — all of it already lives
  unconditionally in `agents/morpheus.md`'s system prompt, so the restatement was pure token
  cost paid per call. It now points back to `morpheus`'s own standard flow instead. Also added
  `model: haiku` to the review gate's run-and-report delegations (`crew:oracle` tests,
  `crew:tank`/`crew:trinity` build, `crew:dozer` e2e) — `morpheus`'s own "Right-size the model
  per delegation" guidance already named these as haiku-eligible, but `commands/review.md`
  never applied it.

## [2.8.0] - 2026-06-16

### Added
- **Build gate handles contention with a running app/dev process.** When a dev server, watcher, or
  running app holds locks on build outputs, a delegated build could fail (`MSB3027`/`MSB3026`,
  "being used by another process", `EBUSY`/locked `bin`/`obj`/`dist`) or hang forever (a worker
  accidentally running a watch/dev command). The build gate now requires a **one-shot** build
  command (never `dotnet watch` / `npm run dev` / `vite` / `tsc --watch`) with a wall-clock timeout,
  and `morpheus` treats a lock/in-use error or timeout as **environmental, not a code failure** —
  it reports that a running process is likely locking the outputs and asks the user to stop the
  dev server/app and retry,
  instead of wastefully routing the "failure" back to the implementer. `tank` and `trinity` carry
  the same one-shot rule and lock-error recognition in their build instructions.

## [2.7.1] - 2026-06-16

### Fixed
- **Anti-drift rule 1's schema list now includes `worker`.** The 2.7.0 run-summary change added
  `worker` to the per-step plan schema but left rule 1's referenced field list at
  `id`/`status`/`depends-on`/`acceptance`/`evidence`, making `morpheus`'s own prompt internally
  inconsistent about which keys to maintain. Added `worker` to the list. Also tightened a changelog
  sentence so `/recap` reads as the command, not a bare noun.

## [2.7.0] - 2026-06-16

### Added
- **`morpheus` emits a run summary — observability for a completed feature.** `morpheus` now
  records `worker` per step in the plan file and emits a concise per-step table — **Step · Worker ·
  Outcome · Evidence** (commit SHA) — at the end of a feature and on request, plus a one-line
  done/blocked tally. Sourced from the plan file's parseable status (not a log dump), it survives a
  resume (when the live agent panel for earlier steps is gone) and deliberately doesn't restate the
  commit list or prose retrospective that Claude Code's `/recap` already covers — it's the
  per-worker delegation view that `/recap` can't see. (Closes #64.)

## [2.6.1] - 2026-06-16

### Changed
- **`morpheus.md` trimmed for token cost (behavior-neutral).** `morpheus.md` is the always-loaded
  system prompt in a `claude --agent crew:morpheus` session, so its size is a per-turn cost. The
  "Standard flow" no longer restates the dedicated sections that follow it (it now names each phase
  and points to them), `<plan-dir>` is defined once instead of in three places, and the build-gate
  wording is tightened — ~4% fewer words with no rule added, removed, or changed.

## [2.6.0] - 2026-06-16

### Added
- **Crew runs are resumable from the plan file.** A crashed or context-reset session used to
  mean re-explaining the feature, even though `<plan-dir>/plan-<feature>.md` already recorded the
  steps. The plan file is now durable state with a parseable schema — a header (`feature:`,
  `base-branch:`, `feature-branch:`) plus per-step `id:` / `status:` (`pending` | `in-progress` |
  `done` | `blocked`) / `depends-on:` / `acceptance:` / `evidence:` (commit SHA) — and `morpheus`
  follows a **resume protocol** on (re)start: if a matching plan exists it checks out the feature
  branch, reconciles each step's status against git (a `done` step must map to its `evidence`
  commit; an unconfirmed `in-progress` step is re-verified and reset to `pending` if its
  acceptance isn't met), and picks up the first unblocked step — without asking the user to
  re-explain. `agents/morpheus.md` defines the schema and protocol; `commands/feature.md` enters
  it (resume an existing plan instead of re-planning). Only a committed step is ever `done`.

## [2.5.0] - 2026-06-16

### Added
- **Configurable per-repo plan location.** A new `Plan directory` crew-config slot lets a repo
  choose where `morpheus` writes `plan-<feature>.md` — e.g. a committed `docs/plans/` — instead
  of always `.claude/`. `morpheus` resolves it the usual way (`CLAUDE.md` crew configuration →
  local memory → the `.claude/` fallback) once per project and reads/writes plans there;
  `commands/feature.md` and `commands/pr.md` reference the resolved `<plan-dir>` rather than a
  literal `.claude/` path. `/crew:init` adds the slot to its canonical catalog and only proposes
  a value when the repo has an obvious plans convention, otherwise leaving it *unset* so the
  `.claude/` fallback applies. Default behavior is unchanged for repos that don't set it.

## [2.4.0] - 2026-06-16

### Added
- **Plan checkpoint — `morpheus` confirms the plan before building.** After writing
  `.claude/plan-<feature>.md`, `morpheus` now presents the plan (scope, ordered steps with
  acceptance criteria, base branch, frontend mode, assumptions) and waits for the user's
  explicit go-ahead **before** creating the feature branch or delegating any step — background
  steps included. It's a single gate, not a prompt per step: a one-step task is a one-word
  approval, and a standing "just build it" (in the request or a remembered preference) is
  honored as the go-ahead. Corrections are folded back into the plan and re-presented as a
  delta. `plugins/crew/commands/feature.md` carries the same checkpoint step. Catches a
  misread task at the cheapest possible point — before any worker time or commits are spent.

## [2.3.0] - 2026-06-16

### Added
- **`/crew:init` — detect and write the crew configuration.** A new command that inspects the
  project (.NET / Node tooling, git default branch, frontend stack) and proposes values for
  every crew-config slot — build/test/lint commands, base branch, branch naming, frontend
  mode, run URL — then, after the user confirms, writes them to the **Crew configuration**
  block in `CLAUDE.md` (the source `morpheus` and the `crew:*` commands already read first).
  It's **idempotent**: the first run bootstraps the block; a re-run reconciles it, adding slots
  introduced by a newer plugin version and filling placeholders **without overwriting values
  the user has already set**. If the user prefers not to commit config, it reports the detected
  values and leaves resolution to `morpheus`'s existing per-session memory.
- **`morpheus` nudges toward `/crew:init` when config is missing.** When a slot it needs is
  absent from `CLAUDE.md`, `morpheus` resolves it as before (memory → ask) and adds a single
  one-line suggestion to run `/crew:init` to persist and reconcile the configuration. It never
  rewrites `CLAUDE.md` config itself mid-feature.

## [2.2.1] - 2026-06-16

### Fixed
- **`morpheus` no longer freezes the conversation while a worker runs.** The
  "delegate in the background" guidance was soft, and the dependency-ordering rule pulled
  `morpheus` toward running a worker in the *foreground* whenever the next step needed its
  output — freezing the whole turn for the worker's entire run (often minutes) and queuing the
  user's messages unheard. `plugins/crew/agents/morpheus.md` now makes `run_in_background: true` the hard
  default for every worker delegation and spells out that backgrounding is not abandoning and
  waiting is not blocking: for a dependency, background the worker, **end the turn**, and
  dispatch the dependent step on the completion notification — never hold the turn open just to
  wait.

## [2.2.0] - 2026-06-12

### Added
- **Validator verifies each agent's `skills:` list resolves.** `plugins/crew/scripts/validate-plugin.sh`
  now parses the YAML frontmatter of every `plugins/*/agents/*.md` file and verifies each entry in
  its `skills:` list resolves to some `plugins/*/skills/<name>/SKILL.md` in the repo (unqualified,
  per existing convention). A typo here previously failed silently at runtime — the skill just
  didn't load and the agent guessed. CI now fails with a clear message:
  `FAIL: plugins/<plugin>/agents/<agent>.md skills -> <name> does not resolve to any plugins/*/skills/<name>/SKILL.md`.

## [2.1.1] - 2026-06-12

### Fixed
- **MCP README no longer conflates a server's config key with its tool namespace.** The
  allowlist note listed `mcp__`-prefixed namespaces under "name your server one of these,"
  which could lead users to name the server `mcp__playwright`. It now distinguishes the *key*
  you set in `.mcp.json` (e.g. `playwright`) from the `mcp__<key>` namespace agents allowlist,
  and lists the expected keys without the prefix.

## [2.1.0] - 2026-06-12

### Added
- **More first-class MCP servers across the crew.** Agents now allowlist additional optional
  MCP servers and use them when present (degrading gracefully when absent):
  - **Browser:** `mcp__chrome-devtools` on `trinity`/`seraph` alongside `mcp__playwright` —
    either browser MCP works zero-config; Chrome DevTools is Chrome-only but adds
    performance/Lighthouse and console/network inspection.
  - **Library & framework docs:** `mcp__context7` on `tank`/`trinity`, for current,
    version-specific API docs instead of coding from memory.
  - **Issue tracking (ticket-in):** `mcp__linear` and `mcp__atlassian` on `morpheus`, to pull
    the source ticket at planning.
  - **Database:** `mcp__mssql` and `mcp__postgres` on `tank`/`oracle`, for schema-aware
    data-access work and integration test data.
  - **Error monitoring:** `mcp__sentry` on `morpheus`, to pull stack/breadcrumb context for a bug.
  `tank` and `oracle` gain `ToolSearch` to load these servers' deferred tool schemas.

### Changed
- **MCP setup in the crew README is a purpose→server table of links** instead of inline
  install/config blocks that drift from each server's own docs. It keeps only the
  crew-specific contract: which agents use each server, the `mcp__<server>` naming the
  allowlist expects, and the fallback when a server is absent.

## [2.0.0] - 2026-06-12

### Changed
- **`/crew:ship` is folded into `/crew:review`.** The crew flow is now `feature → review → pr`.
  `/crew:review` is the single pre-PR **GO / NO-GO** gate: it runs the diff-scoped executable
  checks the ship gate used to own (lane-scoped build, backend tests, frontend e2e, backend/
  frontend lint — idempotent within a session) **and** the consolidated review (code quality,
  security, design conformance via `seraph`), then emits the `## Blocking` / `## Warnings` /
  `## Passed` sections followed by GO/NO-GO. The previous read-only review is preserved as
  `/crew:review quick` (judgment only, no suites); `/crew:review full` forces every gate
  regardless of the diff. `morpheus`, `tank`, `trinity`, and `/crew:pr` now reference the
  **review gate** instead of the ship gate, and `/crew:pr` requires `/crew:review` → GO.

### Removed
- **`/crew:ship` command.** Its behavior now lives in `/crew:review` (above). **Breaking** for
  anyone scripting or invoking `/crew:ship` directly — run `/crew:review` instead.

## [1.9.0] - 2026-06-12

### Added
- **`engineering-principles` gains a "reach for new code last" ladder.** The skill listed
  YAGNI/KISS/dependency preferences as values but no procedure. It now carries an ordered,
  stop-at-first-match ladder — not needed → don't build; stdlib/runtime → use it; native
  platform feature → use it; installed dependency → use it; collapses to a line or two → do
  that; else write the minimum that works — so implementer agents have an explicit check to
  run before writing code. Kept subordinate to *match the repo*.

## [1.8.0] - 2026-06-12

### Changed
- **`morpheus` right-sizes the model per delegation.** The Agent tool's `model` override is
  now part of the delegation contract: mechanical run-and-report steps (running an existing
  suite, ship-gate build/lint runs, post-fix re-runs) go out as `haiku` for speed, while
  anything that authors or diagnoses (implementation, new tests, failure investigation,
  visual judgment) keeps the worker's default model. When in doubt, the override is omitted.
- **Parallel dispatch is the default, not a suggestion.** Plan steps in
  `.claude/plan-<feature>.md` must declare dependencies explicitly (`depends-on: <step>` or
  `independent`), and `morpheus` dispatches every currently-unblocked step in a single
  message each round instead of serializing independent work.
- **Delegations carry the planning context.** Delegation prompts must now include the exact
  file paths to touch and the relevant snippets/contracts `morpheus` already found while
  planning, so workers start editing instead of re-exploring the repo on every spawn.
- **`tank` and `trinity` get `maxTurns: 40`.** The implementers were the only workers with
  unbounded turns; a stuck retry loop is now a bounded wait that returns a partial finding
  `morpheus` can route, matching the caps already on `oracle`/`dozer`/`seraph`.

### Fixed
- **`validate-plugin.sh` marketplace check works on Windows.** Native Windows `jq` emits
  CRLF, so the marketplace source path and plugin name carried a trailing `\r` and the
  check failed locally (`source ./plugins/crew does not exist`). The 2f loop now strips
  `\r` like the manifest-path loops already did.

## [1.7.0] - 2026-06-11

### Added
- **Figma MCP support for design-driven work.** `seraph` (visual conformance) and `trinity`
  (frontend implementation) now allowlist the `mcp__figma` and `mcp__claude_ai_Figma` servers
  plus `ToolSearch` (to load their deferred tool schemas), so `seraph` pulls the canonical
  design spec from Figma instead of a pasted export and `trinity` builds to exact
  measurements/colors/type. `morpheus` passes the Figma link/node in design delegations (it
  doesn't read Figma itself — the workers do, applying `context-discipline` to fetch the
  specific node, not whole-file dumps). With no Figma MCP present, both fall back to the
  delegation's reference — nothing breaks. README documents the Dev Mode and claude.ai options.

### Changed
- **Playwright tools are server-scoped.** `seraph`/`trinity` now allowlist the whole
  `mcp__playwright` server instead of enumerating every `mcp__playwright__browser_*` tool —
  shorter, and consistent with how the git-host and Figma servers are granted.

## [1.6.0] - 2026-06-11

### Changed
- **`morpheus` stays responsive — it delegates worker steps in the background**
  (`run_in_background`) instead of blocking its turn until each worker returns. While a worker
  (e.g. `tank`) runs, the user can keep chatting — adding comments, corrections, or new fixes —
  and `morpheus` folds them into the plan and dispatches them rather than making the user wait
  to be heard; it collects each worker's result when notified, then verifies and commits.
  Backgrounded steps must be fully specified (background agents can't prompt the user), run
  concurrently only when independent, and are committed only once their result returns verified.

### Docs
- README presents `claude --agent crew:morpheus` as a first-class alternative entry point (a
  session that *is* the orchestrator), and documents the non-blocking background delegation.

## [1.5.0] - 2026-06-11

### Changed
- **Builds are a final gate, not a per-step check.** `tank` and `trinity` no longer run the
  full backend/frontend build as a routine self-check on every change; they verify their work
  with reasoning, targeted reads, and the lint/edit loop.
- `morpheus` holds the build and full test suites until the work queue is fully drained —
  every plan step accepted and any newly added review comments or fixes folded in and
  resolved — so a single pass covers all the work instead of re-running per round-trip.
- `morpheus` **delegates** the gate rather than running it (it never runs a worker's
  build/test task): backend build → `tank`, frontend build → `trinity`, tests → `oracle`/
  `dozer`, so each worker absorbs the verbose output and returns concise findings. `/crew:ship`
  now delegates the build **per lane** (backend → `crew:tank`, frontend → `crew:trinity`).
- New `CLAUDE.md` crew-config slots **Backend build command** / **Frontend build command**
  (the old single *Build command* split in two), so the frontend build gate is real and
  symmetric with the lint pair.
- The build runs **isolated from any running app/dev process** (so it can't interfere or
  contend on locked build outputs), and `morpheus` picks **one concrete build location** at
  the start and passes that exact path in every delegation — reused for the whole session, not
  per agent or per step — so incremental and package caches stay warm.
- The ship gate is **idempotent within a session**: it records the `HEAD` SHA (and a clean
  tree) when a gate passes and skips re-running that gate while `HEAD` is unchanged and the
  tree clean, so a build/suite that just ran as the final step isn't repeated.

## [1.4.1] - 2026-06-10

### Fixed
- **`/crew:feature` now actually launches `crew:morpheus`.** The command told the *current
  session* to plan and delegate to workers itself, so the orchestrator — its anti-drift
  rules, opus model, memory, and git ownership — never ran. The command now delegates the
  whole feature to the `crew:morpheus` agent and relays its consolidated status.
- **`/crew:review` and `/crew:ship` delegate with namespaced agent types** (`crew:seraph`,
  `crew:oracle`, `crew:dozer`). The bare names don't resolve for installed plugins — the
  same failure mode fixed for `morpheus` in 1.1.3.
- **`bash-safety` bypass gaps closed:** recursive+force `rm` is now caught in any flag
  spelling (`-fr`, `-rfv`, `-r -f`, `--recursive --force`), including with other flag
  tokens interleaved or a `--` separator before the target (`rm -r -v -f /`,
  `rm -rf -- /`), force-push via short `-f` is
  blocked alongside `--force` (`--force-with-lease` still allowed), and the protected-branch
  commit check now catches git global flags before the subcommand (`git -c k=v commit`,
  `git -C dir commit`).
- **`lane-guard` allow-lanes now match repo-relative paths** (e.g. `MyApp.Tests/Foo.cs`);
  previously `**/`-anchored patterns only matched absolute paths, blocking `oracle`/`dozer`
  from legitimate test files if the harness passed a relative path.

### Changed
- `validate-plugin.sh`: `agents/` and `hooks/` are now optional per plugin (a
  commands/skills-only plugin validates clean, matching the "adding a plugin is additive"
  contract), while an *existing* dir still requires its contents (`agents/*.md`,
  `hooks/hooks.json`). New check: every `marketplace.json` entry's `source` must exist and
  its `plugin.json` name must match the entry.
- `auto-release.yml` prefers a per-plugin `plugins/<name>/CHANGELOG.md` over the shared
  root one (shared changelogs risk cross-matching versions once more plugins exist).
- Docs aligned with reality: `CLAUDE.md`'s release flow no longer instructs manual
  tagging (the workflow creates the tag + release on merge to `main`), and the plugin
  README's **format** hook description matches the 1.3.0 multi-tool behavior.

## [1.4.0] - 2026-06-08

### Added
- **`morpheus` can drive a git-host MCP for PR work.** It now allowlists `ToolSearch` (to load
  deferred MCP tool schemas — without it the host MCP can't be invoked) and the `mcp__ado` /
  `mcp__github` servers (server-scoped, matching the hosts the README documents). Combined with
  its existing unrestricted `Bash` (`az` / `gh`), this lets `/crew:pr` open and manage pull
  requests from a `claude --agent crew:morpheus` session. If your host MCP is named something
  other than `ado` / `github`, add its `mcp__<server>` to morpheus's `tools`.

## [1.3.0] - 2026-06-08

### Added
- **Backend `format.sh` now runs CSharpier.** `dotnet format` doesn't invoke CSharpier, so
  when the solution configures it (`.csharpierrc`), the formatter hook also runs
  `dotnet csharpier format <file>` for `tank` — best-effort, scoped to the changed file.
- **Diff-aware ship gate.** `/crew:ship` now scopes to the branch diff vs. the base branch:
  `morpheus` classifies changed files into backend (`*.cs`/`*.csproj`/`.cshtml`) and frontend
  (`*.ts`/`*.tsx`/`*.js`/`*.scss`/`*.css`/`*.html`/`.cshtml`) lanes and runs only the gates a
  changed lane can affect — a backend-only diff no longer runs the full e2e suite. Skips are
  reported explicitly (never silent); `/crew:ship full` forces every gate.
- **Backend lint gate** added to `/crew:ship`, symmetric to the frontend one (verify mode —
  e.g. `dotnet format --verify-no-changes` plus `dotnet csharpier check`). New `CLAUDE.md`
  crew-config slots: **Backend lint command**, **Frontend lint command**.

### Changed
- **Frontend `format.sh` applies every configured tool, not just the first match.** It now
  detects and runs Biome, Prettier, ESLint, and Stylelint (each in fix mode, scoped to the
  changed file, only when installed locally) instead of stopping at the first `package.json`
  script it found — so projects using both a formatter and linters get all of them applied.
- **`morpheus` entry-point guidance.** `/crew:feature` (run from a normal session) is now the
  documented entry point; launching a terminal *as* `claude --agent crew:morpheus` is an
  optional, explicitly scoped orchestration session that won't run general/config tasks (e.g.
  statusline) — do those in a normal session. Resolves the prior contradiction between the
  launch hint and the orchestrator's delegate-only design.

## [1.2.0] - 2026-06-05

### Added
- **Git workflow.** `morpheus` now owns version control: it resolves the project's **base
  branch** and **branch-naming** convention (`CLAUDE.md` crew config → memory → ask),
  creates a feature branch off the base, and commits each *verified* step. Workers never run
  git. New `CLAUDE.md` crew-config slots: **Base branch**, **Branch naming**.
- **`/crew:pr` command** — pushes the feature branch and opens a pull request via a git-host
  MCP (GitHub / Azure DevOps), host-agnostic, with confirmation; falls back to printing the
  `git push` command + a ready-to-paste PR body when no host MCP is present. The crew still
  stops at the local ship gate by default; push/PR is this explicit step.
- **`bash-safety` refuses `git commit` on a protected base branch** (`main`/`master`/`develop`)
  for crew agents — they branch first. Scoped via `agent_type`, so a normal main session is
  never intercepted.

## [1.1.3] - 2026-06-05

### Fixed
- **`morpheus` could not delegate to workers when installed** ("Agent type 'tank' not
  found"). Installed plugin agents are namespaced, so `morpheus` now delegates to and
  allowlists `crew:tank` / `crew:trinity` / `crew:oracle` / `crew:dozer` / `crew:seraph`,
  and its launch hint is `claude --agent crew:morpheus`.
- **Hardened `morpheus` against improvising.** Planning/delegation/synthesis are its only
  outputs; if a delegation can't be launched it must stop and report rather than copy files,
  invent project conventions, or do the worker's job itself.

## [1.1.2] - 2026-06-05

Addresses findings from a review by Anthropic's `plugin-dev` agents (plugin-validator,
skill-reviewer) and a best-practice review of the agents/hooks.

### Fixed
- **`dozer` could not create new test files** — it authors Cypress specs but its tools
  listed only `Edit`, not `Write`. Added `Write` (lane-guard already confines it to
  `cypress/**`/spec paths).
- `read-guard.sh`: replaced a fragile mixed `||`/`&&` line with an explicit `if`, and
  documented that this guard intentionally fails open (it's context-hygiene, not security).
- `format.sh`: read the hook payload once (it previously risked consuming stdin twice).

### Changed
- **`format.sh` is now project-aware.** For backend it scopes `dotnet format` to the changed
  file instead of the whole solution (slow on large repos). For frontend it discovers the
  project's own format/fix script from `package.json` (e.g. `format`, `format:fix`,
  `lint:fix`, `biome:format`) by preference order rather than guessing, and skips when the
  repo only exposes check-only scripts. Added a `timeout` to the format hook in `hooks.json`.
- **`seraph` is now strictly read-only**: removed its `memory: local` and the stale
  "memory edits allowed" rule (it has no write tools), and dropped its now-unreachable
  `lane-guard` entry.
- `dozer` `color: orange` → `magenta` (orange isn't in the documented agent palette).
- Added keyword triggers to the `frontend-headless` / `frontend-server-rendered` skill
  descriptions so they trigger outside crew preload too; aligned the `engineering-principles`
  description wording ("DRY with judgment").

## [1.1.1] - 2026-06-05

### Fixed
- **Hooks no longer fail to load with "Duplicate hooks file detected."** The standard
  `hooks/hooks.json` at the plugin root is auto-loaded, but the manifest also declared
  `"hooks": "./hooks/hooks.json"`, so it was loaded twice. Removed the `hooks` field from
  `plugin.json` (the manifest's `hooks` is only for *additional* hook files).
- `validate-plugin.sh` now rejects only the auto-loaded `hooks/hooks.json` in the manifest
  (additional hook files are still allowed and existence-checked) and asserts the root
  `hooks/hooks.json` is present.

## [1.1.0] - 2026-06-05

### Changed
- **`trinity` now owns the full client/presentation layer**, not just React/Redux/SCSS:
  it explicitly covers vanilla JS, HTML, and CSS, and — in **server-rendered** mode — the
  *markup/DOM* inside Razor views (structure, classes, ARIA, presentation). The C#/
  server-side of Razor (view-model binding, `@functions`/`@code`, data access) remains
  `tank`'s; the split is by concern, coordinated between the two. In **headless** mode
  `trinity` still never touches Razor.
- `lane-guard` updated to match: `.cshtml` is no longer denied to `trinity` (Razor is now
  shared by concern, prompt-enforced), and `tank` is now denied `*.js`/`*.mjs`/`*.html` in
  addition to the TS/JSX/SCSS/CSS it already couldn't edit.
- `tank`, `frontend-server-rendered`, and `CLAUDE.md` updated to describe the concern-split
  Razor ownership.

### Added
- **`morpheus` now resolves the frontend mode** instead of requiring it pinned in `CLAUDE.md`:
  it uses a `CLAUDE.md` override if present, else its own (local) memory, else asks the user
  and remembers the answer — then passes the resolved mode into every frontend delegation.
  `trinity` takes the mode from the delegation rather than reading `CLAUDE.md` itself.
  `CLAUDE.md`'s **Frontend mode** is now optional.

## [1.0.2] - 2026-06-05

### Changed
- **Repo restructured into a monorepo marketplace.** The `crew` plugin now lives in
  `plugins/crew/` (its own plugin root) instead of the repo root, and
  `marketplace.json` points at it via `source: "./plugins/crew"`. Adding future
  plugins is now additive (`plugins/<name>/` + a marketplace entry) with no
  collision between each plugin's `agents/`/`commands/`/`skills/`/`hooks/`.
  The installed plugin's components are unchanged — same agents, commands, and hooks.
- `validate-plugin.sh` now validates every plugin under `plugins/*`, and CI globs
  were updated accordingly.

### Added
- Per-plugin `plugins/crew/README.md`; the root `README.md` is now a marketplace
  overview with a plugin index.

## [1.0.1] - 2026-06-05

### Fixed
- **Agents now actually load when installed.** Declaring `agents` in the manifest
  (string or array) passed install validation but the agents were never discovered
  (`plugin details` reported 0). Agents now live in a root `agents/` directory and
  are auto-discovered, matching the convention used by Anthropic's own plugins.
  `plugin details` now reports all six (`morpheus`, `tank`, `trinity`, `oracle`,
  `dozer`, `seraph`).
- `validate-plugin.sh` validates array-shaped manifest fields, checks the root
  `agents/` directory, and tolerates CRLF checkouts.

### Changed
- **Commands renamed** to drop the redundant `zion-` prefix, since installed
  components are already namespaced under the plugin: `/zion-feature` → `/crew:feature`,
  `/zion-review` → `/crew:review`, `/zion-ship` → `/crew:ship`. **Breaking** for anyone
  scripting the old command names.
- `CLAUDE.md` expanded from a crew-config stub into a full project memory file.
- `.github/copilot-instructions.md` aligned with the crew reviewer (engineering-principles
  checklist + code/security/design pillars) and now requires PRs that change plugin
  behavior to bump `version` and add a changelog entry.

### Added
- `.gitattributes` enforcing LF line endings for all text files, so shell hooks/scripts
  stay valid on Linux CI and as plugin hooks.
- This `CHANGELOG.md`.

## [1.0.0]

### Added
- Initial release: orchestrated crew of agents (`morpheus`, `tank`, `trinity`,
  `oracle`, `dozer`, `seraph`), commands, skills (`engineering-principles`,
  `context-discipline`, `frontend-headless`, `frontend-server-rendered`), and hooks
  (lane guard, read guard, bash safety, formatter).

[3.1.7]: https://github.com/johantor/zion/compare/crew/v3.1.6...crew/v3.1.7
[3.1.6]: https://github.com/johantor/zion/compare/crew/v3.1.5...crew/v3.1.6
[3.1.5]: https://github.com/johantor/zion/compare/crew/v3.1.4...crew/v3.1.5
[3.1.4]: https://github.com/johantor/zion/compare/crew/v3.1.3...crew/v3.1.4
[3.1.3]: https://github.com/johantor/zion/compare/crew/v3.1.2...crew/v3.1.3
[3.1.2]: https://github.com/johantor/zion/compare/crew/v3.1.1...crew/v3.1.2
[3.1.1]: https://github.com/johantor/zion/compare/crew/v3.1.0...crew/v3.1.1
[3.1.0]: https://github.com/johantor/zion/compare/crew/v3.0.0...crew/v3.1.0
[3.0.0]: https://github.com/johantor/zion/compare/crew/v2.10.0...crew/v3.0.0
[2.10.0]: https://github.com/johantor/zion/compare/crew/v2.9.0...crew/v2.10.0
[2.9.0]: https://github.com/johantor/zion/compare/crew/v2.8.1...crew/v2.9.0
[2.8.1]: https://github.com/johantor/zion/compare/crew/v2.8.0...crew/v2.8.1
[2.8.0]: https://github.com/johantor/zion/compare/crew/v2.7.1...crew/v2.8.0
[2.7.1]: https://github.com/johantor/zion/compare/crew/v2.7.0...crew/v2.7.1
[2.7.0]: https://github.com/johantor/zion/compare/crew/v2.6.1...crew/v2.7.0
[2.6.1]: https://github.com/johantor/zion/compare/crew/v2.6.0...crew/v2.6.1
[2.6.0]: https://github.com/johantor/zion/compare/crew/v2.5.0...crew/v2.6.0
[2.5.0]: https://github.com/johantor/zion/compare/crew/v2.4.0...crew/v2.5.0
[2.4.0]: https://github.com/johantor/zion/compare/crew/v2.3.0...crew/v2.4.0
[2.3.0]: https://github.com/johantor/zion/compare/crew/v2.2.1...crew/v2.3.0
[2.2.1]: https://github.com/johantor/zion/compare/crew/v2.2.0...crew/v2.2.1
[2.2.0]: https://github.com/johantor/zion/compare/crew/v2.1.1...crew/v2.2.0
[2.1.1]: https://github.com/johantor/zion/compare/crew/v2.1.0...crew/v2.1.1
[2.1.0]: https://github.com/johantor/zion/compare/crew/v2.0.0...crew/v2.1.0
[2.0.0]: https://github.com/johantor/zion/compare/crew/v1.9.0...crew/v2.0.0
[1.9.0]: https://github.com/johantor/zion/compare/crew/v1.8.0...crew/v1.9.0
[1.8.0]: https://github.com/johantor/zion/compare/crew/v1.7.0...crew/v1.8.0
[1.7.0]: https://github.com/johantor/zion/compare/crew/v1.6.0...crew/v1.7.0
[1.6.0]: https://github.com/johantor/zion/compare/crew/v1.5.0...crew/v1.6.0
[1.5.0]: https://github.com/johantor/zion/compare/crew/v1.4.1...crew/v1.5.0
[1.4.1]: https://github.com/johantor/zion/compare/crew/v1.4.0...crew/v1.4.1
[1.4.0]: https://github.com/johantor/zion/compare/crew/v1.3.0...crew/v1.4.0
[1.3.0]: https://github.com/johantor/zion/compare/crew/v1.2.0...crew/v1.3.0
[1.2.0]: https://github.com/johantor/zion/compare/crew/v1.1.3...crew/v1.2.0
[1.1.3]: https://github.com/johantor/zion/compare/crew/v1.1.2...crew/v1.1.3
[1.1.2]: https://github.com/johantor/zion/compare/crew/v1.1.1...crew/v1.1.2
[1.1.1]: https://github.com/johantor/zion/compare/crew/v1.1.0...crew/v1.1.1
[1.1.0]: https://github.com/johantor/zion/compare/crew/v1.0.2...crew/v1.1.0
[1.0.2]: https://github.com/johantor/zion/compare/crew/v1.0.1...crew/v1.0.2
[1.0.1]: https://github.com/johantor/zion/compare/crew/v1.0.0...crew/v1.0.1
[1.0.0]: https://github.com/johantor/zion/releases/tag/crew/v1.0.0
