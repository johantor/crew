#!/usr/bin/env bash
# Shared harness for the crew hook tests. Guards are pure PreToolUse functions:
# JSON payload on stdin, allow (exit 0) or block (exit 2 + stderr). Feed a
# crafted payload, assert the exit code and an expected stderr substring. No
# LLM, no network.
#
# Sourced by tests/*.test.sh (CI runs each); see CLAUDE.md. HOOKS_DIR is plugin/hooks/,
# found from the calling test file (BASH_SOURCE[1]).

# No `set -e`: an assertion failure records and continues so one run reports
# every failure, not just the first.
set -uo pipefail

if [ -z "${BASH_SOURCE[1]:-}" ]; then
  echo "FATAL: tests/lib.sh is a harness — source it from a *.test.sh, don't run it" >&2
  exit 1
fi
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")/../plugin/hooks" 2>/dev/null && pwd)"
if [ -z "$HOOKS_DIR" ] || [ ! -d "$HOOKS_DIR" ]; then
  echo "FATAL: no hooks/ directory beside $(dirname "${BASH_SOURCE[1]}")" >&2
  exit 1
fi

for _tool in jq git; do
  command -v "$_tool" >/dev/null 2>&1 || { echo "FATAL: $_tool is required to run the hook tests" >&2; exit 1; }
done

# Abort the whole run. The fixture helpers below run in command substitutions, so
# a plain `exit` there would only leave the subshell; kill "$$" (the main PID —
# unchanged inside subshells) tears the run down for real. Guards mktemp failures
# so a helper never returns an empty path a later `git init`/hook would misuse.
die() { echo "FATAL: $*" >&2; kill "$$" 2>/dev/null; exit 1; }

tests_run=0
tests_failed=0

# All fixtures live under one root so cleanup works even though the helpers below
# are called in command substitutions (a subshell can't mutate a parent array).
# mktemp is given an explicit XXXXXX template throughout, never bare `mktemp` or
# the GNU-only `-p`, so the suite also runs on BSD/macOS (AGENTS.md, Conventions).
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/crew-hook-tests.XXXXXX")" || die "mktemp -d failed"

# new_tmpdir -> echoes a throwaway dir under FIXTURE_ROOT (so the EXIT trap alone
# cleans it up). Lets callers make scratch dirs without touching FIXTURE_ROOT.
new_tmpdir() { mktemp -d "$FIXTURE_ROOT/d.XXXXXX" || die "mktemp -d failed under $FIXTURE_ROOT"; }

_pass() { tests_run=$((tests_run + 1)); }
_fail() {
  tests_run=$((tests_run + 1))
  tests_failed=$((tests_failed + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

# run_hook <hook> <payload> [cwd]
# Runs the hook with <payload> on stdin. With no cwd, runs in a fresh empty temp
# dir so the guard can't accidentally read this repo's .git or CLAUDE.md. Sets
# _status (exit code), _stderr and _stdout (both captured).
#
# The guards say everything on stderr, so _stdout is empty for them. The
# exception puts JSON on stdout: dispatch-denied.sh (its whole decision).
run_hook() {
  local hook="$1" payload="$2" cwd="${3:-}"
  local tmp_cwd="" err_file out_file
  if [ -z "$cwd" ]; then
    tmp_cwd="$(new_tmpdir)"
    cwd="$tmp_cwd"
  fi
  err_file="$(mktemp "$FIXTURE_ROOT/err.XXXXXX")" || die "mktemp failed under $FIXTURE_ROOT"
  out_file="$(mktemp "$FIXTURE_ROOT/out.XXXXXX")" || die "mktemp failed under $FIXTURE_ROOT"
  _status=0
  printf '%s' "$payload" | ( cd "$cwd" && exec "$HOOKS_DIR/$hook" ) >"$out_file" 2>"$err_file" || _status=$?
  _stderr="$(cat "$err_file")"
  _stdout="$(cat "$out_file")"
  rm -f "$err_file" "$out_file"
  [ -n "$tmp_cwd" ] && rm -rf "$tmp_cwd"
}

# assert_allow <label> <hook> <payload> [cwd]
assert_allow() {
  local label="$1" hook="$2" payload="$3" cwd="${4:-}"
  run_hook "$hook" "$payload" "$cwd"
  if [ "$_status" -eq 0 ]; then
    _pass
  else
    _fail "$label: expected allow (exit 0), got exit $_status${_stderr:+ — stderr: $_stderr}"
  fi
}

# assert_block <label> <hook> <payload> <expect_substr> [cwd]
# Pass "" for expect_substr to assert a block without checking the message.
assert_block() {
  local label="$1" hook="$2" payload="$3" substr="$4" cwd="${5:-}"
  run_hook "$hook" "$payload" "$cwd"
  if [ "$_status" -ne 2 ]; then
    _fail "$label: expected block (exit 2), got exit $_status${_stderr:+ — stderr: $_stderr}"
    return
  fi
  if [ -n "$substr" ] && [[ "$_stderr" != *"$substr"* ]]; then
    _fail "$label: blocked as expected but stderr missing '$substr' (got: $_stderr)"
    return
  fi
  _pass
}

# --- Payload builders (jq -n handles all escaping) ----------------------------

# payload_bash <command> [agent_type]
payload_bash() {
  if [ -n "${2:-}" ]; then
    jq -nc --arg c "$1" --arg a "$2" '{tool_input: {command: $c}, agent_type: $a}'
  else
    jq -nc --arg c "$1" '{tool_input: {command: $c}}'
  fi
}

# payload_file <agent_type> <file_path>   (for gitdir-guard and format)
payload_file() {
  jq -nc --arg a "$1" --arg f "$2" '{agent_type: $a, tool_input: {file_path: $f}}'
}

# payload_read <file_path> [limit]        (for read-guard)
payload_read() {
  if [ -n "${2:-}" ]; then
    jq -nc --arg f "$1" --argjson l "$2" '{tool_input: {file_path: $f, limit: $l}}'
  else
    jq -nc --arg f "$1" '{tool_input: {file_path: $f}}'
  fi
}

# --- Fixtures (cleaned up by the EXIT trap) -----------------------------------

# make_git_branch <branch> -> echoes a throwaway git repo checked out on <branch>
make_git_branch() {
  local branch="$1" dir
  dir="$(new_tmpdir)"
  git init -q -b "$branch" "$dir" 2>/dev/null \
    || { git init -q "$dir"; git -C "$dir" symbolic-ref HEAD "refs/heads/$branch"; }
  printf '%s' "$dir"
}

# make_crew_md <frontmatter> [body] -> echoes a throwaway dir containing a
# .claude/crew.md with <frontmatter> between the `---` delimiters. The body is
# prose the readers must ignore, so it is separate rather than something a caller
# has to remember to place below the closing delimiter.
make_crew_md() {
  local dir
  dir="$(new_tmpdir)"
  mkdir -p "$dir/.claude"
  printf -- '---\n%s\n---\n\n%s\n' "$1" "${2:-Notes.}" > "$dir/.claude/crew.md"
  printf '%s' "$dir"
}

# make_tree <relpath>:<content> ... -> echoes a throwaway dir containing each
# file, parent directories created. Splits each argument on its first colon, so
# the content may contain colons (JSON) but the path may not. For fixtures whose
# shape is what the hook reads: a project's configs, plan-guard's agent files.
make_tree() {
  local dir spec rel
  dir="$(new_tmpdir)"
  for spec in "$@"; do
    # Reject a malformed spec loudly: a fixture helper that quietly builds the
    # wrong tree makes every assertion downstream of it meaningless.
    case "$spec" in
      *:*) ;;
      *) die "make_tree: expected <relpath>:<content>, got '$spec'" ;;
    esac
    rel="${spec%%:*}"
    [ -n "$rel" ] || die "make_tree: empty path in '$spec'"
    mkdir -p "$dir/$(dirname "$rel")"
    printf '%s\n' "${spec#*:}" > "$dir/$rel"
  done
  printf '%s' "$dir"
}

trap 'rm -rf "$FIXTURE_ROOT"' EXIT

# finish — call at the end of each test file. Prints a one-line summary (named
# after the calling *.test.sh) and exits non-zero if any assertion failed.
finish() {
  local name
  name="$(basename "${BASH_SOURCE[1]}" .test.sh)"
  if [ "$tests_failed" -ne 0 ]; then
    printf '%s: %d/%d assertions FAILED\n' "$name" "$tests_failed" "$tests_run" >&2
    exit 1
  fi
  printf '%s: %d assertions passed\n' "$name" "$tests_run"
  exit 0
}
