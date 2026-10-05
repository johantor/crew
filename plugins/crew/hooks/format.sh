#!/usr/bin/env bash
# PostToolUse(Edit|Write) formatter, gated to the agents that write source
# (tank/trinity/neo/oracle; other agents and the main session are no-ops). oracle
# is included because a test file is source too: unformatted, it fails the same
# lint gate at the end of the run.
#
# A runner, not a detector. The `formatMatrix` slot in `.claude/crew.md` holds
# one row per `<dir> <extensions> <command>`, written by /crew:init from what the
# project configures; every row whose directory and extension list match the
# edited file runs, in order, from that directory, with `{file}` replaced by the
# file's path relative to it. A file no row covers is left alone. See AGENTS.md,
# "Why format.sh runs a matrix and detects nothing".
set -e

# Fail open: formatting is best-effort, so a missing library or jq is a no-op,
# not an error.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/crew/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
. "$_lib" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

guard_read_payload
# Both fields in one jq pass, and the path is only computed for an agent this
# hook formats for, so the far more common no-op call doesn't pay to look it up.
# neo is the cross-lane express-lane generalist, so it gets the same routing as
# tank/trinity rather than a fixed lane.
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

# No matrix (file or slot missing, `none`, `unset`) means per-edit formatting is
# off. Silent: morpheus nudges once per run to run /crew:init; a line here would
# repeat on every edit.
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

# Every formatter runs under a wall-clock bound. This fires after *every* edit, so
# a hang would stall the agent each time, and the harness's kill can land mid
# `--write` and truncate a source file. `timeout`/`gtimeout` is used when present
# and skipped when not (absent on stock macOS/BSD) -- the same degrade-don't-fail
# posture as the missing-jq path above. Plain SIGTERM, no `-k`: not every
# `timeout` build accepts it, and every formatter routed here dies on a signal.
FORMAT_TIMEOUT="${CREW_FORMAT_TIMEOUT:-20}"
timeout_bin=""
for _t in timeout gtimeout; do
  if command -v "$_t" >/dev/null 2>&1; then timeout_bin="$_t"; break; fi
done

# run_bounded <cmd...> — run a formatter quietly under that bound, returning its
# exit status (124 when the bound killed it).
run_bounded() {
  local _st=0
  if [ -n "$timeout_bin" ]; then
    "$timeout_bin" "$FORMAT_TIMEOUT" "$@" >/dev/null 2>&1 || _st=$?
  else
    "$@" >/dev/null 2>&1 || _st=$?
  fi
  return "$_st"
}

# stderr at exit 0 reaches only the debug log, never the model. A stale-matrix
# nudge has to reach the worker (it hands the line back, `worker-contract`), so
# those lines are also returned as PostToolUse `additionalContext` below.
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
    # The tool the row names is gone: the matrix is stale, not the file. Only a
    # standalone tool exits 127; a wrapper (`dotnet csharpier`) that cannot find
    # its subcommand fails with its own status and lands below, and the lint gate
    # reports the stale matrix instead (AGENTS.md, accepted gaps).
    nudge "$tool not found for formatMatrix row '$dir $exts'; run /crew:init"
  else
    echo "format hook: $tool failed (exit $st) on $path" >&2
  fi
done <<<"$rows"

[ -n "$ran" ] && echo "format hook: applied$ran on $path" >&2
[ -n "$nudges" ] && jq -nc --arg m "$nudges" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
