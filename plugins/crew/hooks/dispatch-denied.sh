#!/usr/bin/env bash
# PermissionDenied(Agent|Task) advisor for crew worker dispatch.
#
# Auto mode drops `Agent` allow rules on entry and judges every dispatch on its
# own, so a dispatch identical to one that passed a minute ago can be refused
# now. Without this hook `lead` sees only "Blocked by classifier" and hands
# the step back with nothing actionable.
#
# First denial of a worker in a session: retry once. Not a bypass — the retried
# call goes through the classifier again, which gets the final say. Later denials
# do NOT retry: they report the fixes that actually exist, so `lead` stops
# thrashing and hands the step back cleanly.
#
# Advisory, not a guard: it never blocks. Silent (exit 0, no output) when it can't
# tell what it is looking at — no jq, unparseable payload, a dispatch that isn't
# a crew worker's. Reports without retrying when it recognises a crew dispatch
# but can't count attempts, since a retry it cannot bound is worse than none. See
# AGENTS.md, "How the crew works".
#
# For this event Claude Code ignores the exit code and stderr — decisions travel
# as JSON on stdout: `hookSpecificOutput.retry` reaches the model,
# `systemMessage` reaches the user.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/crew/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
. "$_lib" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

guard_read_payload
# Fast path, no subprocess. Only an Agent/Task dispatch carries subagent_type;
# a payload without it can only reach the exit below anyway.
case "$guard_payload" in
  *'"subagent_type"'*) ;;
  *) exit 0 ;;
esac

# transcript_path (fallback session_id) keys the counter per session;
# subagent_type is the trusted field that anchors the split (see guard_jq2).
guard_jq2 '(.transcript_path // .session_id // "")' '.tool_input.subagent_type // ""' || exit 0
key_src="$guard_untrusted"
subagent="$guard_trusted"

# Namespace match, deliberately not a hardcoded roster: an installed plugin's
# workers are always `crew:<name>`, so this can't drift as agents are added or
# renamed the way the guards' rosters can (validator §9 exists for those).
case "$subagent" in
  crew:?*) worker="${subagent#crew:}" ;;
  *) exit 0 ;;
esac

# Attempt counter per session+worker. 0 means "couldn't count", which takes the
# no-retry branch below: an unbounded retry is worse than no retry.
attempt=0
# guard_state_path names and sweeps the counter, and returns non-zero when the
# dir is unusable or the key is empty — the can't-count path. The key_src test is
# separate on purpose: the hash input below always carries the subagent, so only
# an explicit check can tell a missing session key apart from a real one.
if [ -n "$key_src" ] && guard_state_path "${CREW_DISPATCH_DENIED_DIR:-${TMPDIR:-/tmp}}" \
  "crew-dispatch-denied" "$key_src$GUARD_RS$subagent" "$worker"; then
  state_file="$guard_state_path"
  guard_read_counter "$state_file"
  attempt=$((guard_count + 1))
  printf '%s\n' "$attempt" > "$state_file" 2>/dev/null || attempt=0
fi

if [ "$attempt" -eq 1 ]; then
  jq -nc --arg m "crew: auto mode's classifier denied the $subagent dispatch. It judges each dispatch on its own and is not deterministic, so crew is retrying this one once." \
    '{hookSpecificOutput: {hookEventName: "PermissionDenied", retry: true}, systemMessage: $m}'
  exit 0
fi

# Only claim "again" when a counted attempt says so: on the can't-count path this
# may well be the first denial, and saying otherwise sends the user looking for a
# retry that never happened.
if [ "$attempt" -eq 0 ]; then
  msg="crew: auto mode's classifier denied the $subagent dispatch. crew cannot track attempts in this session, so it is not retrying — the step comes back to you."
else
  msg="crew: auto mode's classifier denied the $subagent dispatch again — not retrying, so the step comes back to you."
fi
# Single-quoted: "$defaults" is the literal settings token the user must keep,
# not an expansion.
# shellcheck disable=SC2016
msg="$msg"' Note that permissions.allow cannot cover this: auto mode drops `Agent` allow rules on entry, so every crew dispatch is classified individually. What does work: switch this session to acceptEdits (Shift+Tab) instead of auto; describe the project in autoMode.environment in ~/.claude/settings.json (keeping the "$defaults" entry — the classifier does not read project settings); or reissue the call yourself from /permissions > Recently denied (press r).'
jq -nc --arg m "$msg" '{systemMessage: $m}'
exit 0
