# crew — quick reference for agents working on this plugin

Crew-specific map. **Keep it accurate: a PR that changes anything stated here updates this file
in the same commit.** Rules shared by every plugin: [AGENTS.md](../../AGENTS.md).

## Map

- `agents/` — auto-discovered, not in the manifest.
  - `lead`: orchestrator, `model: opus`, sole git owner. Its `Agent(...)` allowlist (eight
    workers plus `Explore`/`Plan`) and `ExitPlanMode` only work as the main thread of
    `claude --agent crew:lead`; via `/crew:feature` the harness ignores both. It also has
    `AskUserQuestion` (operator choices), `TaskStop`, `Skill`, `WebFetch` and `WebSearch`;
    workers get no web tools.
  - Workers: `backend` (the stack's core: in a CLI or script pack, the commands and I/O),
    `frontend` (client-facing layer), `unit-tests`, `e2e`, `visual-review` (no Bash; measures
    computed styles through the browser MCP), `generalist` (express path), `incident-triage`
    (post-merge; no Write/Edit/Bash, history via the git-host MCP), `debt-scout` (no
    Write/Edit/Bash — `Grep`/`Glob` only, so `/crew:audit` hands it `diff` and `outdated`
    results as data).
- `commands/` — namespaced `crew:*` when installed.
  - `init` writes `.claude/crew.md`, one frontmatter key per slot, the only config location;
    §4 asks on bootstrap whether to commit it or git-exclude it via `info/exclude` (Local also
    moves the `CLAUDE.md` part to an excluded `CLAUDE.local.md`).
    Its §1 slot keys are validator §11's source of truth (the `- **Slot** (`key`) —` bullet
    shape is what §11 parses); §2 takes each backend's commands from its `backend-<stack>`
    skill's *Crew config* section; §3 owns what may go in `CLAUDE.md` (auto mode's classifier
    reads only that file); §5 writes and reconciles; §6 reports MCP namespaces.
  - `feature`, `review` (GO/NO-GO gate), `pr` (the only push/PR path), `address`.
  - `debt`: routes into `lead`'s debt lane (the `debt-lane` skill), in the foreground so its
    gates can prompt. The skill must not share a command's name: a command is also listed as a
    skill, so `lead` would load the command and relaunch itself.
  - `audit`: launches `debt-scout` (`diff`'s file list and `outdated`'s package-manager output are
    resolved here first — the scout has no Bash), relays the report, then launches `lead`
    directly per picked pointer with `debt`'s open-mode instructions, never by nesting
    `/crew:debt`.
  - `loop`: re-launches `lead` directly each tick on native `/loop` until exit conditions or
    the cap; the wrapper owns scheduling.
  - `triage`: launches `incident-triage` and relays its report; writes nothing (#175 phase 2).
  - `notify`: peer-session messaging (#177). A command, since `lead` has no `ListAgents`, so
    a `--agent crew:lead` session needs an explicit `to=`.
- `skills/` — `<name>/SKILL.md`, frontmatter `name:` + `description:` only (the description
  carries the triggers).
  - `lead`'s preloads: `context-discipline`, `loop-engineering`, `operator-voice`
    (ASD-STE-100; operator messages only, never plans, ledgers or commits), `review-gate` (the
    build/test/lint gate rules; `/crew:review` loads it too, since a standalone run never sees
    `lead.md`).
  - Debt lane, loaded on demand: `debt-lane` (open mode — the flow, the fixer rules each handoff
    carries, the `<plan-dir>/debt-<slug>.md` ledger with its per-batch `snapshot:`),
    `debt-taxonomy` (rubric, gate, tiers), and `debt-taxonomy-dotnet`/`-typescript`
    (mechanisms, justification slots, recipes). `debt-scout` loads the taxonomy skills too; the
    audit flow lives in its own prompt.
  - Also: `engineering-principles` (the code rules `/crew:review` grades a user's project
    against; this repo's own review rubric is `.github/skills/code-review`), and the preloads
    `worker-contract` (the rules shared by the five workers with a shell — `backend`, `frontend`,
    `unit-tests`, `e2e`, `generalist` — so each prompt states only what is specific to its role, and each
    stack skill only what is specific to its tool: watch commands, weakening flags, the lock
    signature, filter and discovery syntax, the skip mechanism),
    `mid-run-direction` (all eight workers, not `lead`) and `design-tokens` (`visual-review`).
  - Loaded once resolved: frontend mode, stack and test-tool skills. `frontend-razor` holds the
    `.cshtml` rules for both halves of a view: `frontend-server-rendered` names it for the
    markup, `backend-dotnet` for the server side, and the CMS skills point their view rules
    there instead of repeating them. Backends `backend-dotnet`
    (+ the `optimizely-<product>` skills), `-node`, `-python` (Opal tools), `-shell`, each paired
    with a `tests-*` skill. Other languages are unsupported; the hooks keep their Go/Rust/JVM
    patterns for mixed repos. Only node needs lane paths (its extensions collide with a frontend's).
    `frontendStack: none` is a stated absence: `lead` skips frontend, e2e and unit-tool
    resolution and dispatches only `backend`/`unit-tests`. That gate sits above the resolution table.
  - Optimizely: one `optimizely-<product>` skill per product, sections in order **Detect**
    (markers and neighbour skills), the product's own patterns, **Security**, **Testing**,
    **Deploy and verify**, **Sources** (the docs URL). Each product skill stands alone, so one
    load covers it; a migration between versions is its own skill (`optimizely-cms-upgrade`), a
    move off a product stays in that product's skill (`optimizely-search-navigation` → Graph). Facts
    come from docs.optimizely.com: re-check a skill's sources when you touch it. Name a
    neighbour skill only once it ships; a missing skill makes the `Skill` call fail.
    `optimizely-graph`, `optimizely-cms-saas` and `optimizely-odp` are the ones a non-.NET
    worker loads: `frontend-headless` names the markers of all three, `backend-node` those of
    Graph and ODP, `frontend-server-rendered` the ODP web tag, and the worker greps for them
    itself.
- `hooks/` — wired in `hooks/hooks.json`, the one copy; in this repo they load through
  `claude --plugin-dir plugins/crew`. `bash-safety` and `lane-guard` fail closed; `read-guard`, `format`,
  `dispatch-denied` and `plan-guard` fail open.
  - `bash-safety.sh`: workers run no git but a plain `git mv`; protected-branch commit backstop (reads the
    payload's `cwd`, not the hook's directory; AGENTS.md has the shapes); watch/dev
    commands refused; file-mutating Bash refused for agent sessions (in-place
    `sed`/`perl`/`ruby`/`awk`, `tee`, `patch`, `cp`/`mv`, a redirect to a non-exempt sink; #192).
    Exempt sinks include an unquoted absolute path outside `$CLAUDE_PROJECT_DIR` (#240).
    Heredoc bodies are skipped (`_guard_strip_heredocs`): they are data, not commands.
    One carve-out: a plain `git mv`, for any agent, matched on the raw command so a later line
    counts; `-f`/`--force` stays refused. The no-git arm lets a worker run only what
    `guard_is_plain_git_mv` accepts: one `git mv` alone in the command, relative paths, no
    `-C`/`cd`/`..`.
    Raw reads (`cat f`) are refused for agent sessions: a habit redirect, not a boundary.
    Pagers and `tail -f` are refused for every session, since they never end.
  - `read-guard.sh`: raw reads over 64 KiB; an explicit `limit` ≤ 2000 lines passes.
  - `lane-guard.sh`: Edit/Write lanes. `lead` is `--allow` on a filename shape at any depth —
    `plan-*.md`, `debt-*.md`, `crew.md`, `agent-memory-local/*.md`, `tickets/*.md` — plus scratch
    and any path `guard_outside_project` accepts; no directory to anchor, no plan-directory slot
    read (AGENTS.md, "Why `lead` is lane-guarded"). The
    four lane workers get their lanes below. A `..` segment is refused for every lane agent.
    `backend`/`frontend` are refused while `backendStack` is `unset`; the guard probes no markers.
    Reads crew config through `guard_config_load` (`.claude/crew.md` frontmatter by key,
    nothing else), called in the parent shell since `config_slot` runs in `$(...)`.
  - Roster shape: `# crew-roster: <name>` then an `a|b|c)` arm, in `bash-safety.sh` and
    `lane-guard.sh`; §9 keeps both in lockstep with `owns-git`/`lane-guarded` frontmatter.
  - `format.sh`: a runner over the `formatMatrix` block (`config_block`), no detection. Every
    row `<dir> <extensions> <command>` matching the edited file runs in order from `<dir>` via
    `bash -c`, `{file}` single-quoted and relative to `<dir>`, under `CREW_FORMAT_TIMEOUT`
    (default 20s, unbounded without `timeout`/`gtimeout`). Exit 127 reports the tool as gone
    with a `/crew:init` nudge, returned as PostToolUse `additionalContext` on stdout since
    stderr at exit 0 never reaches the model; no matrix, `none` or `unset` is silent. Single-file formatters
    only; whole-project ones belong to the review gate (AGENTS.md, "Why `format.sh` runs a
    matrix and detects nothing").
  - `dispatch-denied.sh` (`PermissionDenied`, `Agent|Task`): attempt 1 emits `retry: true`,
    later ones only a `systemMessage`. The JSON is the decision. Counter under
    `CREW_DISPATCH_DENIED_DIR`; a path that cannot count takes the no-retry branch. Gates on the
    `crew:` namespace, not a roster.
  - `plan-guard.sh` (`PreToolUse`, `Agent|Task`): in plan mode, refuses a `crew:<worker>` whose
    frontmatter grants `Edit`/`Write`/`NotebookEdit`; `owns-git: true` passes. Reads both
    `tools:` shapes; `CREW_AGENTS_DIR` is the test override.
  - `lib/guard-lib.sh`: payload plumbing, `guard_agent_type` (only a `crew:<name>` agent
    reaches the bare rosters; any other agent, a project's own bare `backend` included, becomes
    `ext:<name>`, still an agent session), `guard_normalize`,
    `GUARD_RE_*`, the `guard_block_*` helpers, quote masking, protected branches, read-guard
    limits, crew config (`guard_config_load`, `config_slot`, `config_block`), state files.
- `scripts/gate.sh` — the review-gate runner: `start <id> '<cmd>' [nocache]`, `poll <id>`, `stop <id>`,
  state in `/tmp/crew-gate-<id>/`. A green log is cached under `/tmp/crew-gate-cache`
  (`CREW_GATE_CACHE_DIR`; the tests point it at a fixture) by tree hash, physical directory
  and command, never in a repo with a gitlink or from a directory others can write; a hit
  writes `log` and `exit` 0 and no `pid`. `/crew:review` and `lead` name it by
  `${CLAUDE_PLUGIN_ROOT}`, which Claude Code substitutes in command and agent bodies.
- `tests/` — a guard is `stdin JSON → exit 0/2`: assert allow/block plus a stderr substring.
  Exceptions: `format` asserts its stderr
  report through fake tools, `dispatch-denied` asserts its stdout JSON with `jq`,
  `plan-guard` uses real agents, then fixtures via `CREW_AGENTS_DIR`, and `gate` runs the script. Every validator section has
  a negative fixture and a silent control (assert on the FAIL message).
  `changelog-gate.test.sh` builds real git history.

## Schemas & conventions

- Durable run state: `<plan-dir>/plan-<feature>.md`, schema in `agents/lead.md`
  §"The plan file is durable state" — header `feature:`/`base-branch:`/`feature-branch:` +
  inner-loop fields (`loop:`, `exit-conditions:`, `gate:`) + outer-loop bookkeeping
  (`iterations: n/max`, written by the `/crew:loop` wrapper, not lead);
  steps carry `id:`/`status:`/`depends-on:`/`acceptance:`/`worker:`/`attempts:`/`evidence:`, plus
  `agent-id:` while in flight (cleared when the step leaves `in-progress`). The `steer-token:`
  **never** lands in the plan file, since a plan dir can be committed; a resumed run
  re-dispatches instead of steering orphans.
- Loop mode: generic contract in the shared `loop-engineering` skill; crew bindings (gate GO
  success, second-NO-GO cap, `/crew:pr`, generalist no-op) in `agents/lead.md` §"Loop-mode
  bindings". The outer loop is `commands/loop.md`.
- Every crew agent carries `owns-git` and `lane-guarded` before `skills:` (§9); exactly one
  (`lead`) owns git.
- `omitClaudeMd: true` only on `incident-triage` and `visual-review` (read-only, fully briefed). Never on an
  implementer: the project's `CLAUDE.md` holds its conventions. Not on `debt-scout` either: the
  project's `CLAUDE.md` may carry the debt policy section it has to honor.
- `lead` has `loaded-lines-cap: 609`, 4 lines of slack (raised from 595 when the gate rules
  moved into the preloaded `review-gate` skill, whose frontmatter and heading count). Skills it
  loads on demand (`debt-lane`) do not count.

## Gotchas

- `incident-triage`'s "no mutating MCP tool" rule is prose, not a mechanism (§13 forces whole-server
  grants). Don't describe it as enforced.
