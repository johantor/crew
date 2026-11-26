#!/usr/bin/env bash
# dispatch-scope.sh: lead launches any agent; one outside the crew and the Bash-free
# built-ins gets a warning on stdout. It never refuses, and any other caller, and any
# payload it can't read, passes silently.
# shellcheck source=tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# payload_dispatch <subagent_type> <agent_type> [tool_name] — a PreToolUse
# payload, Agent by default. Pass "" to omit either of the first two fields.
payload_dispatch() {
  jq -nc --arg s "$1" --arg a "$2" --arg t "${3:-Agent}" \
    '{hook_event_name: "PreToolUse", tool_name: $t,
      tool_input: ({description: "Implement step 3", prompt: "…"}
                   + (if $s != "" then {subagent_type: $s} else {} end))}
     + (if $a != "" then {agent_type: $a} else {} end)'
}

hook=dispatch-scope.sh

# assert_silent <label> <payload> — allowed with nothing on stdout.
assert_silent() {
  run_hook "$hook" "$2"
  if [ "$_status" -ne 0 ]; then
    _fail "$1: expected exit 0, got $_status${_stderr:+ — stderr: $_stderr}"
  elif [ -n "$_stdout" ]; then
    _fail "$1: expected no output, got: $_stdout"
  else
    _pass
  fi
}

# assert_warns <label> <payload> <type> — allowed, no decision, and the
# PreToolUse context names the type and points at the crew.
assert_warns() {
  run_hook "$hook" "$2"
  if [ "$_status" -ne 0 ]; then
    _fail "$1: expected exit 0, got $_status${_stderr:+ — stderr: $_stderr}"
  elif ! jq -e --arg t "'$3'" '.hookSpecificOutput.hookEventName == "PreToolUse"
        and (.hookSpecificOutput | has("permissionDecision") | not)
        and (.hookSpecificOutput.additionalContext | contains($t) and contains("crew:generalist"))' \
        >/dev/null 2>&1 <<<"$_stdout"; then
    _fail "$1: expected a PreToolUse warning naming '$3' (got: $_stdout)"
  else
    _pass
  fi
}

# --- lead: crew workers and the Bash-free built-ins pass silently -----------------
for t in crew:backend crew:incident-triage crew:web-review Explore Plan claude-code-guide web-fetch statusline-setup; do
  assert_silent "lead may dispatch $t" "$(payload_dispatch "$t" crew:lead)"
done

# --- lead: anything else launches, with a warning that names it -------------------
for t in general-purpose claude backend my-project-agent explore; do
  assert_warns "lead dispatching '$t' is warned" "$(payload_dispatch "$t" crew:lead)" "$t"
done
assert_warns "no subagent_type launches general-purpose -> warned" \
  "$(payload_dispatch "" crew:lead)" general-purpose
assert_warns "the legacy Task tool name is a dispatch too" \
  "$(payload_dispatch general-purpose crew:lead Task)" general-purpose

# --- Non-dispatch tools pass, should a matcher read as a regex reach them ---------
for t in TaskStop TaskOutput TaskCreate; do
  assert_silent "lead's $t is not a dispatch" "$(payload_dispatch "" crew:lead "$t")"
done

# --- Other callers are not this hook's business -----------------------------------
assert_silent "the user's own session may dispatch general-purpose" "$(payload_dispatch general-purpose "")"
assert_silent "another crew agent is out of scope" "$(payload_dispatch general-purpose crew:backend)"
assert_silent "a project's own 'lead' is not crew:lead" "$(payload_dispatch general-purpose lead)"
# The fast path matches text; only the harness field decides.
assert_silent "crew:lead in the prompt is not the caller" \
  "$(jq -nc '{tool_name: "Agent", tool_input: {subagent_type: "general-purpose", prompt: "act as \"crew:lead\""}}')"
assert_silent "unparseable payload -> fail open" 'not json "crew:lead"'

finish
