#!/usr/bin/env bash
# Behavior tests for format.sh — the PostToolUse formatter. It differs from the
# guards in two ways that shape these tests: it never blocks (every path exits 0,
# so the assertions are on what it *reports* on stderr), and it is the one hook
# that mutates the user's files, by running the commands the `formatMatrix` slot
# in .claude/crew.md names. Those commands are faked as scripts, so the suite
# keeps its no-build/no-network/no-LLM contract while still exercising the real
# match -> run -> report path.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="format.sh"

# Short bound for the hang case below; the fake tools elsewhere are instant.
CREW_FORMAT_TIMEOUT=2
export CREW_FORMAT_TIMEOUT

# assert_reports <label> <payload> <cwd> <substr> — exit 0 and say <substr>.
assert_reports() {
  run_hook "$HOOK" "$2" "$3"
  if [ "$_status" -ne 0 ]; then
    _fail "$1: expected exit 0, got exit $_status${_stderr:+ — stderr: $_stderr}"
  elif [[ "$_stderr" != *"$4"* ]]; then
    _fail "$1: stderr missing '$4' (got: ${_stderr:-<empty>})"
  else
    _pass
  fi
}

# assert_silent <label> <payload> [cwd] — a no-op path must exit 0 saying nothing.
assert_silent() {
  run_hook "$HOOK" "$2" "${3:-}"
  if [ "$_status" -eq 0 ] && [ -z "$_stderr" ]; then
    _pass
  else
    _fail "$1: expected exit 0 with no stderr, got exit $_status${_stderr:+ — stderr: $_stderr}"
  fi
}

# matrix_project <rows> -> a throwaway project whose crew.md carries <rows> as
# the formatMatrix block. Rows are given unindented; the block indents them.
matrix_project() {
  local dir indented=""
  while IFS= read -r line; do indented+="  $line"$'\n'; done <<<"$1"
  dir="$(make_crew_md "backendStack: node"$'\n'"formatMatrix: |"$'\n'"${indented%$'\n'}" \
    'Body text that also says formatMatrix: | and must not be read.')"
  printf '%s' "$dir"
}
# fake_tool <dir> <relpath> <body> — an executable script at <dir>/<relpath>.
fake_tool() {
  mkdir -p "$1/$(dirname "$2")"
  printf '#!/bin/sh\n%s\n' "$3" > "$1/$2"
  chmod +x "$1/$2"
}

# --- Gating: who and what the hook is a no-op for ------------------------------
web="$(matrix_project '. ts,tsx node_modules/.bin/prettier --write {file}')"
fake_tool "$web" node_modules/.bin/prettier 'exit 0'
assert_silent "a non-formatter agent is a no-op" "$(payload_file e2e src/a.ts)" "$web"
assert_silent "the main session (no agent_type) is a no-op" \
  "$(jq -nc '{tool_input: {file_path: "src/a.ts"}}')" "$web"
assert_silent "no file_path is a no-op" "$(jq -nc '{agent_type: "backend"}')" "$web"
# unit-tests writes test files, which are source and need the same formatting.
assert_reports "unit-tests's test edits are formatted too" \
  "$(payload_file unit-tests src/a.test.ts)" "$web" "applied prettier"
assert_reports "generalist gets the same routing as backend/frontend" \
  "$(payload_file generalist src/a.ts)" "$web" "applied prettier"
# An installed plugin's worker calls tools as `crew:backend`.
assert_reports "crew:backend is formatted like backend" \
  "$(payload_file crew:backend src/a.ts)" "$web" "applied prettier"
assert_silent "other:backend is not this crew's worker" "$(payload_file other:backend src/a.ts)" "$web"

# --- No matrix: per-edit formatting is off, silently -------------------------
assert_silent "no .claude/crew.md is a no-op" "$(payload_file backend src/a.ts)"
assert_silent "formatMatrix: none is a no-op" \
  "$(payload_file backend src/a.ts)" "$(make_crew_md 'formatMatrix: none')"
assert_silent "formatMatrix: unset is a no-op" \
  "$(payload_file backend src/a.ts)" "$(make_crew_md 'formatMatrix: unset')"
assert_silent "a crew.md without the slot is a no-op" \
  "$(payload_file backend src/a.ts)" "$(make_crew_md 'backendStack: node')"
# The slot name in the body is prose; only the frontmatter block is a matrix.
assert_silent "a matrix quoted in the body is not read" "$(payload_file backend src/a.ts)" \
  "$(make_crew_md 'backendStack: node' $'formatMatrix: |\n  . ts node_modules/.bin/prettier --write {file}')"

# --- Match: directory prefix and extension list -------------------------------
assert_reports "a matching row runs and is reported" \
  "$(payload_file backend src/a.ts)" "$web" "applied prettier"
assert_silent "an extension no row lists is left alone" "$(payload_file backend src/a.cs)" "$web"
assert_silent "an extension is matched whole, not as a prefix" \
  "$(payload_file backend src/a.t)" "$web"
assert_silent "a file with no extension is left alone" "$(payload_file backend Makefile)" "$web"

mono="$(matrix_project 'apps/web/ ts node_modules/.bin/prettier --write {file}
apps/api/ cs dotnet-csharpier format {file}')"
# The fake's body is a script of its own: the single quotes are deliberate.
# shellcheck disable=SC2016
fake_tool "$mono" apps/web/node_modules/.bin/prettier \
  '[ "$(pwd)" = "'"$mono"'/apps/web" ] && [ "$2" = "src/a.ts" ] && exit 0; exit 1'
mkdir -p "$mono/apps/api"
assert_reports "a row runs from its directory with {file} relative to it" \
  "$(payload_file backend apps/web/src/a.ts)" "$mono" "applied prettier"
assert_reports "an absolute path is matched project-relative" \
  "$(payload_file backend "$mono/apps/web/src/a.ts")" "$mono" "applied prettier"
assert_silent "a file outside every row's directory is left alone" \
  "$(payload_file backend src/a.ts)" "$mono"
assert_silent "a directory prefix matches whole segments only" \
  "$(payload_file backend apps/webapp/a.ts)" "$mono"
# The row's tool is gone: the matrix is stale, and the message names the fix.
assert_reports "a tool the row names but cannot be found nudges /crew:init" \
  "$(payload_file backend apps/api/Svc.cs)" "$mono" "dotnet-csharpier not found for formatMatrix row 'apps/api cs'; run /crew:init"
# stderr at exit 0 never reaches the model, so the nudge is also returned as
# PostToolUse additionalContext; an applied run returns nothing on stdout.
if [ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$_stdout" 2>/dev/null)" = \
     "format hook: dotnet-csharpier not found for formatMatrix row 'apps/api cs'; run /crew:init" ]; then _pass
else _fail "the nudge must be returned as additionalContext (got stdout: ${_stdout:-<empty>})"; fi
run_hook "$HOOK" "$(payload_file backend apps/web/src/a.ts)" "$mono"
if [ -z "$_stdout" ]; then _pass; else _fail "an applied run returns no additionalContext (got: $_stdout)"; fi
# A wrapper that cannot find its subcommand exits with its own status, not 127,
# so it is a plain failure here; the lint gate reports the stale matrix instead.
wrapper="$(matrix_project '. cs dotnet csharpier format {file}')"
fake_tool "$wrapper" bin/dotnet 'echo "Could not execute because the specified command or file was not found." >&2; exit 1'
PATH="$wrapper/bin:$PATH" run_hook "$HOOK" "$(payload_file backend Svc.cs)" "$wrapper"
if [[ "$_stderr" == *"dotnet failed (exit 1) on Svc.cs"* && "$_stderr" != *"/crew:init"* ]]; then _pass
else _fail "a wrapper's missing subcommand is a failure, not a stale-matrix nudge (got: ${_stderr:-<empty>})"; fi
# A directory with a space is single-quoted in the row.
spaced="$(matrix_project "'my service/' java bin/google-java-format --replace {file}")"
# shellcheck disable=SC2016
fake_tool "$spaced" 'my service/bin/google-java-format' '[ "$2" = "src/main/java/Svc.java" ] && exit 0; exit 1'
assert_reports "a quoted directory with a space matches and runs from it" \
  "$(payload_file backend 'my service/src/main/java/Svc.java')" "$spaced" "applied google-java-format"
missing_dir="$(matrix_project 'gone/ ts node_modules/.bin/prettier --write {file}')"
assert_reports "a row whose directory is missing nudges /crew:init" \
  "$(payload_file backend gone/a.ts)" "$missing_dir" "row directory 'gone' is missing; run /crew:init"

# --- Several rows, in order, each reported; comments and blanks skipped --------
multi="$(matrix_project '# web lane
. ts,tsx node_modules/.bin/prettier --write {file}

. ts node_modules/.bin/eslint --fix {file}
. css node_modules/.bin/stylelint --fix {file}')"
fake_tool "$multi" node_modules/.bin/prettier 'echo prettier >> order'
fake_tool "$multi" node_modules/.bin/eslint 'echo eslint >> order'
fake_tool "$multi" node_modules/.bin/stylelint 'exit 0'
assert_reports "every matching row runs and is reported" \
  "$(payload_file backend src/a.ts)" "$multi" "applied prettier eslint on src/a.ts"
if [ "$(tr '\n' ' ' < "$multi/order")" = "prettier eslint " ]; then _pass
else _fail "rows must run in matrix order (got: $(tr '\n' ' ' < "$multi/order"))"; fi
run_hook "$HOOK" "$(payload_file backend src/a.css)" "$multi"
if [[ "$_stderr" == *"applied stylelint"* && "$_stderr" != *"prettier"* ]]; then _pass
else _fail "only rows listing the extension run (got: ${_stderr:-<empty>})"; fi
malformed="$(matrix_project '. ts node_modules/.bin/prettier --write {file}
just-two words')"
fake_tool "$malformed" node_modules/.bin/prettier 'exit 0'
assert_reports "a row without a command is reported and the rest still run" \
  "$(payload_file backend src/a.ts)" "$malformed" "row 'just-two words' is not '<dir> <extensions> <command>'; run /crew:init"
assert_reports "a malformed row does not stop the matching one" \
  "$(payload_file backend src/a.ts)" "$malformed" "applied prettier"

# --- {file} quoting: a space or a quote in the path stays one argument --------
quoted="$(matrix_project '. ts node_modules/.bin/prettier --write {file}')"
# shellcheck disable=SC2016
fake_tool "$quoted" node_modules/.bin/prettier '[ "$#" = 2 ] && [ "$2" = "src/a b'"'"'c.ts" ] && exit 0; exit 1'
assert_reports "a path with a space and a quote reaches the tool as one argument" \
  "$(payload_file backend "src/a b'c.ts")" "$quoted" "applied prettier"

# --- Failure and hang reporting -----------------------------------------------
failing="$(matrix_project '. ts node_modules/.bin/prettier --write {file}')"
fake_tool "$failing" node_modules/.bin/prettier 'exit 1'
assert_reports "a formatter that rejects the file is reported as failed" \
  "$(payload_file backend src/a.ts)" "$failing" "prettier failed (exit 1) on src/a.ts"

# Without the bound this call would block for the sleep's full duration on every
# edit. `timeout` is GNU coreutils and absent on stock macOS/BSD, where the hook
# deliberately degrades to running unbounded — so assert this only where the
# binary the hook looks for actually exists.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  hanging="$(matrix_project '. ts node_modules/.bin/prettier --write {file}')"
  fake_tool "$hanging" node_modules/.bin/prettier 'sleep 60'
  started=$SECONDS
  assert_reports "a hung formatter is killed and reported as a timeout" \
    "$(payload_file backend src/a.ts)" "$hanging" "prettier timed out after ${CREW_FORMAT_TIMEOUT}s"
  elapsed=$((SECONDS - started))
  if [ "$elapsed" -lt 30 ]; then
    _pass
  else
    _fail "a hung formatter must not be waited out: the call took ${elapsed}s"
  fi
else
  echo "note: no timeout/gtimeout binary — skipping the bounded-formatter case" >&2
fi

finish
