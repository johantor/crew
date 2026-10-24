#!/usr/bin/env bash
# PreToolUse(Edit|Write): no crew agent writes inside .git/. Repository state
# changes go through git, which only lead runs; lead keeps .git/info/exclude,
# which /crew:init writes. The crew has no write lanes (AGENTS.md, "Why the crew
# has no write lanes"), so this is the only Edit/Write refusal.

# Fail open on a broken install, like the other Edit/Write hooks: a floor, not a sandbox.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugin/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
. "$_lib" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

guard_read_payload
guard_jq2 '(.tool_input.file_path // .tool_input.path) // ""' '.agent_type // ""' || exit 0
guard_agent_type
# Crew agents only: the operator's session and a project's own agents are not the crew's to bound.
case "$agent_type" in ''|ext:*) exit 0 ;; esac
# The globs below use `/`; Windows hands over `D:\x\y`.
guard_posix_path "$guard_untrusted"
path="$guard_path"
[ -z "$path" ] && exit 0

# Case-blind: macOS and Windows file systems are. A `..` segment cannot dodge
# the match, since any path naming .git/ is refused.
shopt -s nocasematch
[[ "/$path/" == */.git/* ]] || exit 0
if [ "$agent_type" = lead ] && [[ "/$path" == */.git/info/exclude ]]; then
  exit 0
fi
echo "Blocked: $path is inside .git/, which no Edit/Write may change. Repository state changes go through git, which only lead runs." >&2
exit 2
