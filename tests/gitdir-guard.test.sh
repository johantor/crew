#!/usr/bin/env bash
# Behavioral tests for hooks/gitdir-guard.sh.
# shellcheck source=tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
HOOK="gitdir-guard.sh"

# Fail open: a payload the guard cannot parse passes.
assert_allow "an unparseable payload passes" "$HOOK" 'not json'

# --- Every crew agent is refused .git/ -------------------------------------------
for _a in backend frontend unit-tests e2e generalist copywriter designer lead; do
  assert_block "$_a blocked from .git/config" "$HOOK" "$(payload_file "crew:$_a" .git/config)" "inside .git/"
done
assert_block "the block ignores case"          "$HOOK" "$(payload_file crew:e2e .GIT/config)" "inside .git/"
assert_block "a '..' path cannot dodge it"     "$HOOK" "$(payload_file crew:e2e src/../.git/hooks/pre-commit)" "inside .git/"
assert_block "a worktree's .git file too"      "$HOOK" "$(payload_file crew:backend /repo/wt/.git)" "inside .git/"
CREW_OSTYPE=msys assert_block "a Windows path too" \
  "$HOOK" "$(payload_file crew:backend 'D:\repo\.git\config')" "inside .git/"

# --- lead keeps the one file /crew:init writes there ------------------------------
assert_allow "lead allowed the git exclude file"  "$HOOK" "$(payload_file crew:lead /repo/.git/info/exclude)"
assert_block "lead's exemption is the file only" \
  "$HOOK" "$(payload_file crew:lead .git/info/exclude/../../config)" "inside .git/"
assert_block "a worker gets no exclude exemption" \
  "$HOOK" "$(payload_file crew:backend .git/info/exclude)" "inside .git/"

# --- Everything else passes: there are no write lanes ---------------------------
assert_allow "backend keeps .gitignore"        "$HOOK" "$(payload_file crew:backend .gitignore)"
assert_allow "backend keeps .github/"          "$HOOK" "$(payload_file crew:backend .github/workflows/ci.yml)"
assert_allow "backend writes a frontend file"  "$HOOK" "$(payload_file crew:backend src/web/App.tsx)"
if [ -n "$_stdout" ]; then _fail "a cross-role write gets no note (got: $_stdout)"; else _pass; fi
assert_allow "lead writes a source file"       "$HOOK" "$(payload_file crew:lead src/app.ts)"
assert_allow "the main session is not guarded" "$HOOK" "$(jq -nc '{tool_input:{file_path:".git/config"}}')"
assert_allow "a project's own agent is not guarded" "$HOOK" "$(payload_file backend .git/config)"

finish
