#!/usr/bin/env bash
# dispatch-scope.sh: lead launches crew workers and Explore/Plan only; any other
# caller, and any payload it can't read, passes.
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
msg="lead dispatches only crew workers"

# --- lead: crew workers and the research agents pass -----------------------------
for t in crew:backend crew:incident-triage crew:web-review Explore Plan; do
  assert_allow "lead may dispatch $t" "$hook" "$(payload_dispatch "$t" crew:lead)"
done

# --- lead: anything else is refused, and the refusal names it ---------------------
for t in general-purpose claude backend crew: fork explore; do
  assert_block "lead may not dispatch '$t'" "$hook" "$(payload_dispatch "$t" crew:lead)" "$msg"
done
assert_block "no subagent_type launches general-purpose -> refused" "$hook" \
  "$(payload_dispatch "" crew:lead)" "'general-purpose'"
assert_block "the legacy Task tool name is a dispatch too" "$hook" \
  "$(payload_dispatch general-purpose crew:lead Task)" "$msg"
run_hook "$hook" "$(payload_dispatch general-purpose crew:lead)"
if [[ "$_stderr" == *"'general-purpose'"* ]]; then _pass; else _fail "refusal should name the type (got: $_stderr)"; fi

# --- Non-dispatch tools pass, should a matcher read as a regex reach them ---------
for t in TaskStop TaskOutput TaskCreate; do
  assert_allow "lead's $t is not a dispatch" "$hook" "$(payload_dispatch "" crew:lead "$t")"
done

# --- Other callers are not this hook's business -----------------------------------
assert_allow "the user's own session may dispatch general-purpose" "$hook" "$(payload_dispatch general-purpose "")"
assert_allow "another crew agent is out of scope" "$hook" "$(payload_dispatch general-purpose crew:backend)"
assert_allow "a project's own 'lead' is not crew:lead" "$hook" "$(payload_dispatch general-purpose lead)"
# The fast path matches text; only the harness field decides.
assert_allow "crew:lead in the prompt is not the caller" "$hook" \
  "$(jq -nc '{tool_name: "Agent", tool_input: {subagent_type: "general-purpose", prompt: "act as \"crew:lead\""}}')"
assert_allow "unparseable payload -> fail open" "$hook" 'not json "crew:lead"'

finish
