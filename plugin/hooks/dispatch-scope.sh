#!/usr/bin/env bash
# Dispatch scope: `lead` launches only crew workers and the built-in
# `Explore`/`Plan` research agents.
#
# `lead` inherits every tool of the session, so it can reach the user's own MCP
# servers; that costs the frontmatter `Agent(...)` allowlist. Any other agent
# type is not on bash-safety's no-git roster, so it would run git and edit
# files outside lead's plan. Other sessions and agents are not this hook's
# business. Fails open, like plan-guard: no jq or an unreadable payload allows.
# See AGENTS.md, "crew:lead".
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

# An Agent call without a subagent_type launches general-purpose, so "" is refused.
guard_jq2 '.tool_input.subagent_type // ""' '.agent_type // ""' || exit 0
# shellcheck disable=SC2154  # set by guard_jq2 in the library sourced above
[ "$guard_trusted" = "crew:lead" ] || exit 0
# shellcheck disable=SC2154
case "$guard_untrusted" in
  crew:?*|Explore|Plan) exit 0 ;;
esac

echo "Blocked: lead dispatches only crew workers (crew:<worker>) and the built-in Explore/Plan agents, not '${guard_untrusted:-general-purpose}'. Delegate the step to the crew worker that owns it, or stop and report the blocker to the user." >&2
exit 2
