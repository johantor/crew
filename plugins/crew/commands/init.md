---
description: Detect the project's crew configuration and write it to .claude/crew.md (idempotent — re-run to reconcile settings a newer plugin version added)
---

Set up (or reconcile) the **crew configuration** the orchestrator reads. This command
detects the project's build/test/lint commands, per-edit formatters, base branch, frontend mode,
and backend/frontend stack, shows you what it found, and writes the agreed values to **`.claude/crew.md`**.
It is **idempotent**: the first run bootstraps the file; a re-run reconciles it, adding any
slots introduced by a newer plugin version **without overwriting values you've already set**.

Two destinations, split by **audience** — not by tool:

- **`.claude/crew.md`** — every slot in §1. Committed by default, so a teammate who installs
  the plugin inherits them, and reviewable in a pull request; or kept local, git-excluded (§4).
  This is machine configuration for a dispatcher: it is read on demand, not auto-loaded into
  every session. It is the only place the crew reads configuration from.
- **`CLAUDE.md`** — the `## Crew orchestration` prose (§3, which has a reader that sees only
  `CLAUDE.md`) plus the few repo conventions a careful reader would get **wrong** (§3's bar),
  in tool-neutral wording. Slot values never go here. A `## Crew configuration` section left
  by a plugin older than 3.21.0 is not read: say so, and propose removing it once its values
  are in `.claude/crew.md`. For **Local** (§4), these go to `CLAUDE.local.md` instead.

Do the detection read-only first, then confirm with the user before writing anything.

## 1. Canonical configuration slots

The slots the crew reads, each with its `.claude/crew.md` key. This list is the source of truth
for what "complete" means — reconcile fills any that are missing, and CI keeps it in lockstep
with this repo's own `.claude/crew.md`. This command is the only detector: `lead` never
detects, remembers or guesses a slot, and a slot a step needs that is still `unset` stops the
run until this command fills it (`branchNaming` is asked once per run instead, and
`planDirectory` defaults).

- **Frontend mode** (`frontendMode`) — `headless` or `server-rendered`. Orthogonal to the
  stack: Next.js is `headless` even though it server-renders, since there is no shared server
  template.
- **Backend stack** (`backendStack`) — `dotnet`, `node`, `python`, or `shell`; `other` for a
  stack the crew ships no skill for (Go, Rust, Java, Ruby, …), best effort: the crew works from
  the configured commands and the project's own skill, and `lead`'s plan, not the lane guard,
  keeps `backend` and `frontend` apart unless lane paths are set. The
  lane guard refuses `backend`/`frontend` while it is `unset`.
- **Backend skill** (`backendSkill`) — only with `other`: the project's own skill for its stack,
  by name, which `lead` hands to `backend` and `unit-tests`; `none` when it has none. `unset`
  for every other stack.
- **Frontend stack** (`frontendStack`) — `react`, `nextjs`, `other`, or `none`;
  `none` is a statement: the project has no client-facing surface (a library, a headless service,
  a script pack), so `lead` skips frontend mode, e2e and unit-tool resolution and never
  dispatches the frontend workers. `other` is a web view the crew ships no skill for (Vue,
  Svelte, Angular, Astro, …), best effort like the backend's. **A TUI, or
  a CLI whose rendered output is designed, is a view** in `frontend`'s lane with no supported
  value yet — stop and surface unsupported rather than writing `none`, `other` or `unset`.
- **Frontend skill** (`frontendSkill`) — only with `other`: the project's own skill for its
  frontend, by name, which `lead` hands to `frontend`; `none` when it has none. `unset` for every
  other stack.
- **Frontend e2e tool** (`frontendE2eTool`) — `cypress`, `playwright`, or `none` when the
  project has no e2e suite (a confirmed absence: `e2e` is then never dispatched).
- **Frontend unit test tool** (`frontendUnitTestTool`) — `vitest`, `jest`, or `cypress`; `unset`
  when the project has no frontend unit tests, and `unit-tests` then scopes to backend tests.
- **Backend lane path(s)** (`backendLanePaths`) — comma-separated path prefixes, e.g. `apps/api/`.
  Only when backend and frontend stacks are the same language (Node backend + Next.js): by
  extension `lane-guard.sh` cannot tell `backend`'s and `frontend`'s files apart and falls back
  to these. Optional with an `other` stack, for the guard to split the lanes there too. `unset`
  otherwise.
- **Frontend lane path(s)** (`frontendLanePaths`) — e.g. `apps/web/`; same caveat. A lane path
  is a directory: never `./` or `.` (it covers the whole tree, so the other lane can write
  nothing). Files outside both lanes (a backend's root `Program.cs`) are open to both, except
  route handlers (`app/**/route.ts`, `pages/api/**`), which stay `backend`'s.
- **Backend test command** (`backendTestCommand`) — e.g. `dotnet test`.
- **Frontend test command** (`frontendTestCommand`) — the **e2e** suite only (e.g. `npx playwright
  test`); `unit-tests` derives unit/component runs from the Frontend unit test tool instead.
- **Backend build command** (`backendBuildCommand`) — e.g. `dotnet build`.
- **Frontend build command** (`frontendBuildCommand`) — e.g. `tsc --noEmit` / `vite build`.
- **Backend lint command** (`backendLintCommand`) — verify mode, e.g. `dotnet format
  --verify-no-changes`.
- **Frontend lint command** (`frontendLintCommand`) — the lint script in report/verify mode.
- **Format matrix** (`formatMatrix`) — the per-edit formatters, as a block scalar (`formatMatrix: |`)
  with one row per line: `<dir> <extensions> <command>`. `format.sh` runs every row whose
  directory prefix (`.` for the whole project) and comma-separated extension list match the
  edited file, in order, from that directory, with `{file}` replaced by the file's path relative
  to it; a directory holding a space is single-quoted (`'my service/' cs …`). A file no row
  covers is left alone. `none` when the project has no single-file
  formatter; whole-project formatters (`dotnet format`, shfmt via `.editorconfig`) stay
  at the lint gate and get no row.
- **Base branch** (`baseBranch`) — the branch `lead` branches off (`main` / `develop` / trunk).
- **Branch naming** (`branchNaming`) — e.g. `feature/<ticket>-<slug>`.
- **Run/dev URL** (`runUrl`) — the local dev URL, if the project serves one.
- **Plan directory** (`planDirectory`) — where `lead` writes `plan-<feature>.md`; `unset` uses
  the `.claude/` fallback. Set it (e.g. `docs/plans/`) for a committed location.

Free-text notes for the crew are not a slot: they go in the file's **body**, below the
frontmatter — why a slot is set the way it is, a caveat on a command, which areas of the app are
headless when the mode is mixed. The body is prose, and reconcile preserves it verbatim.

The file's shape:

```markdown
---
backendStack: dotnet
backendSkill: unset
frontendStack: react
frontendSkill: unset
frontendMode: server-rendered
frontendE2eTool: cypress
frontendUnitTestTool: unset
backendLanePaths: unset
frontendLanePaths: unset
backendTestCommand: dotnet test
frontendTestCommand: npx playwright test
backendBuildCommand: dotnet build
frontendBuildCommand: npm run build
backendLintCommand: dotnet format --verify-no-changes
frontendLintCommand: npm run format:check
formatMatrix: |
  src/Site  ts,tsx,scss  node_modules/.bin/prettier --write {file}
  src/Site  ts,tsx       node_modules/.bin/eslint --fix --cache {file}
  .         cs           dotnet csharpier format {file}
baseBranch: develop
branchNaming: feature/<ticket>-<slug>
runUrl: https://localhost:5001/
planDirectory: unset
---

Notes the crew should carry: npm scripts run from `src/Site`, not the repo root.
```

## 2. Detect (read-only)

Inspect the repo and propose a value for each slot. Cite where each came from so the user can
trust or correct it; never invent a command you can't see configured.

| Slot | Detect from |
|---|---|
| Backend stack | `*.csproj`/`*.sln` → `dotnet`; `package.json` with a server framework (NestJS/Express/Fastify) and no SPA-only bundle config → `node`; `pyproject.toml` (or `requirements*.txt`/`setup.py`/`Pipfile`) → `python`; `*.sh`/`*.bats` with no other backend marker → `shell` (the scripts are the deliverable, not a repo that merely has a build script). Only other languages' markers (`go.mod`, `Cargo.toml`, `pom.xml`, `Gemfile`, …), one or several → propose `other` and say the crew has no skill for it. Markers for two supported backends → ask which governs the crew, don't break the tie; an unsupported marker beside a supported one does not count. |
| Backend skill | Only for `other`: a project skill (`.claude/skills/<name>/SKILL.md`, or one the user names) whose description covers the stack → propose its name; else `none`. `unset` for a supported stack. |
| Backend build, test, lint | Load the detected stack's `backend-<stack>` skill and propose what its **Crew config** section says; it names the static gate for a stack with no compile step and the runner prefix a command needs. For `other`, propose only the commands the project configures (a `Makefile` target, a CI step, the backend skill) and ask for the rest; a slot nobody can name is `none`. |
| Frontend stack | `next.config.*` → `nextjs`; a React/Vite SPA build without it → `react`; another view framework in `package.json` (`vue`, `nuxt`, `svelte`, `@angular/core`, `astro`, …) → propose `other` and say the crew has no skill for it; no client-facing surface → propose `none` and say why. A TUI or designed CLI output → stop, unsupported. |
| Frontend skill | As Backend skill, for a frontend `other`. |
| Frontend build, test, lint | `package.json` `scripts`: `build`/`typecheck` → build, `test`/`e2e`/a Playwright config → test, `lint` → lint. Use the scripts that exist; don't assume an `npx` download. A script that only runs from a subdirectory says so in the value: `npm run build (from src/Site)`. |
| Format matrix | One row per configured single-file formatter per package, from the package's own directory (in a monorepo that is not the root); a package with Prettier and ESLint gets two rows. Backend rows come from the `backend-<stack>` skill's **Crew config** section. Web rows from the configs in the package (a config file, or the matching `package.json` key): `biome.json*` → `node_modules/.bin/biome check --write {file}`; `.prettierrc*`/`prettier.config.*`/a `prettier` key → `node_modules/.bin/prettier --write {file}`; `.eslintrc*`/`eslint.config.*`/an `eslintConfig` key → `node_modules/.bin/eslint --fix --cache {file}` (script extensions only); `.stylelintrc*`/`stylelint.config.*`/a `stylelint` key → `node_modules/.bin/stylelint --fix {file}` (style extensions only). Always the locally installed binary, never `npx`. A tool merely on `PATH` with no config is not the project's choice: no row. No single-file formatter anywhere → `none`. |
| Frontend mode | An SPA build (React, Vue, Svelte, Angular, Next, Nuxt, …) → `headless`; Razor `.cshtml` views without an SPA bundle → `server-rendered`. Mixed or unclear → **ask** which mode governs the areas the crew will work in, write that one, and describe the split in the body notes. Never leave it `unset`: `lead` stops on it and sends the user back here. |
| Frontend e2e tool | `cypress.config.*` or a `cypress/` directory → `cypress`; `playwright.config.*` → `playwright`; neither → `none`, a confirmed absence, never `unset`. |
| Frontend unit test tool | `vitest.config.*` → `vitest`; `jest.config.*` or a `jest` key with no vitest → `jest`; a `cypress.config.*` `component` key with neither → `cypress`. Absent → `unset`, a confirmed absence that stops nothing. |
| Lane paths | Never auto-detect. Only when backend and frontend stacks are the same language, and then ask for the paths. With an `other` stack beside a frontend, say they are optional and leave them `unset` unless the user gives them. |
| Base branch | `git symbolic-ref refs/remotes/origin/HEAD`, else an existing `main`/`develop`. Ambiguous → ask; `origin/HEAD` is often unset or stale, and a wrong base is expensive. |
| Run/dev URL, branch naming | Dev scripts, `launchSettings.json`, existing branch names; else `unset`. |
| Plan directory | Only an obvious existing convention (`docs/plans/`, tracked `plan-*.md` outside `.claude/`); else `unset`. |

When detection comes up empty, pick the placeholder by slot type — never a value that makes the
config unusable:

- **Tooling slots** (test, build and lint commands; format matrix; run/dev URL): `none` when the
  project genuinely has no such tooling. Gates that need it then skip with that note.
- **Project-identity slots** (base branch, branch naming, frontend mode, backend stack): `unset`,
  never `none` — a base branch always exists. `lead` stops on it and sends the user here, so
  ask now rather than leave it.
- **Frontend stack is the exception.** `none` is a real answer: write it when confirmed, since
  `unset` would send `lead` asking a question a CLI or a script pack cannot answer.

Write both placeholders as plain YAML values — `unset` and `none`, never quoted, never
backticked — so reconcile recognizes them later. Write every key, so a slot a newer plugin
version added is visibly unadopted rather than merely missing. Don't guess to fill a blank.

## 3. What belongs in `CLAUDE.md`

Two things, and no slot values.

**First, the `## Crew orchestration` prose.** Ensure that section exists (for **Local**, in
`CLAUDE.md` or `CLAUDE.local.md`). It carries no slots and
nothing detects into it — it is fixed prose, added once and left alone on reconcile if the user has
edited it. Its audience is anything that reads `CLAUDE.md` to understand this repo, including auto
mode's permission classifier: the classifier reads the same `CLAUDE.md` Claude does, and without
this it has only a dispatch label to judge a worker delegation by. That reader is why this prose
stays in `CLAUDE.md` while the configuration moves out. Keep it descriptive — it states what the
crew *is*, and never instructs the classifier to permit anything.

```markdown
## Crew orchestration

Development in this repo is orchestrated: `lead` plans the work and delegates each step to a
worker subagent (`backend`, `frontend`, `unit-tests`, `e2e`, `visual-review`, `generalist`, `incident-triage`, `debt-scout`). Dispatching a
worker is ordinary in-repo development — the worker reads files in this working tree, an
implementer edits them (`visual-review`, `incident-triage` and `debt-scout` carry no edit tool), and each returns
a summary. It is not remote execution, and it sends nothing outside the repository.

The crew's guard hooks bound what a worker can do: only `lead` touches git, no agent commits on
the base branch, each worker's edits are confined to its own lane — through `Edit`/`Write`, and
file-mutating Bash is refused so a write cannot route around the lane — and destructive shell
commands are refused. Nothing is pushed and no pull request is opened on its own — `/crew:pr` is the only
path out of the machine, and the user invokes it.
```

Fix the worker list and the last line if this project's crew differs (a repo that never uses
`/crew:pr`, say). Don't add project-specific claims you haven't verified.

**Second, repo conventions — but only the ones a glance gets wrong.** Detection is cheap and
`package.json` maintains itself, so the bar for a `CLAUDE.md` line is not "is it true?" but:

> **Would a quick glance give the right answer, or a plausible wrong one?**

Propose a line only when the glance misleads. Typical earners:

- A script whose name hides what it does — a `format` script that **writes** fixes, so an agent
  asked to *check* formatting runs it and dirties the working tree. That needs saying;
  `npm run build` does not.
- A build that must be invoked a particular way to be safe (output redirected away from a running
  dev server), or whose success output can lie (a "0 warnings" build that compiled nothing).
- A unit convention that silently corrupts translated values — `html` at 62.5%, so `1rem = 10px`.
- Wiring no linter or type-check can see, so a green run doesn't mean it is connected.
- Generated files that must not be committed, where the generator isn't obvious.

Never propose: the stack, a bare build/test command, the dev URL, tool names — every one is a
glance away, and a written copy rots while the config file doesn't. Write what survives as ordinary
repository conventions in the repo's existing voice, with no crew vocabulary: their audience is
anyone working in the repo, including teammates who have never installed this plugin. If
`CLAUDE.md` already covers a point, leave it alone.

## 4. Confirm with the user

Show two tables — the §1 slots (slot · proposed value · source) and any proposed `CLAUDE.md` lines
(line · why a glance misleads) — and let the user confirm or edit each before anything is written.

When `.claude/crew.md` does not exist yet, also ask where init writes:

- **Committed** (default) — `.claude/crew.md` and `CLAUDE.md`, shared with the repo, so
  teammates inherit them.
- **Local** — nothing checked in: `.claude/crew.md`, and `CLAUDE.local.md` in place of
  `CLAUDE.md`, which Claude Code loads alongside it. Both are added to the file
  `git rev-parse --git-path info/exclude` names. Say the cost: a git worktree holds only tracked
  files, so a worker in one finds no configuration and `backend`/`frontend` are refused there.

Skip the question when `git check-ignore -q .claude/crew.md` already succeeds: the run is
**Local**. On reconcile, don't ask: the same check decides, so report it. Local needs both files
untracked: if `git ls-files .claude/crew.md CLAUDE.local.md` lists one, stop and tell the user to
untrack it (`git rm --cached`) or choose Committed.

## 5. Write and reconcile

Every **Local** run, bootstrap or reconcile, first adds the lines `/.claude/crew.md` and
`/CLAUDE.local.md` to the exclude file with `Edit` (`Write` if it is missing), skipping a line
already there. Until that write succeeds, write nothing else: if it fails, stop and report it.

- **Nothing yet** → create `.claude/crew.md` with every slot from §1 and the confirmed values,
  and apply the confirmed `CLAUDE.md` additions from §3.
- **`.claude/crew.md` exists (reconcile)** → for each slot in §1: add its key if missing; fill it
  if present but still a placeholder (`unset` / `none`) and a value was detected and confirmed.
  **Never overwrite a key the user has set to a real value** — show those as "kept" rather than
  changing them; a `formatMatrix` block with rows is such a value, so propose new rows as a
  diff rather than rewriting the block. Preserve the body notes verbatim. The one exception: a
  value §1 no longer lists (a `backendStack` of `go`, `rust` or `java` from crew 6)
  is shown as "unsupported" with the supported values, `other` proposed first, and the user
  picks one or removes the crew from the project.

Before writing, show the exact set of additions and removals — a short diff of slots, plus the
`CLAUDE.md` lines kept, reworded, and dropped — and apply only after the user confirms.
Afterwards, report what was added, filled, kept, and dropped, and note that re-running reconciles
again after future plugin updates.

## 6. MCP namespace check (report-only)

Not a configuration slot — nothing is written for this. MCP servers are configured in the user's
own session, and the crew agents reach them through an allowlisted namespace, so a mismatch
between the two is invisible at runtime: an agent sees a server it can't call exactly as it sees
one that was never installed.

Report, don't guess. From the MCP tools visible in this session, list each server's namespace and
say which crew agent grants it (the plugin README's *Optional MCP servers* table is the mapping);
tell the user to run `/mcp` for the authoritative list, since a session sees only what it loaded.
Flag these two cases:

- **A server keyed differently from the README's keys** — its tools are `mcp__<key>__…`, so the
  fix is granting `mcp__<key>` to the relevant agent(s).
- **A plugin-installed server** — its tools are `mcp__plugin_<plugin>_<server>__…`. The agents
  already grant `mcp__plugin_<key>_<key>` for a plugin that ships one server under its own name;
  any other combination needs that exact prefix added to the agent's `tools:`.

If nothing is visible and the user expected a server, say so plainly rather than reporting the
configuration as complete.
