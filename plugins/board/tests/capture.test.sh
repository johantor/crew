#!/usr/bin/env bash
# Behavioral tests for hooks/capture.sh (the board's event capture; never blocks),
# then the Node suite for the reducer, history backfill and server.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
HOOK="capture.sh"

# The board needs Node; a missing one fails the suite rather than skipping it.
command -v node >/dev/null 2>&1 || die "node is required to run the board tests"

CLAUDE_BOARD_DIR="$(new_tmpdir)/board"
export CLAUDE_BOARD_DIR
log="$CLAUDE_BOARD_DIR/events.jsonl"

# last_record -> the newest line of the log, or nothing.
last_record() { [ -f "$log" ] && tail -n 1 "$log"; }
line_count() { if [ -f "$log" ]; then wc -l < "$log" | tr -d ' '; else echo 0; fi; }

# assert_record <label> <jq filter that must be true for the newest record>
assert_record() {
  local rec
  rec="$(last_record)"
  if [ -n "$rec" ] && jq -e "$2" >/dev/null 2>&1 <<<"$rec"; then
    _pass
  else
    _fail "$1: newest record fails '$2' (got: ${rec:-nothing})"
  fi
}

# assert_no_new <label> <count before>
assert_no_new() {
  if [ "$(line_count)" -eq "$2" ]; then _pass; else _fail "$1: expected no new record, got: $(last_record)"; fi
}

repo="$(make_git_branch feature/cart)"
mkdir -p "$repo/src"

# A tool call becomes one short activity line, relative to the session's cwd.
assert_allow "PreToolUse is captured" "$HOOK" \
  "$(jq -nc --arg cwd "$repo" '{session_id:"s1", hook_event_name:"PreToolUse", cwd:$cwd, permission_mode:"default",
      tool_name:"Edit", tool_input:{file_path:($cwd + "/src/cart.ts"), old_string:"a", new_string:"b"}}')"
assert_record "Edit summarized" '.e == "PreToolUse" and .sid == "s1" and .tool == "Edit src/cart.ts" and (.ts | type) == "number"'

# Repo and branch come from the nearest .git, read as files.
assert_allow "SessionStart is captured" "$HOOK" \
  "$(jq -nc --arg cwd "$repo/src" '{session_id:"s1", hook_event_name:"SessionStart", cwd:$cwd, source:"startup"}')"
assert_record "repo and branch" ".repo == \"$(basename "$repo")\" and .branch == \"feature/cart\" and .source == \"startup\""

# A subagent's event keeps the parent's session id and names the agent.
assert_allow "SubagentStart is captured" "$HOOK" \
  '{"session_id":"s1","hook_event_name":"SubagentStart","agent_id":"a1","agent_type":"crew:backend"}'
assert_record "subagent fields" '.aid == "a1" and .agent == "crew:backend"'

# A long prompt is clipped, so one line stays far below the 4 KiB append limit.
long="$(printf 'x%.0s' $(seq 1 5000))"
assert_allow "long prompt" "$HOOK" \
  "$(jq -nc --arg p "$long" '{session_id:"s1", hook_event_name:"UserPromptSubmit", prompt:$p}')"
assert_record "prompt clipped" '(.prompt | length) <= 200'

# Events the board does not track never reach the log.
# A permission notification repeats PermissionRequest, so it is dropped too.
before="$(line_count)"
assert_allow "permission notification" "$HOOK" \
  '{"session_id":"s1","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission"}'
assert_no_new "permission notification skipped" "$before"
assert_allow "untracked event" "$HOOK" '{"session_id":"s1","hook_event_name":"PreCompact"}'
assert_no_new "PreCompact skipped" "$before"

# A question, and the idle prompt that ends a turn without a Stop, do reach it.
assert_allow "question notification" "$HOOK" \
  '{"session_id":"s1","hook_event_name":"Notification","notification_type":"elicitation_dialog","message":"Which env?"}'
assert_record "question captured" '.ntype == "elicitation_dialog" and .msg == "Which env?"'
assert_allow "idle notification" "$HOOK" \
  '{"session_id":"s1","hook_event_name":"Notification","notification_type":"idle_prompt","message":"waiting"}'
assert_record "idle captured" '.ntype == "idle_prompt"'

# Never fails the session: bad input, no session id, an unwritable log, no Node.
before="$(line_count)"
assert_allow "invalid JSON" "$HOOK" 'not json'
assert_allow "no session id" "$HOOK" '{"hook_event_name":"Stop"}'
assert_no_new "nothing logged for bad input" "$before"

blocker="$(new_tmpdir)/file"
: > "$blocker"
CLAUDE_BOARD_DIR="$blocker/board" assert_allow "unwritable board dir" "$HOOK" \
  '{"session_id":"s2","hook_event_name":"Stop","last_assistant_message":"done"}'

# Run outside run_hook: the harness itself needs the PATH this case takes away.
nonode="$(new_tmpdir)"
ln -s "$(command -v dirname)" "$nonode/dirname"
status=0
printf '%s' '{"session_id":"s3","hook_event_name":"Stop"}' | PATH="$nonode" "$BASH" "$HOOKS_DIR/$HOOK" || status=$?
if [ "$status" -eq 0 ]; then _pass; else _fail "no node on PATH: expected exit 0, got $status"; fi

# The log is private to the user: transcripts hold client code.
mode="$(stat -c '%a' "$log" 2>/dev/null || stat -f '%Lp' "$log")"
if [ "$mode" = "600" ]; then _pass; else _fail "events.jsonl mode is $mode, expected 600"; fi

# Order the reducer relies on: PermissionRequest lands before its tool runs, and
# SessionEnd before the process exits, so both run in the foreground; the rest are async.
wiring="$(dirname "${BASH_SOURCE[0]}")/../hooks/hooks.json"
for event in PermissionRequest SessionEnd; do
  if jq -e --arg e "$event" '.hooks[$e][0].hooks[0] | (.async != true) and (.timeout | type == "number")' "$wiring" >/dev/null; then
    _pass
  else
    _fail "$event must run in the foreground with a timeout"
  fi
done
if jq -e '[.hooks | to_entries[] | select(.key != "PermissionRequest" and .key != "SessionEnd") | .value[0].hooks[0].async] | all' "$wiring" >/dev/null; then
  _pass
else
  _fail "every other board hook must be async"
fi

# The reducer, history backfill and server have their own Node suite.
if node --test "$(dirname "${BASH_SOURCE[0]}")"/*.test.mjs >"$FIXTURE_ROOT/node-test.log" 2>&1; then
  _pass
else
  cat "$FIXTURE_ROOT/node-test.log" >&2
  _fail "node --test suite failed"
fi

finish
