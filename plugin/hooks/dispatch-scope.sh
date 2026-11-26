#!/usr/bin/env bash
# Dispatch scope: `lead` may launch any agent, but one outside the crew and the
# Bash-free built-ins gets a warning in lead's context, since bash-safety keeps no
# git from it (AGENTS.md, "crew:lead"). Never refuses; fails open.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugin/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
. "$_lib" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

guard_read_payload
# Fast path, no subprocess: only a lead session is in scope.
case "$guard_payload" in
  *'"crew:lead"'*) ;;
  *) exit 0 ;;
esac

# Both trusted fields are harness-controlled. tool_name is checked too, so a
# matcher read as a regex (TaskStop, TaskOutput) never gets the warning.
guard_jq2 '.tool_input.subagent_type // ""' '(.tool_name // "") + " " + (.agent_type // "")' || exit 0
# shellcheck disable=SC2154  # set by guard_jq2 in the library sourced above
case "$guard_trusted" in
  'Agent crew:lead'|'Task crew:lead') ;;
  *) exit 0 ;;
esac
# An Agent call without a subagent_type launches general-purpose, so "" is warned.
# shellcheck disable=SC2154
case "$guard_untrusted" in
  crew:?*|Explore|Plan|claude-code-guide|web-fetch|statusline-setup) exit 0 ;;
esac

a="${guard_untrusted:-general-purpose}"
msg="crew dispatch-scope: '$a' is not a crew agent, and the crew guards do not stop it running git. Prefer the crew worker that owns this step (crew:generalist for general work). If you keep '$a': tell it to run no git, then check that HEAD has not moved and that its diff stays inside the step before you commit."
# No permissionDecision: the call keeps the normal permission flow.
jq -nc --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}' || exit 0
exit 0
