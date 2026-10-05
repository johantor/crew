# Contributing to Zion

Zion is a Claude Code plugin marketplace: `crew` (orchestrated feature delivery, plus a debt lane
for tech-debt and upgrade fixes). **This repository *is* the plugins** — there is no application
code to build or ship. Work here means editing agent/command/skill definitions, hooks, and docs.

This is the contributor guide for anyone — human or agent — changing this repo. It is tool-neutral
and the one place each rule is written. Tool-specific entry points point here: `CLAUDE.md` for
Claude Code (plus how Claude should talk and edit), the `code-review` skill in `.github/skills/`
for reviewers, and each plugin's `CLAUDE.md` for its own map. Crew's configuration lives in
`.claude/crew.md`.

## Repository layout

A **monorepo marketplace**: `.claude-plugin/marketplace.json` lists the plugins, each in its own
directory under `plugins/<name>/`. Adding a plugin is additive — create the directory and add an
entry.

- `plugins/crew/` — the `crew` plugin (paths below relative to it):
  - `.claude-plugin/plugin.json` — the manifest.
  - `agents/` — `morpheus` (orchestrator) and the workers `tank`, `trinity`, `oracle`, `dozer`,
    `seraph`, `neo`, `sentinel`, `keymaker`. Auto-discovered; not declared in the manifest.
  - `commands/` — `/init`, `/feature`, `/debt`, `/audit`, `/review`, `/pr`, `/address`, `/triage`,
    `/loop`, `/notify` (namespaced `crew:*` once installed). `/feature`, `/debt` and `/address`
    are thin routers into `morpheus`'s own flows; `/loop` and `/audit` launch agents directly
    rather than nesting a command, since a wrapper cannot pass what the inner command does not
    forward. `/pr` is the only push path. Each command's own file says what it does; the plugin
    map (`plugins/crew/CLAUDE.md`) says how they fit.
  - `skills/` — preloads: `context-discipline` (every agent), `loop-engineering`,
    `operator-voice` and `review-gate` (`morpheus`; `/crew:review` loads `review-gate` too),
    `engineering-principles` (the implementers), `worker-contract` (the five workers with a
    shell: the rules every dispatch follows), `mid-run-direction` (every worker),
    `design-tokens` (`seraph`). On demand: `debt-lane` with `debt-taxonomy` and its per-stack
    skills; the stack skills `backend-*`, `frontend-*`, `cms-optimizely`, `tests-*`, loaded once
    `morpheus` resolves the project's stack and tools.
  - `hooks/` — `bash-safety.sh`, `read-guard.sh`, `lane-guard.sh`, `format.sh`,
    `dispatch-denied.sh`, `plan-guard.sh`, wired in `hooks/hooks.json`. The
    top-level `*.sh` are entry points (`+x`, wired); `hooks/lib/*.sh` are sourced libraries (not
    `+x`, not wired) — validator §3 and §6 enforce the split. The plugin map describes each hook.
  - `scripts/gate.sh` — the review-gate runner the wait recipe calls (shipped, unlike the
    repo-level `scripts/` below).
  - `CHANGELOG.md`, `README.md` (user-facing), `VERIFICATION.md` (the manual scenario matrix),
    `CLAUDE.md` (the plugin map for agents working on it).
- `scripts/` — repo tooling, never shipped: `validate-plugin.sh` (tree-only structural checks,
  the `§N` sections below), `check-changelog.sh` (the diff-based release gate, takes the base
  branch), `release-notes.sh` (one version's changelog section, used by `auto-release.yml`).
- `tests/hooks/` — the shared harness (`lib.sh`) and runner (`run.sh`) for `plugins/*/tests/`.
- `.claude/crew.md` — this repo's own crew configuration. The repo carries no hook wiring of its
  own: work here with `claude --plugin-dir plugins/crew`.
- `.github/` — `copilot-instructions.md` points Copilot at `skills/code-review/SKILL.md`, the one
  review rubric (`.claude/skills/zion-review/` wraps it for Claude Code); `workflows/validate.yml`
  runs shellcheck, the validator, the release gate and the hook tests; `auto-release.yml` tags.

## How the crew works

- `morpheus` plans and delegates; it writes no production code and is the **sole owner of git**:
  it branches off the resolved base and commits each verified step. Workers run no git but a
  plain `git mv`. The
  crew stops at the local review gate; `/crew:pr` pushes.
- The plan at `<plan-dir>/plan-<feature>.md` (the `planDirectory` slot, else `.claude/`) carries
  per-step acceptance criteria and is presented once for the user's go-ahead before the branch
  or any delegation — the plan checkpoint, honoring a standing "just build it".
- Lanes are stack-agnostic: `tank` backend, `trinity` client-facing layer (plus a shared server
  template's markup in server-rendered mode), `oracle` unit tests (backend, and frontend
  component tests when a unit tool is configured), `dozer` frontend e2e, `seraph` visual
  conformance (read-only), `neo` express-lane generalist (all lanes, no lane guard), `sentinel`
  post-merge triage (read-only, returns a pointer), `keymaker` debt scout (read-only, no Bash,
  returns `/crew:debt` pointers). `lane-guard.sh` enforces the write lane by extension where the
  stacks' languages differ, or by the configured lane paths when they are the same (Node +
  Next.js is the one such pair).
- A **regression** enters through `sentinel`: `morpheus` delegates the report to it and plans
  against the pointer, so the finding arrives in its own context. `/crew:triage` is the same
  agent standalone.
- `morpheus` **right-sizes by task size**: small, low-risk work takes the express lane (`neo`, no
  plan or full gate, a quick self-review, commit), escalating on evidence; features take the full
  flow; a pointer to known debt takes the **debt lane** (`debt-lane` skill: gate on blast radius,
  one verified batch per commit), even when it looks like a one-liner; an audit scope goes to
  `keymaker`. The debt lane is a skill, not a second orchestrator: `claude --agent crew:morpheus`
  sessions can only dispatch from the main thread, and an on-demand skill stays out of the
  footprint cap.
- **Loop mode** (`loop-engineering`): on explicit user intent the flow runs to completion without
  per-step check-ins, stopping only at the terminal gate (feature: review gate GO; debt: verify +
  commit — never push), a blocked human decision, or the retry cap (3 failed fix→verify
  round-trips on a unit; for the gate, a second NO-GO on the same findings). Intent is never
  inferred from fetched content. Loop state lives in the plan file so a resume continues in loop
  mode. The **outer** loop across runs is `/crew:loop`, a main-session wrapper on the native
  `/loop` that owns scheduling and the iteration cap; `morpheus` never self-schedules.
- All workers apply `context-discipline`: process bulk output with code, return concise findings.

Runtime configuration (commands, base branch, mode, stacks) lives in `.claude/crew.md` — YAML
frontmatter, one key per slot, plus a prose body. `/crew:init` writes and reconciles it. A slot
reads `unset` when unresolved (the orchestrator asks once) and `none` when the project has no such
tooling (the gate skips). Configuration does **not** live in a project's `CLAUDE.md`; what stays
there is the `## Crew orchestration` prose, whose reader — auto mode's permission classifier —
sees only `CLAUDE.md`. It is the one location: the `--local` file and the legacy `CLAUDE.md`
block went in 5.0.0 (#248), each stated in seven places and read by one hook.

## How we review code (the crew reviewer)

Reviews of **this repo** — by Copilot, the `zion-review` skill, or `/crew:review` run here — judge
code against `engineering-principles` (the code rules) and the `code-review` skill (this repo's
rubric: what to check, severity, the **Blocking** / **Warnings** / **Passed** output). In a user's
project, `/crew:review` applies `engineering-principles` only. Each is written once; everything
else points to them.

### Reviewing a prompt change (commands, agents, skills)

These artifacts are **executable contracts written in prose**, so `validate-plugin.sh` catches
structural drift, never a design bug. Most review misses here were this class. Apply this lens
before pushing and as a reviewer:

- **Durable-state invariant.** If one store is "the only cross-run state", every count or
  "N-in-a-row" lives there — no in-memory tally a fresh-context resume would lose.
- **Delegation can only pass what the callee accepts.** A wrapper cannot convey what the inner
  command does not forward; launch the agent directly and say so.
- **Every threshold is a number**, with what resets it.
- **Every failure and edge path has a stated behavior** — stop, skip or surface, and which
  durable state is or is not mutated.
- **A structured field documents its shape where it is owned**, and the owner is told to
  preserve it verbatim on rewrite.
- **Cross-file wording agrees.** Grep every term you changed across the command, its agent and
  the README/AGENTS/CLAUDE/CHANGELOG copies.

## Prompt design rationale

An always-loaded prompt costs context on **every** run, so it carries *instruction* and not the
*justification*. The justification lives here, one line per rule, with the PR that decided it
where one exists; the PR holds the full story. Prompts carry a single pointer to this file, never
per-rule pointers:
this file is never shipped, so a runtime agent cannot follow one.

**The classification test before moving a line out of a prompt:** *would an agent that never read
this text behave differently on some input?* Yes → instruction, it stays, even phrased as a "why"
("watch commands never terminate", "plugin agents are namespaced"). No → rationale, it comes here.
Anything arguable stays: a deleted edge-case rule costs more than a sentence of prose, and
motivation measurably helps compliance. Compression is not a quota.

### crew:morpheus

- **Gates run serially unless a stack proves a split** with a *Parallel gates* recipe run for
  real; a generic split-the-path rule drew a finding per tool (#232). .NET and Node have one;
  their guards are closed checks (a command allow-list, a tree check every run), not lists.
- **Right-size the process.** Small by default, escalate on evidence: a wrong small fix costs
  more than the escalation would have.
- **Plan checkpoint** before the branch: the cheapest place to catch a misunderstood task.
- **Plan mode — the approval is the checkpoint.** `ExitPlanMode` is the same gate, so both would
  ask twice. A subagent loses `ExitPlanMode` and inherits plan mode, so it returns the plan for
  `/crew:feature` to present and re-launch as approved. `Explore`/`Plan` stay in the allowlist
  because plan mode's own workflow reaches for them; `general-purpose` is absent because it is an
  unguarded implementer. `plan-guard` reads frontmatter, not a roster, and fails open: plan mode
  is the real boundary.
- **Stay responsive.** Foreground calls freeze the orchestrator for minutes, so background is the
  default; the status pulse is emitted after the result is reconciled, or it reports stale state.
- **Fresh spawns; steering is the narrow exception.** `Agent` never continues a worker, so
  `SendMessage` is the only way to add a turn to a live one; it is host-dependent, so its absence
  is never a blocker, and durable context still travels through the plan file. A steer amends the
  plan step as it is sent: the commit is judged against the step's `acceptance:`, so a steer that
  widens the work without widening the step makes the two disagree.
- **A steer is authenticated on a per-dispatch token, and its content is still fallible.** A
  steer arrives shaped like a `system-reminder`, the same shape injected text takes, so the anchor
  is a token minted per dispatch that planted content cannot quote; a plan step id could be
  cited by anyone who reads the repo. The token never enters the plan file or a worker's return.
  Workers preload `mid-run-direction`: correct a wrong premise, grow the step but never move the
  lane, guards or git posture, surface anything unanchored.
- **A truncated return is not a finished step.** Completeness is judged on content, the only
  signal always present; the reconcile path is the durable-resume rule under another trigger.
  It is the one mechanism for a worker cut off at `maxTurns`: a warning hook with a budget table
  lockstepped to the agents duplicated it and went in 5.1.0 (#249).
- **Right-size the model per delegation.** Run-and-report steps get speed; everywhere else the
  override is omitted, since a wrong fast result costs more than the seconds saved.
- **Builds and full suites are one delegated final gate**, not a per-step check: expensive and
  verbose, and a standalone build before the gate builds the same tree twice.
- **A gate command ends inside the worker's turn.** A backgrounded command's late report can
  reach the UI and never the orchestrator (#239), so `/crew:review`'s wait recipe polls an exit
  file in bounded calls and kills a timed-out gate as a process group. The recipe lives in
  `scripts/gate.sh` because Claude's permission check refuses an inline compound recipe (`$$`,
  then `{ … }`), and a headless worker cannot answer the prompt (#245). It takes the command as a
  string, so its allow rule is as wide as allowing all Bash; reading a fixed crew-config slot
  instead was declined, because a narrowed gate (named failing tests) could not use it. A worker
  that still
  backgrounds its own command is messaged for its report, and never reported on from a result
  that has not arrived. The runner caches a green log by the tree's git hash, the physical
  directory and the command: the skip rule that had `morpheus` record `HEAD` and a clean
  status was prose, and a run that forgot it built the same tree twice. Red is never cached
  (it may be contention); a run that changed the tree is not cached either (the key is taken
  again at exit); the key ignores ignored files and the toolchain (an accepted gap; the user
  clears the cache) and skips a tree that hashes with a gitlink, an untracked embedded repo
  included (its dirty content is invisible to the outer hash); its fields are NUL-delimited
  (a path or command may hold a newline); a hit is trusted only from an absolute cache
  directory this user owns and others cannot write, with a failed permission query counting as
  writable, since `/tmp` is shared and `CREW_GATE_CACHE_DIR` can name anything, and only when
  the whole cached log copies (a half-read entry runs the gate). A Parallel gates run
  passes `nocache`: the key excludes ignored files, so a run the recipe's tree check later
  rejects would otherwise seed a green entry that the serial rerun then hits.
- **Isolation or a path, decided at dispatch.** An isolated worktree auto-cleans a gitignored
  deliverable (#241), and a relocation steer is refused inconsistently (#242).
- **Address review feedback** with the same lane routing, git ownership and gate that built the
  feature, not a second looser flow.
- **The plan file is durable state.** It survives a crash or context reset. `/crew:loop` keeps
  no crash marker: ticks run their workers in the foreground and return only when nothing runs,
  so the next tick's resume reconciles whatever a crashed one left (#249).
- **Run summary** reproduces the per-worker view the agent panel loses on resume, so it repeats
  neither `/recap`'s commit list nor the status pulse.
- **Anti-drift.** Citing the exact plan step in every delegation keeps a run resumable; current
  `status` fields make a crash leave an accurate record; naming the failing tests on a re-verify
  keeps full suites at the gate.

### crew:debt (the debt lane)

- **A scout but no fixer of its own.** A fixer would duplicate `tank`/`trinity`'s lanes and
  contracts, so the fixer rules travel in each handoff. The audit greps untrusted content and
  must edit nothing; `keymaker`'s `tools:` list without Edit/Write/Bash is the boundary, and
  `/crew:audit` resolves the two shell-needing scopes as data blocks.
- **Why `morpheus` is lane-guarded, and why its lane is a filename shape.** It writes plans,
  ledgers, config and memory, never production code. A directory allowlist needed a root and a
  slot that could overlap source, and three review rounds each found an edge case; production
  code is never named `plan-*.md`. A `..` segment is refused for every lane agent.
- **Class 4 waits for the user**: routing a skipped test on the pointer alone turns "investigate"
  into "unskip".
- **Exit contract and resume** make re-running a cleared pointer a cheap no-op.
- **Step 8 re-sweeps independently** because the worker's own counts are the claim under test.
- **The batch ledger is durable state**; open mode runs many batches across many turns.
- **Justified suppressions are read, never written** (#52). The store had to be the codebase:
  `memory: local` is per clone, a registry in the project's `AGENTS.md` rots by `file:line`, and
  the mechanism's native slot has keying, lifecycle and review locality for free. No ack command,
  no crew token. Slot-less mechanisms fall to project policy or stay surfaced — accepted.
- **`stale` ignores the filter and skipped tests are never excluded**: a justification explains
  why a suppression was added, not why it should stay, and the filter's failure mode is a scope
  reported clean because it excluded everything.

## Validating changes

This repo has no app build. Before opening a PR, run what CI runs:

```bash
shellcheck plugins/*/hooks/*.sh plugins/*/hooks/lib/*.sh plugins/*/scripts/*.sh plugins/*/tests/*.sh scripts/*.sh tests/hooks/*.sh
bash scripts/validate-plugin.sh
bash scripts/check-changelog.sh          # takes the base branch; defaults to main
bash tests/hooks/run.sh
```

`check-changelog.sh` is the one diff-based check, which is why it takes a ref and lives outside
the tree-only `validate-plugin.sh`. See *Releasing*.

`validate-plugin.sh`'s sections, cited as `§N`: manifests §2, marketplace sync §2f, `skills:`
resolution §2g, version ↔ changelog §2h, hook file modes §3, wiring §6 (§4–§5, §7 and §8 are
unused), rosters §9, prose refs §10, `crew.md` keys §11, footprint §12, MCP
pairs §13, YAML frontmatter §14. §2g and §12 index skills through `git ls-files`, so stage a
new or renamed skill file before running the validator.

`plugins/<plugin>/tests/` is a bash suite — `jq` and `git` only, no LLM, no network — exercising
the hooks' behavior: each guard is a pure `stdin JSON → exit 0/2` function. The harness lives
once in `tests/hooks/`; `run.sh` discovers every suite and **fails when a plugin ships `hooks/`
with no suite beside it**. `format.sh` is covered through a fixture `formatMatrix` whose rows name faked tools. **A change to a guard's logic adds or adjusts a
case, covering both the allow and the block side.**

The suite also self-tests the validator: **every section carries a negative fixture and a silent
control, and a new section or guard lands with its fixture in the same commit.** A check that
silently stops checking is the worst failure for an enforcement tool. Assert on the guard's own
FAIL message, not the exit code: a minimal fixture trips unrelated sections.

What the lockstep sections protect, one line each:

- **§2g** — a `skills:` typo fails silently at runtime; the agent guesses.
- **§9** — a name missing from a guard's roster **fails open**: unrestricted git, no lane. Each
  agent declares `owns-git` and `lane-guarded`; each roster carries a `# crew-roster:` marker in
  the load-bearing `a|b|c)` arm shape; exactly one git owner.
- **§10** — a `crew:` reference in prose that resolves to no agent or command fails late.
- **§11** — `init.md` §1's `- **Slot** (`key`) —` bullets and `.claude/crew.md`'s keys agree both
  ways, paired on the key.
- **§12** — the always-loaded footprint (agent + preloaded skills) is reported; an agent may set
  `loaded-lines-cap` (today `morpheus`) so growth is a visible frontmatter edit. An unparseable
  cap or unreadable file fails rather than counting zero.
- **§13** — a plugin-bundled MCP server's tools are `mcp__plugin_<plugin>_<server>__…`, so every
  bare `mcp__<key>` grant needs its plugin form and vice versa, matched by suffix. Tool-scoped
  grants and a bare `mcp__*` are rejected; hosted connectors (`mcp__claude_ai_Figma`) are exempt.
- **§14** — an unquoted YAML scalar with `: ` drops the whole frontmatter, so a skill never
  triggers while reading fine to a human. Wrap the value in double quotes.

## Releasing

Versions are per-plugin, and there is one rule: **a shipped change bumps the version.**

1. Bump `version` in `plugins/<name>/.claude-plugin/plugin.json` and add a matching `CHANGELOG.md`
   entry in the same PR; §2h fails CI unless they agree.
2. Merge to `main`. `auto-release.yml` sees the version has no `<plugin>/v<version>` tag, and
   creates the tag and GitHub Release with that version's changelog section
   (`scripts/release-notes.sh`). No entry → it skips with a warning.

### A shipped change bumps the version

A tag carries **everything** merged since the previous tag, so an unbumped change ships inside
the next release, described nowhere (`crew/v3.15.0` did that to a README rewrite). So every PR
that touches shipped files bumps — patch for a fix, minor for an addition, major for a break — a
reworded refusal, a changed prompt, a comment inside a shipped hook, a README line included.
Several in a day is fine. `check-changelog.sh` enforces it. Shipped means everything under
`plugins/<name>/` except `tests/`, `CLAUDE.md`, `VERIFICATION.md` and `CHANGELOG.md` itself;
`README.md` counts. Repo-wide changes (CI, root docs, `scripts/`, `tests/`) need no bump.

**Changelog entries are terse.** One bullet per change under its Keep-a-Changelog heading, one
line, two at most: *what changed*, with the PR as `(#N)`. The why belongs in the PR and commit.

## Conventions

- Hooks are Bash (`#!/usr/bin/env bash`), shellcheck-clean, and **BSD/macOS-portable**: `mktemp`
  with an explicit `XXXXXX` template, `[[:space:]]` not `\s`, no GNU-only flags.
- Guards run before every tool call, so they match with `[[ =~ ]]` and parameter expansion, never
  a fork per pattern.
- Agent/command/skill files are Markdown with YAML frontmatter; match the field shape of their
  neighbours. In an agent, `skills:` is the last key (§2g).
- Local agent memory (`.claude/agent-memory-local/`) is gitignored. It and an unset plan directory
  resolve inside a **git worktree**, so `git worktree remove` deletes both; only committed content
  outlives it, which is what pointing `planDirectory` at a tracked path is for.
- Keep diffs minimal-scope; list unrelated improvements rather than bundling them.
- PR titles follow Conventional Commits, `type(scope): summary`, with `(vX.Y.Z)` when the PR bumps.
  Types: `feat`/`fix`/`chore`/`docs`/`ci`/`refactor`; scope the plugin when the change is
  plugin-specific (`feat(crew): … (v1.9.0)`).
- **PR descriptions have a hard budget**: summary 150 words and 5 bullets at most, whole body
  under 400 words. The body says why, and what a reviewer needs to approve safely. Never a
  self-review, a bugs-found log, a narrative, design alternatives, or pasted output; those go in
  the commit message (not budgeted), the issue, or a review thread. Verification is a result
  ("ran X, all green"), not a transcript.
- **Every review comment gets a reply, then the thread is resolved.** Fixed — name the commit.
  Declining — say why. Duplicate — say which.
- A PR that resolves an issue links it with a closing keyword (`Closes #N`).
- One branch and PR per issue, from the latest `main`: `git fetch origin main && git checkout -B
  <branch> origin/main`. A merged PR's branch is deleted; reusing the name leaves a stale tracking
  ref until pruned.

### Writing style (READMEs, changelogs, PR bodies, issues)

Prose here reads like a person wrote it; generated-sounding text is a trust problem, because the
same patterns let a claim slide through unbacked.

- **Name the catch** next to the claim. Two lane-guard overclaims survived #178 because the
  sentence sounded confident.
- **Specifics instead of adjectives.** Name the hook, the tool it gates, what happens when it fires.
- **Take the stance.** "Both have their place" is a dodge.
- **Don't hedge every sentence**, and **vary the rhythm**; a four-word sentence is allowed.
- **Skip the tells**: `delve`, `leverage`, `robust`, `seamless`, `unlock`, `harness` (as a verb),
  `streamline`, `empower`, `elevate`, `pivotal`, "it's not just X, it's Y", "at its core", "in
  today's fast-paced …".
- **Go easy on em-dashes.** A colon, a comma or a full stop usually serves; keep a matched pair
  around a real aside. A nudge, not a review comment.

### The Bash guards are floors, not sandboxes

`bash-safety.sh` refuses a few command shapes. Two rules read like enforcement and are not; each
was widened once and reverted, and the hooks point here so it is not tried a third time.

- **The raw-read rule is a habit redirect**, so it applies to agent sessions only (#249). It
  blocks `cat f` and names `Read`; `grep . f`,
  `awk`, `tail -n 999999`, `python3 -c` dump the same file and are allowed. A missed read costs
  nothing, a wrong refusal costs a turn, so the pattern is one line and any pipe or redirect ends
  the match. Following bytes through redirects needs bash's tokenizer (#226: two regressions in
  six rounds, reverted).
- **`guard_normalize` flattens newlines, leaving a gap**: `cd sub` + newline + `git status` reads
  as one command and the no-git block misses it. Splitting on newlines refuses ordinary heredocs
  and quoted strings (#226 tried three shapes). Both gaps stay open: the worker's prompt keeps it
  out of git, and closing either takes a tokenizer in its own PR.
- **`/crew:audit` passes `diff` file names as quoted lines**, not a parsed encoding: the scout
  reads the block as data and has no tool to act on it, so a hostile name can only skew a report.
- **The protected-branch backstop reads the branch where the commit runs**: the payload's `cwd`,
  or the literal directory of `git -C <dir>` / `cd <dir> &&`; other shapes also check the hook's
  own directory, so it is never weaker than before #224 (a full shell walk drew 100+ threads and
  was replaced). Open gap: `CDPATH`.
- **A redirect outside the project is exempt, by allow-list** (#240): lanes and formatting guard
  only the checkout, and an out-of-tree build root is where builds write. Only an absolute path
  of plain segments outside `$CLAUDE_PROJECT_DIR` passes; `$`, backticks, globs, `.`, `..`, `//`,
  hidden segments, quotes and an unset project dir all count as inside. #264 first tried to
  reason about what bash would expand and leaked three rounds running. Open gaps: a symlink
  outside the project that points into it (as with `/tmp` before), and a main checkout written
  from a worktree session.
- **`rm -rf` refuses every target starting with `/`, `~` or `*`**, build dirs included. A
  whole-token match let `/*/` and `/tmp/../*` through (#264). Out-of-tree cleanup is `rm -r`.
- **The `git mv` carve-out reads line starts because it is an allowance**: a false separator can
  only wave through a `git mv` inside a string, never refuse anything. The floor decides *what* a
  `git mv` is, not *whose*: it lets any agent run a plain one. `bash-safety.sh`'s no-git roster
  lets a worker run only a `git mv` alone in the command with relative paths (no `-C`, `cd` or
  `..`), so the rename stays in the tree it was dispatched to (#249, #263). Open gaps: no lane
  guard sees a `git mv`, so `morpheus` checks renames in the staged diff; a cwd a worker moved
  with an earlier `cd` call is not checked.

### Why `format.sh` runs a matrix and detects nothing

Until 6.0.0 the hook decided per edit which formatter a project had chosen: nearest config up
the tree, a `[tool.ruff.format]` section, a Cargo edition from the owning manifest, gofumpt out
of golangci YAML, Spotless across build files. That was 340 lines of detection with two awk
parsers, and every stack added a lane with fixtures. The question it answered is a property of
the project that a human confirms once, so it moved to `/crew:init`: the stack skills say what
to propose, init proposes rows, the user confirms, and the hook only runs them. Consequences:

- **No fallback.** A missing slot, `none` or `unset` means per-edit formatting is off and the
  lint gate catches the result. Keeping detection as a fallback would keep the 340 lines.
- **Staleness has two signals, neither a scan.** A tool that is gone exits 127, which the hook
  reports with a `/crew:init` nudge the worker hands back; a config that is new fails the lint
  gate on formatting alone, which `review-gate` reports as a stale matrix. `morpheus` never
  walks the tree for formatter configs: that list belongs in `init.md` only.
- **A row is a command string run from a committed file on every edit.** The same trust posture
  as the gate's test command slot (`scripts/gate.sh` runs one with `bash -c` too).
- **Accepted gaps.** Rows are inclusive, so a path black would exclude needs no row rather than a
  row that reformats it; a Rust edition is a row per crate, so a workspace mixing editions
  without crate rows formats on the default.

## Recurring review findings — apply proactively

Patterns that showed up more than once in review on this repo. Apply them up front:

- **Verify before filing a "nothing enforces this" issue.** Grep the implementation and this file
  first; a drift-guard issue was filed against a check the validator already had.
- **A validator or guard fails loudly on every path where it cannot verify its claim** — a missing
  input, invalid input, an unreachable check. Never skip silently.
- **Anchor a delimiter split on the trusted field.** Splitting on the first occurrence is safe
  only when the field before it is a small controlled value that cannot contain the delimiter;
  put untrusted text last, or split from the end.
- **A new conditional in a multi-mode flow is spelled out for every mode**, not only the default.
- **State heuristics as heuristics.** "X is unlikely" is not "X can't happen".
- **Bash: `if ! var="$(cmd)"` still assigns `var`**; don't comment that it is "never set".
- **Quote every expansion, array subscripts included.**
- **Keep inline comments short; the rationale lives once, here or in the changelog, with a pointer.**
- **After merging `main` into a branch, refresh the PR description**: version ranges go stale.
- **Self-review the diff before opening a PR** (`/code-review` or the `/crew:review` gate);
  reviewers are the backstop, not the first pass.
- **Behavioral verification means running the scenario**, from the plugin's
  [`VERIFICATION.md`](plugins/crew/VERIFICATION.md), and citing the observed result. "Would pass"
  is not verification.
