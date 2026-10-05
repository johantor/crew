#!/usr/bin/env bash
# Behavior tests for dispatch-denied.sh — the PermissionDenied advisor that reacts
# to auto mode refusing a crew worker dispatch. Two shapes set it apart from the
# guards: its decision is JSON on _stdout, and it is stateful, counting attempts
# per session+worker through the CREW_DISPATCH_DENIED_DIR override.
#
# The cases below pin both ways it degrades — silent when it can't tell what it is
# looking at, reporting-without-retrying when it can't count attempts — and the
# load-bearing asymmetry: only a counted first attempt may ask for a retry, and a
# can't-count message must not claim to be a repeat.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"

# payload_denied <subagent_type> <transcript_path> — minimal PermissionDenied
# payload. Pass "" to omit either field.
payload_denied() {
  jq -nc --arg s "$1" --arg t "$2" \
    '{hook_event_name: "PermissionDenied", tool_name: "Agent", tool_use_id: "tu_1",
      permission_mode: "auto",
      tool_input: ({description: "Cap hero text width", prompt: "…"}
                   + (if $s != "" then {subagent_type: $s} else {} end))}
     + (if $t != "" then {transcript_path: $t} else {} end)'
}

# assert_silent <label> <payload> — fail open means exit 0 *and* say nothing: a
# regression that emits JSON for a non-crew dispatch must fail here.
assert_silent() {
  run_hook dispatch-denied.sh "$2"
  if [ "$_status" -eq 0 ] && [ -z "$_stdout" ]; then
    _pass
  else
    _fail "$1: expected exit 0 with no stdout, got exit $_status${_stdout:+ — stdout: $_stdout}"
  fi
}

# assert_retry <label> <payload> — asks the model to retry, once.
assert_retry() {
  run_hook dispatch-denied.sh "$2"
  if [ "$_status" -ne 0 ]; then
    _fail "$1: expected exit 0, got exit $_status${_stderr:+ — stderr: $_stderr}"
  elif ! jq -e '.hookSpecificOutput.hookEventName == "PermissionDenied"
                and .hookSpecificOutput.retry == true
                and (.systemMessage | type == "string")' >/dev/null 2>&1 <<<"$_stdout"; then
    _fail "$1: expected retry:true JSON on stdout, got: ${_stdout:-<empty>}"
  else
    _pass
  fi
}

# assert_no_retry <label> <payload> <expect_substr> — reports, never retries.
assert_no_retry() {
  run_hook dispatch-denied.sh "$2"
  if [ "$_status" -ne 0 ]; then
    _fail "$1: expected exit 0, got exit $_status${_stderr:+ — stderr: $_stderr}"
  elif ! jq -e '(.hookSpecificOutput.retry // false) == false
                and (.systemMessage | type == "string")' >/dev/null 2>&1 <<<"$_stdout"; then
    _fail "$1: expected a systemMessage with no retry, got: ${_stdout:-<empty>}"
  elif ! jq -e --arg s "$3" '.systemMessage | contains($s)' >/dev/null 2>&1 <<<"$_stdout"; then
    _fail "$1: message missing '$3' (got: $(jq -r '.systemMessage // ""' <<<"$_stdout"))"
  else
    _pass
  fi
}

CREW_DISPATCH_DENIED_DIR="$(new_tmpdir)"
export CREW_DISPATCH_DENIED_DIR

# --- Only crew dispatches are this hook's business ------------------------------
assert_silent "a subagent not on crew's roster is left alone" "$(payload_denied general-purpose /tmp/t/a.jsonl)"
assert_silent "an unnamespaced agent is left alone" "$(payload_denied generalist /tmp/t/a.jsonl)"
assert_silent "a bare 'crew:' prefix with no worker is not a dispatch" "$(payload_denied crew: /tmp/t/a.jsonl)"
assert_silent "no subagent_type (not a dispatch) -> silent" "$(payload_denied "" /tmp/t/a.jsonl)"
assert_silent "unparseable payload -> fail open" 'not json'
# Nothing above may leave state behind: a stray counter would make a later first
# denial look like a repeat and swallow its retry.
found=""
for f in "$CREW_DISPATCH_DENIED_DIR"/crew-dispatch-denied.*; do [ -e "$f" ] && found="$f"; done
if [ -n "$found" ]; then _fail "state written for a non-crew dispatch: $found"; else _pass; fi

# --- Retry once, then report ----------------------------------------------------
assert_retry "first denial retries once" "$(payload_denied crew:generalist /tmp/t/run.jsonl)"
assert_no_retry "second denial stops and names the working fix" \
  "$(payload_denied crew:generalist /tmp/t/run.jsonl)" "acceptEdits"
assert_no_retry "third denial still refuses to retry" \
  "$(payload_denied crew:generalist /tmp/t/run.jsonl)" "autoMode.environment"
# The advice must not send the user down the path that cannot work.
run_hook dispatch-denied.sh "$(payload_denied crew:generalist /tmp/t/run.jsonl)"
if jq -e '.systemMessage | contains("permissions.allow cannot cover this")' >/dev/null 2>&1 <<<"$_stdout"; then
  _pass
else
  _fail "repeat-denial message should say permissions.allow cannot cover this"
fi

# --- Counters are per worker and per session ------------------------------------
assert_retry "a different worker in the same session gets its own first retry" \
  "$(payload_denied crew:frontend /tmp/t/run.jsonl)"
assert_retry "the same worker in a different session starts fresh" \
  "$(payload_denied crew:generalist /tmp/t/other.jsonl)"

# --- Corrupt counter state is treated as fresh, not a crash ---------------------
corrupt="/tmp/t/corrupt.jsonl"
run_hook dispatch-denied.sh "$(payload_denied crew:backend "$corrupt")"
state_file=""
for f in "$CREW_DISPATCH_DENIED_DIR"/crew-dispatch-denied.*.backend; do [ -e "$f" ] && state_file="$f"; done
if [ -n "$state_file" ]; then _pass; else _fail "expected a backend state file after one denial"; fi
printf 'garbage\n' > "$state_file"
assert_retry "corrupt state restarts at the first attempt" "$(payload_denied crew:backend "$corrupt")"

# --- Can't count -> never retry --------------------------------------------------
assert_no_retry "no session key -> report without retrying" \
  "$(payload_denied crew:generalist "")" "acceptEdits"
# ...and it must not pass itself off as a repeat: nothing was retried.
run_hook dispatch-denied.sh "$(payload_denied crew:generalist "")"
if jq -e '.systemMessage | contains("again") | not' >/dev/null 2>&1 <<<"$_stdout"; then
  _pass
else
  _fail "can't-count message must not claim the dispatch was denied 'again'"
fi

ro_dir="$(new_tmpdir)"
chmod a-w "$ro_dir"
if [ -w "$ro_dir" ]; then
  # Running as root (some CI containers): the dir stays writable, so this path
  # can't be exercised here — skip rather than assert what the environment
  # can't set up.
  chmod u+w "$ro_dir"
else
  _status=0
  _stdout="$(printf '%s' "$(payload_denied crew:generalist /tmp/t/ro.jsonl)" \
    | ( cd "$(new_tmpdir)" && CREW_DISPATCH_DENIED_DIR="$ro_dir" exec "$HOOKS_DIR/dispatch-denied.sh" ) 2>/dev/null)" || _status=$?
  if [ "$_status" -eq 0 ] \
     && jq -e '(.hookSpecificOutput.retry // false) == false' >/dev/null 2>&1 <<<"$_stdout"; then
    _pass
  else
    _fail "unwritable state dir must report without retrying, got exit $_status — ${_stdout:-<empty>}"
  fi
  chmod u+w "$ro_dir"
fi

finish
