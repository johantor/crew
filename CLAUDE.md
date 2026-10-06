# crew — Claude Code notes

This repository is the `johantor` Claude Code plugin marketplace (`crew`):
orchestrated agents, commands, hooks, and skills. **This repository *is* the plugins** —
there is no application code to build or ship.

**Start with [AGENTS.md](AGENTS.md)** — the contributor guide (repository layout, how the
crew works, reviewing, validating, releasing, and conventions). It is tool-neutral and the
single source of truth for working in this repo.

Plugin-specific maps (schemas, file inventories, validator gotchas, release steps) live next
to each plugin and load automatically when working under it — start there instead of
re-exploring:

- [plugins/crew/CLAUDE.md](plugins/crew/CLAUDE.md)

Keep them accurate: a PR that changes anything they state updates them in the same commit.

## Communication style

Use ASD-STE-100 (Simplified Technical English) when you speak to the operator: short sentences,
the active voice, one instruction per sentence, and the same word for the same thing each time.
This applies to what you say to the operator, not to what you write into the repository — files,
docs, and commit messages keep the repo's own voice.

## Engineering rules

Every change here follows
[`engineering-principles`](plugins/crew/skills/engineering-principles/SKILL.md). Read it before
you write code, and re-read your diff against it before you finish. Before you open a PR or push
to one, run the `crew-review` skill on the diff and fix its Blocking and Warning findings first
(`AGENTS.md`, *Conventions*).

## Brevity

- **Replies**: the result first, then what the operator must decide. No recap of work they saw,
  no option you will not take. Under 150 words unless the operator asks for more.
- **Code comments**: explain *why*, in one or two lines. A longer rationale lives once, in
  `AGENTS.md`, and the comment points there. Never the same rationale in several files.
- **Docs and PR bodies**: facts, not history. Before you add a paragraph, cut one.
- **Fixes**: prefer removing code to adding a parser, and opening a rule to locking it down
  (AGENTS.md, *Open up before you lock down*). If a second review round finds new edge
  cases of the mechanism you already patched, stop fixing instances and ask the operator: redesign,
  or accept the gap and document it in AGENTS.md. (#224 went 100+ threads without this.)

## Rules for every plugin

The rules live once, in [AGENTS.md](AGENTS.md); plugin `CLAUDE.md` files hold only what differs
per plugin. Read the section before you touch its area:

- **Validating** (every `run:` step in `.github/workflows/validate.yml`, the `§N` section map,
  staging new skill files): *Validating changes*.
- **Hooks and shell** (portability, no fork per pattern, the open gaps): *Conventions* and *The
  Bash guards are floors, not sandboxes*.
- **Agents and prompts** (frontmatter, MCP pairs, footprint cap): *Validating changes* and
  *Prompt design rationale*.
- **Release** (bump by default, changelog bullets): *Releasing*.

## Reading and editing files

Reads and writes in this repository go through the `Read`, `Edit` and `Write` tools, not
through the shell. A guard hook enforces it (start a session here with
`claude --plugin-dir plugins/crew`, which loads the crew hooks), so the glance-level habit fails
here:

- **Reading a file**: use `Read`. A bare `cat <file>` is refused in agent sessions — a shell
  read reaches no `PreToolUse(Read)` hook, so the size bound in `read-guard.sh` never applies
  to it. Bounded shell reads stay available and are the right tool for a slice: `head`,
  `sed -n '10,40p'`, `grep`, `jq`, and any `cat` whose output is piped into a filter.
- **Changing a file**: use `Edit` or `Write`. An in-place `sed`/`perl`, a `tee`, a `cp`/`mv`,
  or a redirect into the checkout is refused in agent sessions, because such a write reaches
  no `PreToolUse(Edit|Write)` hook and would skip both the write lanes and the formatter.
  Scratch output under `/tmp`, and an unquoted absolute path outside the project, is exempt.

Both rules close the same gap: a shell that edges around the tool the hooks are wired to.
The refusal message names the tool to use instead, so a blocked command has a one-step fix.

The rest of this file describes how the orchestration works. It stays in the project-root
CLAUDE.md because its reader is anything that reads `CLAUDE.md` to understand this repo —
including auto mode's permission classifier, which otherwise has only a dispatch label to judge a
worker delegation by. The crew's **configuration** is not here: it lives in
[.claude/crew.md](.claude/crew.md), one frontmatter key per slot, written and reconciled by
`/crew:init`.

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
