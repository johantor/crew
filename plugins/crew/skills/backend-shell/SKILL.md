---
name: backend-shell
description: Shell/Bash project conventions — POSIX vs bash, the traps in `set -euo pipefail`, BSD/macOS portability, shellcheck as the gate, and matching in-process rather than forking. Load when the resolved backend stack is shell.
---

# Backend: Shell

You are working in a shell codebase: scripts, hooks, CI helpers, or a tool whose deliverable *is*
the shell. There is no compile step and often no application beside it — the scripts are the
product.

## Crew config

`/crew:init` proposes: build is the static gate — `shellcheck <globs>`, taking the globs from CI
since the shell's `*` does not cross directory separators and one pattern usually misses a
subdirectory, optionally with `bash -n`; test the project's own runner (`bash tests/run.sh`,
`bats tests/`); lint `shellcheck` plus `shfmt -d` where shfmt is configured. No format matrix
row: shfmt's configuration is `.editorconfig`, whose section globs only shfmt itself resolves,
so shell formatting belongs to the lint gate.

## Decide which shell a file may assume

The shebang is a contract, and the file has to keep it:

- `#!/usr/bin/env bash` — bash features are available: `[[ ]]`, arrays, `local`, `=~`.
- `#!/bin/sh` — POSIX only. `[[ ]]`, arrays, `local` and `+=` are **not** POSIX; a script that uses
  them under `sh` works on a system where `/bin/sh` is bash and breaks where it is dash.

Never add a bash-only construct to a `sh` script to make something convenient. Either keep it
POSIX or change the shebang deliberately and say you did.

## `set -euo pipefail` does not do what it looks like

**In bash.** `-o pipefail` is not POSIX and `dash` exits on it, so a `#!/bin/sh` script gets
`set -eu` and handles pipeline failure explicitly. Adding `pipefail` to a POSIX script breaks it at
the first line.

Use it in bash, but know where it stops:

- **`local x="$(cmd)"` swallows the failure.** `local` is itself a command, and its exit status is
  what `-e` sees — always zero. Declare first, assign second: `local x; x="$(cmd)"`.
- **`-e` does not fire in a condition.** In `if cmd`, `cmd && …`, `cmd || …` or a `!` negation the
  command may fail freely. That is usually what you want; it is not a place to rely on `-e`.
- **`-e` does not reach into a subshell's caller** the way people expect, and a command
  substitution in an argument list is a subshell.
- **`-u` and an empty array.** Under bash before 4.4, `"${arr[@]}"` on an empty array is an
  unbound-variable error. Guard with a length check — `[ "${#arr[@]}" -gt 0 ] && cmd "${arr[@]}"`.
  Do **not** reach for `"${arr[@]:-}"`: on an empty array that expands to one empty argument, so
  the command receives an extra `''` it never asked for.
- **`pipefail` changes what a pipeline returns**, so a `grep` that matches nothing now fails the
  script. Guard it (`|| true`) where an empty match is a legitimate outcome — and only there.

## Quoting and tests

- Quote every expansion unless you have a reason not to, and say the reason. `$*` vs `$@` is not a
  style choice: `"$@"` preserves argument boundaries and `$*` destroys them.
- `[[ ]]` over `[ ]` in bash: it does not word-split, so `[[ -n $x ]]` is safe unquoted, and `=~`
  gives you regex without a fork.
- Compare with `=`/`==` for strings and `-eq` for integers; `[ "$a" == "$b" ]` is a bashism inside
  `[ ]`.

## Portability: GNU is not the baseline

If the project runs on macOS or BSD — assume it does unless told otherwise — these differ:

- `mktemp` needs an explicit template: `mktemp -d "${TMPDIR:-/tmp}/name.XXXXXX"`. Bare `mktemp -d`
  and GNU's `-p` are not portable.
- `sed -i` takes a mandatory suffix argument on BSD. Write to a temp file and move instead.
- `timeout` is GNU coreutils and absent on stock macOS (`gtimeout` via brew). Degrade rather than
  fail when neither exists.
- `grep -P` is GNU-only; `readlink -f`, `date -d` and `stat -c` all differ.
- Keep regexes POSIX so BSD and GNU `regcomp` agree.

## Performance in a hot path

A script that runs on every tool call, every file, or every loop iteration pays for each process
it starts. Prefer bash's own facilities to a pipeline:

- `[[ $s =~ $re ]]` and `${s#prefix}`/`${s%suffix}`/`${s//a/b}` instead of `echo "$s" | grep` or
  `| sed`.
- One traversal that collects everything, not one `find` per marker.

In cold code, clarity wins — do not contort a one-off script to save a fork.

## Build and lint

There is no build, so the crew-config **backend build command** is the static gate the project
configures — almost always `shellcheck`, sometimes with `bash -n` beside it.

What weakens the gate: a narrowed file list, or a lowered `--severity`. A
`# shellcheck disable=` names its code and says why, on the line it applies to; a blanket disable
at the top of a file, or one with no reason, is a finding — report it rather than adding one.
`shfmt -d` (diff mode) is the formatting check; the `-w` form is not a gate. Report findings as
the code (`SC2086`), `file:line`, and a count per code.

## Docs

The authority for a shellcheck code is its own wiki page, and for a builtin the bash manual.
