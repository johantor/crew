#!/usr/bin/env bash
# The eval sessions' PermissionRequest hook: appends one line per request to
# $CREW_EVAL_PERMISSION_LOG and prints no decision, so the request is still refused, as in any
# headless run. A worker's refusal reaches no other record (evals/README.md, Run).
set -uo pipefail

[ -n "${CREW_EVAL_PERMISSION_LOG:-}" ] || exit 0
jq -c '{agent: (.agent_type // "lead"), tool: .tool_name,
  input: ((.tool_input.command // (.tool_input | tostring)) | .[0:300])}' \
  >>"$CREW_EVAL_PERMISSION_LOG" 2>/dev/null
exit 0
