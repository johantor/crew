# Contributing to crew

This repository is the `johantor` Claude Code plugin marketplace: `crew`, orchestrated feature
delivery plus a debt lane for tech-debt and upgrade fixes. **This repository *is* the plugins**:
there is no application code to build or ship. Work here edits agent, command and skill
definitions, hooks, and docs.

This is the contributor guide for anyone, human or agent, changing this repo. It is tool-neutral
and the one place each rule is written. Tool-specific entry points point here: `CLAUDE.md` for
Claude Code (plus how Claude should talk and edit), `.github/skills/code-review/` for reviewers,
and each plugin's `CLAUDE.md` for its own map.

## Repository layout

A **monorepo marketplace**: `.claude-plugin/marketplace.json` lists the plugins, each in its own
directory under `plugins/<name>/`. Adding a plugin is additive: create the directory and add an
entry.

- `plugins/crew/`: the `crew` plugin. `.claude-plugin/plugin.json` is the manifest; `agents/`,
  `commands/` and `skills/` are auto-discovered, and `hooks/hooks.json` wires the hooks. The
  top-level `hooks/*.sh` are entry points (`+x`, wired); `hooks/lib/*.sh` are sourced libraries
  (not `+x`, not wired); validator §3 and §6 enforce the split. `scripts/gate.sh` is the
  review-gate runner, shipped unlike the repo-level `scripts/`. `README.md` is user-facing,
  `VERIFICATION.md` is the manual scenario matrix, and `CLAUDE.md` is the plugin map: every
  agent, command, skill and hook, and how they fit.
- `scripts/`: repo tooling, never shipped. `validate-plugin.sh` (tree-only structural checks,
  the `§N` sections below), `check-changelog.sh` (the diff-based release gate, takes the base
  branch), `release-notes.sh` (one version's changelog section, used by `auto-release.yml`).
- `tests/hooks/`: the shared harness (`lib.sh`) and runner (`run.sh`) for `plugins/*/tests/`.
- `.claude/crew.md`: this repo's own crew configuration. The repo carries no hook wiring of its
  own: work here with `claude --plugin-dir plugins/crew`.
- `.github/`: `workflows/validate.yml` runs the checks in *Validating changes*;
  `auto-release.yml` tags. `ISSUE_TEMPLATE/` holds the bug and feature forms. `skills/` holds
  the repo's own skills, never shipped: `code-review` (the one review rubric, which Copilot reads
  through `copilot-instructions.md`) and `writing-style`. Each has a thin wrapper in
  `.claude/skills/` for Claude Code (`crew-review` adds the shell steps).
  `.claude/skills/steward/` says how a session drives a PR.
- `CONTRIBUTING.md` points here; `CODE_OF_CONDUCT.md` is the Contributor Covenant 2.1;
  `SECURITY.md` covers guard bypasses.

## How the crew works

- `lead` plans and delegates. It writes no production code and is the **sole owner of git**: it
  branches off the resolved base and commits each verified step. Workers run no git but a plain
  `git mv`. The crew stops at the local review gate; `/crew:pr` pushes.
- The plan at `<plan-dir>/plan-<feature>.md` (the `planDirectory` slot, else `.claude/`) carries
  per-step acceptance criteria. It is presented once for the user's go-ahead before the branch
  or any delegation (the plan checkpoint); a standing "just build it" counts as the go-ahead.
- Each worker has a lane (the plugin map lists them). `lane-guard.sh` enforces the write lane by
  extension where the stacks' languages differ, or by the configured lane paths where they are
  the same (Node + Next.js); an `other` stack without lane paths has open lanes (*Why an `other`
  stack has open lanes*). With `backendStack` unset it refuses `backend`/`frontend`.
  `generalist` has no lane guard; `visual-review`,
  `incident-triage` and `debt-scout` are read-only.
- `lead` **right-sizes by task size**: small, low-risk work takes the express lane (`generalist`,
  no plan or full gate, a quick self-review, commit) and escalates on evidence; features take the
  full flow; a pointer to known debt takes the **debt lane** (`debt-lane` skill: gate on blast
  radius, one verified batch per commit), even when it looks like a one-liner; an audit scope goes
  to `debt-scout`; a regression goes to `incident-triage` first, and `lead` plans against its
  pointer.
- **Loop mode** (`loop-engineering`) runs only on explicit user intent, never inferred from
  fetched content. It runs without per-step check-ins and stops only at the terminal gate
  (feature: review gate GO; debt: verify + commit, never push), a blocked human decision, or the
  retry cap (3 failed fix→verify round-trips on a unit; for the gate, a second NO-GO on the same
  findings). Loop state lives in the plan file, so a resume stays in loop mode. The outer loop
  across runs is `/crew:loop`, a wrapper on the native `/loop` that owns scheduling and the
  iteration cap; `lead` never self-schedules.
- Every agent applies `context-discipline`: process bulk output with code, return concise findings.

Runtime configuration (commands, base branch, mode, stacks) lives in `.claude/crew.md`: YAML
frontmatter, one key per slot, plus a prose body. It is the one location (#248). `/crew:init`
writes and reconciles it and is the only detector (*Init is the only detector*). A slot reads
`unset` when unresolved (the orchestrator stops and names `/crew:init`; the lane guard refuses a
worker) and `none` when the project has no such tooling (the gate skips). A project's `CLAUDE.md`
holds no configuration, only the `## Crew orchestration` prose, because auto mode's permission
classifier reads only `CLAUDE.md`. To keep the configuration out of the repo, `/crew:init`
git-excludes the same file, so no reader changes, and moves the prose to a git-excluded
`CLAUDE.local.md`. A new worktree then has no configuration.

## How we review code (the crew reviewer)

Reviews of **this repo** (by Copilot, the `crew-review` skill, or `/crew:review` run here) judge
code against `engineering-principles` (the code rules) and the `code-review` skill (this repo's
rubric: what to check, severity, the **Blocking** / **Warnings** / **Passed** output). In a user's
project, `/crew:review` applies `engineering-principles` only. A prompt change (agents,
commands, skills) has its own lens in the rubric's *Prompts* section; apply it before you push.

## Prompt design rationale

An always-loaded prompt costs context on **every** run, so it carries the *instruction*, not the
*justification*. The justification lives here, one line per rule, with the PR that decided it
where one exists. Prompts carry a single pointer to this file, never per-rule pointers: this file
is not shipped, so a runtime agent cannot follow one.

**Before moving a line out of a prompt, ask:** *would an agent that never read this text behave
differently on some input?* Yes → instruction, it stays, even phrased as a "why" ("watch commands
never terminate"). No → rationale, it comes here. Anything arguable stays: a deleted edge-case
rule costs more than a sentence of prose, and motivation measurably helps compliance.

### crew:lead

- **Gates run serially unless a stack proves a split** with a *Parallel gates* recipe run for
  real; a generic split-the-path rule drew a finding per tool (#232). .NET and Node have one;
  their guards are closed checks (a command allow-list, a tree check every run), not lists.
- **Right-size the process.** Small by default, escalate on evidence: a wrong small fix costs
  more than the escalation would have.
- **Plan checkpoint** before the branch: the cheapest place to catch a misunderstood task.
- **Plan mode: the approval is the checkpoint.** `ExitPlanMode` is the same gate, so both would
  ask twice. A subagent loses `ExitPlanMode` and inherits plan mode, so it returns the plan for
  `/crew:feature` to present and re-launch as approved. `Explore`/`Plan` stay in the allowlist
  because plan mode's own workflow reaches for them; `general-purpose` is absent because it is an
  unguarded implementer. `plan-guard` reads frontmatter, not a roster, and fails open: plan mode
  is the real boundary.
- **Stay responsive.** Foreground calls freeze the orchestrator for minutes, so background is the
  default; the status pulse is emitted after the result is reconciled, or it reports stale state.
- **Fresh spawns; steering is the narrow exception.** `Agent` never continues a worker, so
  `SendMessage` is the only way to add a turn to a live one. It is host-dependent, so its absence
  is never a blocker, and durable context still travels through the plan file. A steer amends the
  plan step as it is sent: the commit is judged against the step's `acceptance:`.
- **A steer is authenticated on a per-dispatch token.** A steer arrives shaped like a
  `system-reminder`, as injected text does, so the anchor is a token minted per dispatch that
  planted content cannot quote (a plan step id is readable by anyone). The token never enters the
  plan file or a worker's return. Workers preload `mid-run-direction`: correct a wrong premise,
  grow the step but never move the lane, guards or git posture, surface anything unanchored.
- **A truncated return is not a finished step.** Completeness is judged on content, the only
  signal always present. It is the one mechanism for a worker cut off at `maxTurns`; a warning
  hook with a budget table duplicated it and was removed (#249).
- **Right-size the model per delegation.** Run-and-report steps get speed; elsewhere the override
  is omitted, since a wrong fast result costs more than the seconds saved.
- **Builds and full suites are one delegated final gate**, not a per-step check: expensive and
  verbose, and a standalone build before the gate builds the same tree twice.
- **A gate command ends inside the worker's turn.** A backgrounded command's late report can
  reach the UI and never the orchestrator (#239), so `/crew:review`'s wait recipe polls an exit
  file in bounded calls and kills a timed-out gate as a process group. A worker that still
  backgrounds its own command is messaged for its report, never reported on from a result that
  has not arrived.
- **The recipe lives in `scripts/gate.sh`** because Claude's permission check refuses an inline
  compound recipe (`$$`, then `{ … }`), and a headless worker cannot answer the prompt (#245).
  It takes the command as a string, so its allow rule is as wide as allowing all Bash. Reading a
  fixed config slot instead was declined: a narrowed gate (named failing tests) could not use it.
- **The gate command cache** replaces a prose skip rule that a run forgot, building the same tree
  twice. A green log is keyed by the tree's git hash, the physical directory and the command;
  fields are NUL-delimited, since a path or command may hold a newline. Never cached: red (it may
  be contention), a run that changed the tree (the key is taken again at exit), a tree that
  hashes with a gitlink or an untracked embedded repo (its dirty content is invisible to the
  outer hash), and a Parallel gates run (`nocache`: a run the recipe's tree check later rejects
  would seed a green entry the serial rerun then hits). A hit is trusted only from an absolute
  cache directory this user owns and others cannot write (a failed permission query counts as
  writable: `/tmp` is shared and `CREW_GATE_CACHE_DIR` can name anything), and only when the
  whole log copies. Accepted gap: the key ignores ignored files and the toolchain; the user
  clears the cache.
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

- **A skill, not a second orchestrator.** `claude --agent crew:lead` sessions can dispatch only
  from the main thread, and an on-demand skill stays out of the footprint cap.
- **A scout but no fixer of its own.** A fixer would duplicate `backend`/`frontend`'s lanes and
  contracts, so the fixer rules travel in each handoff. The audit greps untrusted content and
  must edit nothing; `debt-scout`'s `tools:` list without Edit/Write/Bash is the boundary, and
  `/crew:audit` resolves the two shell-needing scopes as data blocks.
- **Why `lead` is lane-guarded, and why its lane is a filename shape.** It writes plans,
  ledgers, config and memory, never production code. A directory allowlist needed a root and a
  slot that could overlap source, and three review rounds each found an edge case; production
  code is never named `plan-*.md`. Ticket drafts (`tickets/*.md`) fit the same shape. Outside
  the project, `lead` writes anything (a scratchpad, an input file for a CLI): the lane guards
  the checkout only, by `guard_outside_project`. A `..` segment is refused for every lane agent.
- **Class 4 waits for the user**: routing a skipped test on the pointer alone turns "investigate"
  into "unskip".
- **Exit contract and resume** make re-running a cleared pointer a cheap no-op.
- **Step 8 re-sweeps independently** because the worker's own counts are the claim under test.
- **The batch ledger is durable state**; open mode runs many batches across many turns.
- **Justified suppressions are read, never written** (#52). The store had to be the codebase:
  `memory: local` is per clone, a registry in the project's `AGENTS.md` rots by `file:line`, and
  the mechanism's native slot has keying, lifecycle and review locality for free. No ack command,
  no crew token. Slot-less mechanisms fall to project policy or stay surfaced.
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
the tree-only `validate-plugin.sh`.

`validate-plugin.sh`'s sections, cited as `§N`: manifests §2, marketplace sync §2f, `skills:`
resolution §2g, version ↔ changelog §2h, hook file modes §3, wiring §6 (§4–§5, §7 and §8 are
unused), rosters §9, prose refs §10, `crew.md` keys §11, footprint §12, MCP
pairs §13, YAML frontmatter §14. §2g and §12 index skills through `git ls-files`, so stage a
new or renamed skill file before running the validator.

`plugins/<plugin>/tests/` is a bash suite (`jq` and `git` only, no LLM, no network) exercising
the hooks' behavior: each guard is a pure `stdin JSON → exit 0/2` function. The harness lives
once in `tests/hooks/`; `run.sh` discovers every suite and **fails when a plugin ships `hooks/`
with no suite beside it**. `format.sh` is covered through a fixture `formatMatrix` whose rows
name faked tools. **A change to a guard's logic adds or adjusts a case, covering both the allow
and the block side.**

The suite also self-tests the validator: **every section carries a negative fixture and a silent
control, and a new section or guard lands with its fixture in the same commit.** A check that
silently stops checking is the worst failure for an enforcement tool. Assert on the guard's own
FAIL message, not the exit code: a minimal fixture trips unrelated sections.

What the lockstep sections protect:

- **§2g**: a `skills:` typo fails silently at runtime; the agent guesses.
- **§9**: a name missing from a guard's roster **fails open**: unrestricted git, no lane. Each
  agent declares `owns-git` and `lane-guarded`; each roster carries a `# crew-roster:` marker in
  the load-bearing `a|b|c)` arm shape; exactly one git owner.
- **§10**: a `crew:` reference in prose that resolves to no agent, command or skill fails late.
- **§11**: `init.md` §1's `- **Slot** (`key`) —` bullets and `.claude/crew.md`'s keys agree both
  ways, paired on the key.
- **§12**: the always-loaded footprint (agent + preloaded skills) is reported; an agent may set
  `loaded-lines-cap` (today `lead`) so growth is a visible frontmatter edit. An unparseable
  cap or unreadable file fails rather than counting zero.
- **§13**: a plugin-bundled MCP server's tools are `mcp__plugin_<plugin>_<server>__…`, so every
  bare `mcp__<key>` grant needs its plugin form and vice versa, matched by suffix. Tool-scoped
  grants and a bare `mcp__*` are rejected; hosted connectors (`mcp__claude_ai_Figma`) are exempt.
- **§14**: an unquoted YAML scalar with `: ` drops the whole frontmatter, so a skill never
  triggers while reading fine to a human. Wrap the value in double quotes.

**Behavioral verification means running the scenario** from the plugin's
[`VERIFICATION.md`](plugins/crew/VERIFICATION.md) and citing the observed result. "Would pass" is
not verification, and neither is "needs a person": most rows run headless (`VERIFICATION.md`,
*Running a row headless*), so run them before asking the maintainer to. Run a row when the
change alters the mechanism it covers: a guard, an agent or command prompt, or a new kind of
route. A change that repeats a pattern a ticked row already proves (one more marker line that
routes to a product skill) needs no run and no new row: name the row it relies on.

## Releasing

Versions are per plugin, and one rule holds: **a shipped change bumps the version.** A tag
carries everything merged since the previous tag, so an unbumped change ships inside the next
release, described nowhere. Shipped means everything under `plugins/<name>/` except `tests/`,
`CLAUDE.md`, `VERIFICATION.md` and `CHANGELOG.md` itself; `README.md` counts, and so does a
comment inside a shipped hook. Repo-wide changes (CI, root docs, `scripts/`, `tests/`) need no
bump. Patch for a fix, minor for an addition, major for a break; several in a day is fine.

1. Bump `version` in `plugins/<name>/.claude-plugin/plugin.json` and add a matching `CHANGELOG.md`
   entry in the same PR. §2h fails CI unless they agree, and `check-changelog.sh` fails a shipped
   change without a bump.
2. Merge to `main`. `auto-release.yml` sees the version has no `<plugin>/v<version>` tag, and
   creates the tag and GitHub Release with that version's changelog section
   (`scripts/release-notes.sh`). No entry → it skips with a warning.

**Changelog entries are terse.** One bullet per change under its Keep-a-Changelog heading, one
line, two at most: *what changed*, with the PR as `(#N)`. The why belongs in the PR and commit.

## Conventions

- Hooks are Bash (`#!/usr/bin/env bash`), shellcheck-clean, and **BSD/macOS-portable**: `mktemp`
  with an explicit `XXXXXX` template, `[[:space:]]` not `\s`, no GNU-only flags. Quote every
  expansion, array subscripts included; `if ! var="$(cmd)"` still assigns `var`.
- Guards run before every tool call, so they match with `[[ =~ ]]` and parameter expansion, never
  a fork per pattern.
- Code comments explain *why* in one or two lines; a longer rationale lives once, here or in the
  changelog, and the comment points to it.
- Agent/command/skill files are Markdown with YAML frontmatter; match the field shape of their
  neighbours. In an agent, `skills:` is the last key (§2g).
- Local agent memory (`.claude/agent-memory-local/`) is gitignored. It and an unset plan directory
  resolve inside a **git worktree**, so `git worktree remove` deletes both; only committed content
  outlives it, which is what pointing `planDirectory` at a tracked path is for.
- Keep diffs minimal-scope; list unrelated improvements rather than bundling them.
- **Self-review the diff before every PR and every push to one**, merge and conflict-resolution
  pushes included (a resolution is new code nobody has read). Use the repo rubric
  (`.github/skills/code-review/SKILL.md`; the `crew-review` skill runs it with the checks and
  reproduces each finding) and fix every Blocking and Warning first. Copilot reviews with the
  same rubric, so what it would find, you find.
- PR titles follow Conventional Commits, `type(scope): summary`, with `(vX.Y.Z)` when the PR bumps.
  Types: `feat`/`fix`/`chore`/`docs`/`ci`/`refactor`; scope the plugin when the change is
  plugin-specific (`feat(crew): … (v1.9.0)`).
- **PR descriptions have a hard budget**: summary 150 words and 5 bullets at most, whole body
  under 400 words. The body says why, and what a reviewer needs to approve safely. Never a
  self-review, a bugs-found log, a narrative, design alternatives, or pasted output; those go in
  the commit message (not budgeted), the issue, or a review thread. Verification is a result
  ("ran X, all green"), not a transcript. After merging `main` into a branch, refresh the
  description: version ranges go stale.
- **Every review comment gets a reply, then the thread is resolved.** Fixed: name the commit.
  Declining: say why. Duplicate: say which.
- **A correct finding is fixed and pushed now**, whatever its label (nit, low, optional). Never
  defer it to "the next code push": the PR can merge before one comes, and the wrong line ships.
  Decline only a finding that is wrong, and say why.
- A PR that resolves an issue links it with a closing keyword (`Closes #N`).
- One branch and PR per issue, from the latest `main`: `git fetch origin main && git checkout -B
  <branch> origin/main`. A merged PR's branch is deleted; reusing the name leaves a stale tracking
  ref until pruned.
- READMEs, changelogs, PR bodies and issues follow the `writing-style` skill
  (`.github/skills/writing-style/SKILL.md`).

### Open up before you lock down

Fail closed is for **safety**: git, destructive and file-mutating Bash, secrets, pushes. It is not
for division of labour. When a guard cannot know the answer (which agent owns a file in a stack
the crew knows nothing about), open it and let `lead`'s plan or the agent's prompt hold the rule,
rather than add mechanism to refuse. The signs you are locking down the wrong thing: the fix needs
a list that will always miss a case, a parser, a new required slot, or a config shape some real
layout cannot express; or a second review round finds a new edge case of the same mechanism.
Opening up removes code; locking down adds it and still leaks. The worked example is the next
section. Reviewers: an opening documented here is not a fail-open finding.

### Why an `other` stack has open lanes

No extension list can split `backend`'s files from `frontend`'s for a stack the crew knows
nothing about (#301 found `.styl` past one), and required lane paths cannot express a root-level
backend. So with an `other` stack and no lane paths, `lane-guard` lets both write anywhere and
`lead`'s plan gives each step its own files. Every safety guard is unchanged, as are the
`unit-tests`, `e2e` and `lead` lanes; lane paths, when set, restore the directory split.

### The Bash guards are floors, not sandboxes

`bash-safety.sh` refuses a few command shapes. The rules below read like enforcement and are
not; several were widened once and reverted, and the hooks point here so it is not tried again.

- **The raw-read rule is a habit redirect**, so it applies to agent sessions only (#249). It
  blocks `cat f` and names `Read`; `grep . f`, `awk`, `tail -n 999999` and `python3 -c` dump the
  same file and are allowed. A missed read costs nothing and a wrong refusal costs a turn, so the
  pattern is one line and any pipe or redirect ends the match. Following bytes through redirects
  needs bash's tokenizer (#226: two regressions in six rounds, reverted).
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
  hidden segments, quotes and an unset project dir all count as inside. Reasoning about what bash
  would expand leaked three rounds running (#264). Open gaps: a symlink outside the project that
  points into it, and a main checkout written from a worktree session.
- **The write scan reads heredoc bodies too**, so HTML or prose in one (`<h3>`, "apply the
  patch") is refused as a write. Write the text with `Write` to a scratch path and pass the file
  instead (`--description @file`). A heredoc reader drew a bypass in each of two review rounds
  and was dropped (#295).
- **`rm -rf` refuses every target starting with `/`, `~` or `*`**, build dirs included. A
  whole-token match let `/*/` and `/tmp/../*` through (#264). Out-of-tree cleanup is `rm -r`.
- **The `git mv` carve-out reads line starts because it is an allowance**: a false separator can
  only wave through a `git mv` inside a string, never refuse anything. The floor decides *what* a
  `git mv` is, not *whose*: it lets any agent run a plain one. `bash-safety.sh`'s no-git roster
  lets a worker run only a `git mv` alone in the command with relative paths (no `-C`, `cd` or
  `..`), so the rename stays in the tree it was dispatched to (#249, #263). Open gaps: no lane
  guard sees a `git mv`, so `lead` checks renames in the staged diff; a cwd a worker moved
  with an earlier `cd` call is not checked.

### Init is the only detector

A value that is a property of the project and that a human can confirm once (the stack, the
tools, the paths, the commands) is a slot in `.claude/crew.md`, proposed by `/crew:init` from the
stack skills' *Crew config* sections and confirmed by the user. Hooks and `lead` read slots;
none of them detects, and a missing slot is a stop naming `/crew:init`, never a guess. Until
7.0.0, `lead`, `lane-guard.sh` and `format.sh` each detected too: duplicated markers, misses that
failed open, and agent memory as a second config store. A rule of behavior (who owns git, what a
lane may touch, which commands hang) stays in the crew; the Bash guards' command lists are
floors, not project knowledge.

### Why `format.sh` runs a matrix and detects nothing

Which formatter a project uses is a property of the project, so `/crew:init` proposes
`formatMatrix` rows from the stack skills, the user confirms them, and the hook only runs them.
Per-edit detection (340 lines and two awk parsers until 6.0.0) is gone. Consequences:

- **No fallback.** A missing slot, `none` or `unset` means per-edit formatting is off and the
  lint gate catches the result. A detection fallback would keep the 340 lines.
- **Staleness has two signals, neither a scan.** A tool that is gone exits 127, which the hook
  reports with a `/crew:init` nudge the worker hands back; a config that is new fails the lint
  gate on formatting alone, which `review-gate` reports as a stale matrix. `lead` never
  walks the tree for formatter configs: that list belongs in `init.md` only.
- **A row is a command string run from a committed file on every edit.** The same trust posture
  as the gate's test command slot (`scripts/gate.sh` runs one with `bash -c` too).
- **Accepted gaps.** Rows are inclusive, so a path black would exclude needs no row rather than a
  row that reformats it; a Rust edition is a row per crate, so a workspace mixing editions
  without crate rows formats on the default; only a standalone tool exits 127, so a wrapper
  whose subcommand is gone (`dotnet csharpier`) reads as a failure and the lint gate carries
  the stale-matrix report; a directory is single-quoted when it holds a space, and one holding
  a quote has no row.

## Recurring review findings

Patterns that showed up more than once in review on this repo. Apply them up front:

- **Verify before filing a "nothing enforces this" issue.** Grep the implementation and this file
  first; a drift-guard issue was filed against a check the validator already had.
- **A validator or guard fails loudly on every path where it cannot verify its claim**: a missing
  input, invalid input, an unreachable check. Never skip silently.
- **Anchor a delimiter split on the trusted field.** Splitting on the first occurrence is safe
  only when the field before it is a small controlled value that cannot contain the delimiter;
  put untrusted text last, or split from the end.
- **A new conditional in a multi-mode flow is spelled out for every mode**, not only the default.
- **State heuristics as heuristics.** "X is unlikely" is not "X can't happen".
