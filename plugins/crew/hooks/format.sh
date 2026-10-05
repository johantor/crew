#!/usr/bin/env bash
# PostToolUse(Edit|Write) formatter for the agents that write source (oracle
# included: an unformatted test fails the same lint gate). A runner, not a
# detector: every `formatMatrix` row matching the edited file runs from its
# directory with `{file}` substituted (AGENTS.md, "Why format.sh runs a matrix
# and detects nothing").
set -e

# Fail open: formatting is best-effort.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/crew/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
. "$_lib" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

guard_read_payload
# One jq pass; the path is only computed for an agent this hook formats for.
guard_jq2 \
  '(if ((.agent_type // "") | sub("^crew:"; "") | test("^(tank|trinity|neo|oracle)$")) then ((.tool_input.file_path // .tool_input.path) // "") else "" end)' \
  '.agent_type // ""' || exit 0
guard_agent_type
path="$guard_untrusted"

case "$agent_type" in
  tank|trinity|neo|oracle) : ;;
  *)                       exit 0 ;;
esac
[ -n "$path" ] || exit 0

# No matrix means per-edit formatting is off; morpheus nudges once, not every edit.
guard_config_load
rows="$(config_block formatMatrix)"
[ -n "$rows" ] || exit 0

# Rows name project-relative directories; the payload may carry an absolute path.
case "$path" in
  "$PWD"/*) path="${path#"$PWD"/}" ;;
  ./*)      path="${path#./}" ;;
esac
ext="${path##*.}"
[ "$ext" = "$path" ] && ext=""

# Bounded: a hang would stall every edit, and the harness's kill can truncate a
# file mid-write. Unbounded where `timeout`/`gtimeout` is absent (stock macOS).
FORMAT_TIMEOUT="${CREW_FORMAT_TIMEOUT:-20}"
timeout_bin=""
for _t in timeout gtimeout; do
  if command -v "$_t" >/dev/null 2>&1; then timeout_bin="$_t"; break; fi
done

# run_bounded <cmd...> — exit status of the command, 124 when the bound killed it.
run_bounded() {
  local _st=0
  if [ -n "$timeout_bin" ]; then
    "$timeout_bin" "$FORMAT_TIMEOUT" "$@" >/dev/null 2>&1 || _st=$?
  else
    "$@" >/dev/null 2>&1 || _st=$?
  fi
  return "$_st"
}

# stderr at exit 0 never reaches the model, so a nudge the worker must hand back
# is also returned as PostToolUse `additionalContext` below.
nudge() { echo "format hook: $1" >&2; nudges="${nudges:+$nudges$'\n'}format hook: $1"; }

ran=""
nudges=""
sq="'"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  # Two controlled fields first, the command (which may hold spaces) last. A
  # directory with a space is single-quoted: `'my service/' java ...`.
  case "$row" in
    \'*) rest="${row#\'}"; dir="${rest%%\'*}"; read -r exts cmd <<<"${rest#*\'}" ;;
    *)   read -r dir exts cmd <<<"$row" ;;
  esac
  if [ -z "$cmd" ]; then
    nudge "formatMatrix row '$row' is not '<dir> <extensions> <command>'; run /crew:init"
    continue
  fi
  dir="${dir%/}"
  if [ "$dir" = "." ]; then
    rel="$path"
  else
    case "$path" in
      "$dir"/*) rel="${path#"$dir"/}" ;;
      *)        continue ;;
    esac
  fi
  case ",$exts," in
    *",$ext,"*) ;;
    *)          continue ;;
  esac
  tool="${cmd%% *}"; tool="${tool##*/}"
  if [ ! -d "$dir" ]; then
    nudge "formatMatrix row directory '$dir' is missing; run /crew:init"
    continue
  fi
  # {file} is single-quoted so a space or a quote in the path stays one argument.
  q="${rel//\'/\'\\\'\'}"
  cmd="${cmd//\{file\}/$sq$q$sq}"
  st=0
  ( cd "$dir" && run_bounded bash -c "$cmd" ) || st=$?
  if [ "$st" = 0 ]; then
    ran="$ran $tool"
  elif [ -n "$timeout_bin" ] && [ "$st" = 124 ]; then
    # 124 is `timeout`'s convention; no formatter here exits it of its own accord.
    echo "format hook: $tool timed out after ${FORMAT_TIMEOUT}s on $path" >&2
  elif [ "$st" = 127 ]; then
    # Only a standalone tool exits 127; a wrapper's missing subcommand lands below
    # and the lint gate reports the stale matrix (AGENTS.md, accepted gaps).
    nudge "$tool not found for formatMatrix row '$dir $exts'; run /crew:init"
  else
    echo "format hook: $tool failed (exit $st) on $path" >&2
  fi
done <<<"$rows"

[ -n "$ran" ] && echo "format hook: applied$ran on $path" >&2
[ -n "$nudges" ] && jq -nc --arg m "$nudges" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
