---
name: code-review
description: Review a pull request or diff in the crew plugin marketplace — Bash guard hooks, Markdown agent/command/skill prompts, plugin manifests and changelogs. Use when asked to review code, a PR, or a diff in this repository.
---

# Reviewing a crew change

This repo ships Bash hooks, Markdown prompts that agents execute, and JSON manifests. `AGENTS.md` is
the contributor guide and wins on conflict. Code rules: the `engineering-principles` skill
(`plugins/crew/skills/engineering-principles/SKILL.md`). This file is the one rubric and owns the
output format; Copilot reads it directly and Claude Code's `crew-review` skill loads it.

## Scope: one full pass, then only what changed

- **First review: every changed hunk ends as a finding or a Passed line.** Also read what the
  diff makes newly reachable: a new caller, a pattern now matched against a different input.
- **Re-review after a push: review the new commits.** Raise an old, unchanged hunk only if it is
  Blocking. Never reopen a resolved thread with the same point reworded.
- **One root cause, one finding.** When findings share a cause (the same parser, the same
  missing case), report the cause once as a design finding and stop listing instances.

## Severity: earn it with an input

- **Blocking** needs a concrete command, payload or file state, and the wrong verdict it gives
  that the base branch did not. No input, no Blocking.
- **A bypass through a documented gap is not a finding.** The Bash guards are floors, not
  sandboxes: newline flattening, `bash -c`, interpreters, `$(...)` and the raw-read scope are
  open on purpose (`AGENTS.md`, "The Bash guards are floors, not sandboxes"). Flag only a change
  that widens a gap or tries to close one with a pattern.
- **Prefer less code.** When a fix grows a parser (quotes, heredocs, escapes) to close an edge
  case, say so and suggest removing the rule or accepting the documented gap. A partial tokenizer
  always has a next edge case; #226 and #231 both reverted one.
- **Open up before you lock down.** Fail closed is for safety, not division of labour: do not ask
  a guard to refuse what it cannot know, and do not flag an opening `AGENTS.md` documents
  ("Open up before you lock down").
- Style-only notes are not findings unless they break a written convention.

## Guard hooks (`plugins/*/hooks/**/*.sh`)

- **Name each pattern's failure direction.** An allowance (match lets it through) may
  over-match. A refusal (match exits 2) must not refuse ordinary work. A refusal that reads line
  starts or quoted text is Blocking.
- Probe changed patterns with: a second line, a backslash-newline, a quoted string, a heredoc,
  `;`/`&&`/`|`, an env prefix (`FOO=1`, `env`, `command`), `find -exec`, and `*` or `[` in a value.
- `bash-safety` and `lane-guard` fail closed (exit 2 without their library or
  `jq`); `read-guard`, `format`, `dispatch-denied` and `plan-guard` fail open. A
  change that flips a hook's direction is Blocking.
- Match with `[[ =~ ]]` and parameter expansion, no fork per pattern. Quote expansions used as
  patterns (`${x#*"$m"}`). POSIX classes, no `\s` or `\b`, no GNU-only flags.
- A roster rule lives below the floor in `bash-safety.sh`. Do not reshape `# crew-roster:` arms
  (validator §9).

## Prompts (`agents/`, `commands/`, `skills/`)

These files are executable contracts written in prose: `validate-plugin.sh` catches structural
drift, never a design bug, and most review misses here were design bugs. Authors apply the same
lens before they push.

- **Durable-state invariant.** If one store is "the only cross-run state", every count or
  "N-in-a-row" lives there, never in an in-memory tally a fresh-context resume would lose.
- **Delegation can only pass what the callee accepts.** A wrapper cannot convey what the inner
  command does not forward; launch the agent directly and say so.
- **Every threshold is a number**, with what resets it.
- **Every failure and edge path has a stated behavior**: stop, skip or surface, and which durable
  state is or is not mutated.
- **A structured field documents its shape where it is owned**, and the owner is told to
  preserve it verbatim on rewrite.
- **Every skill a prompt names exists.** Check each new backticked skill name against
  `plugins/<plugin>/skills/<name>/`: a missing one fails the worker's `Skill` call. The validator
  checks only `crew:` refs (§10) and `skills:` frontmatter (§2g); a name match by prefix also
  hits package names (`optimizely-sdk`), so this check stays with the reviewer.
- **Cross-file wording agrees.** Grep every term the diff changed across the command, its agent
  and the README/AGENTS/CLAUDE/CHANGELOG copies.

## Release, tests, docs

- **Shipped change without a bump** (anything under `plugins/<name>/` except `tests/`,
  `CLAUDE.md`, `VERIFICATION.md`, the changelog): Warning; Blocking if users miss a fix.
- **Hook behavior change**: allow and block cases in the plugin's suite for the
  hook, asserting its output contract (stderr for a guard, stdout JSON for `dispatch-denied`).
  A new case must fail on the base code.
- **Any other behavior change without a test** that would catch its regression is a Warning.
- **Plugin `CLAUDE.md`** must match the code in the same PR.

## Security and design

- **Security pass, always:** untrusted input (a command, a payload, a PR comment an agent reads)
  validated at the boundary; no injection into a shell, regex or prompt; no secrets in files,
  logs or prompts; no safety guard that fails open where it should fail closed; a new dependency named
  and justified.
- **Design conformance** only when UI changes: layout, spacing, color, typography and component
  states against the design reference.

## Verbosity is a finding

- **One rationale, one place.** The reason lives in `AGENTS.md`; code comments explain *why* in
  one or two lines and point there. The same explanation in three files is a Warning.
- Comments that restate the code, and PR bodies over the template's budget, are nits.

## Output

`## Blocking`, `## Warnings`, `## Passed`. One bullet per finding: `path:line` — defect —
failing input — smallest fix. A Warning should be fixed but does not block merge; a test-only
issue is a Warning unless it hides a correctness gap. Under Passed, one line per lens applied,
plus any informational note that asks for nothing.

**Every Blocking or Warning finding is a review thread on its line**, including one in a hunk
the last review passed over. A finding that exists only in the summary (a "previously missed"
list, a bullet with no thread) cannot be replied to or resolved, so the author's loop never
sees it. The summary repeats the threads; it never holds a finding of its own.
