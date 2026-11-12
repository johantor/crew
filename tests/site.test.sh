#!/usr/bin/env bash
# Behavior tests for scripts/site.sh, the site runner: start launches the
# configured runCommand detached and waits for runUrl, a site another process
# runs is `external` and never stopped, stop kills the whole process group, and
# the time limit ends a site nobody stopped.
# shellcheck source=tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugin/scripts" && pwd)/site.sh"

check() {  # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then _pass; else _fail "$1: expected [$2], got [$3]"; fi
}

# No network: a fake curl answers while the pid in ./up is alive. A fixture's
# runCommand writes its own pid there, so the site "answers" until it is killed.
fakebin="$(new_tmpdir)"
# shellcheck disable=SC2016  # the fake script's own expansions
printf '#!/bin/sh\n[ -s up ] && kill -0 "$(cat up)" 2>/dev/null\n' >"$fakebin/curl"
chmod +x "$fakebin/curl"
serve='echo started >>starts; echo $$ >up; exec sleep 300'

# project <runUrl> <runCommand> — echoes a project root holding that config.
project() {
  local dir; dir="$(new_tmpdir)"
  mkdir "$dir/.claude"
  printf -- '---\nbaseBranch: main\nrunUrl: %s\nrunCommand: %s\n---\n\nrunCommand: echo body-is-prose\n' "$1" "$2" >"$dir/.claude/crew.md"
  echo "$dir"
}
# site <project> <op> — runs the runner from the project root, on the fake curl.
site() { (cd "$1" && PATH="$fakebin:$PATH" bash "$SITE" "$2" 2>&1); }
state() { echo "/tmp/crew-site-$(cd "$1" && pwd -P | cksum | cut -d' ' -f1)"; }
projects=()
# Extends the harness's EXIT trap: stop every site, then drop its state directory.
# shellcheck disable=SC2329  # invoked by the trap
cleanup() {
  local q
  for q in "${projects[@]}"; do site "$q" stop >/dev/null; rm -rf "$(state "$q")"; done
  rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT

# --- start, status, stop -------------------------------------------------------
p1="$(project http://localhost:5000/ "$serve")"; projects+=("$p1")
check "nothing running reads as stopped" "stopped" "$(site "$p1" status)"
check "start waits until the URL answers" "ready" "$(site "$p1" start)"
check "status of a started site" "ready" "$(site "$p1" status)"
check "the state directory is private and holds the log" "private" \
  "$([ -f "$(state "$p1")/log" ] && [ -z "$(find "$(state "$p1")" -maxdepth 0 -perm -g=r -o -maxdepth 0 -perm -o=r)" ] && echo private)"
check "a second start reuses the running site" "ready" "$(site "$p1" start)"
check "the command ran once" "1" "$(grep -c started "$p1/starts")"
check "stop kills the site" "stopped" "$(site "$p1" stop)"
check "a stopped site no longer answers" "stopped" "$(site "$p1" status)"
check "start after stop launches again" "ready" "$(site "$p1" start)"
check "the command ran a second time" "2" "$(grep -c started "$p1/starts")"
site "$p1" stop >/dev/null

# A command that starts children: stop must take the whole group down.
p2="$(project http://localhost:5000/ 'sleep 300 & echo $! >child; echo $$ >up; exec sleep 300')"; projects+=("$p2")
site "$p2" start >/dev/null
check "stop reports the group gone" "stopped" "$(site "$p2" stop)"
check "stop kills the command's children" "gone" "$(kill -0 "$(cat "$p2/child")" 2>/dev/null && echo alive || echo gone)"

# --- a site another process runs ----------------------------------------------
p3="$(project http://localhost:5000/ none)"; projects+=("$p3")
sleep 300 & other=$!
echo "$other" >"$p3/up"
check "an answering URL nobody started here is external" "external" "$(site "$p3" start)"
check "status of an external site" "external" "$(site "$p3" status)"
check "stop leaves an external site alone" "external" "$(site "$p3" stop)"
check "the external process survives stop" "alive" "$(kill -0 "$other" 2>/dev/null && echo alive || echo gone)"
kill "$other" 2>/dev/null

# --- failures are loud -----------------------------------------------------------
p4="$(project http://localhost:5000/ 'echo boom-on-startup; exit 7')"; projects+=("$p4")
out="$(site "$p4" start)"; rc=$?
check "a command that exits before it answers fails" "1" "$rc"
check "the failure opens with failed" "failed" "${out%%$'\n'*}"
check "the failure carries the log's tail" "boom-on-startup" "$(grep -o boom-on-startup <<<"$out" | head -n 1)"
check "the log records the exit code" "1" "$(grep -c 'exited with 7' <<<"$out")"

site "$p3" start >/dev/null; rc=$?
check "no runCommand and nothing answering is refused" "3" "$rc"
check "the refusal names the slot and /crew:init" "1" "$(site "$p3" start | grep -c "runCommand is 'none'.*crew:init")"
p5="$(project none "$serve")"
site "$p5" start >/dev/null; rc=$?
check "runUrl none is refused" "3" "$rc"
p6="$(project '-o /tmp/crew-site-injected' "$serve")"
site "$p6" start >/dev/null; rc=$?
check "a runUrl that is not http(s) is refused" "3" "$rc"
(cd "$(new_tmpdir)" && bash "$SITE" start >/dev/null 2>&1); rc=$?
check "no crew.md is refused" "3" "$rc"
(cd "$p1" && bash "$SITE" restart >/dev/null 2>&1); rc=$?
check "an unknown operation is refused" "2" "$rc"

# --- bounds --------------------------------------------------------------------
# The wait ends inside the call: a site still starting is reported, not waited out.
p7="$(project http://localhost:5000/ 'exec sleep 300')"; projects+=("$p7")
check "a site not yet answering reports starting" "starting" "$(CREW_SITE_WAIT=1 site "$p7" start)"
check "status while starting" "starting" "$(site "$p7" status)"
check "a starting site stops" "stopped" "$(site "$p7" stop)"
# The time limit kills a site nobody stopped, and the log says why.
p8="$(project http://localhost:5000/ "$serve")"; projects+=("$p8")
CREW_SITE_TTL=1 site "$p8" start >/dev/null
for ((i = 0; i < 20; i++)); do [ "$(site "$p8" status)" = stopped ] && break; sleep 1; done
check "the time limit stops the site" "stopped" "$(site "$p8" status)"
check "the log names the time limit" "1" "$(grep -c 'time limit' "$(state "$p8")/log")"
# A pid file that outlives its group could later name an unrelated process.
for q in "$p1" "$p4" "$p8"; do
  check "no pid file outlives the site" "absent" "$([ -e "$(state "$q")/pid" ] && echo present || echo absent)"
done

# --- config reading ------------------------------------------------------------
# The command runs as it stands, shell quotes and backslashes included; the
# prose body's `runCommand:` is not read.
# shellcheck disable=SC2016  # the fixture command's own expansions
p9="$(project http://localhost:5000/ 'printf "%s\\n" "a: b" '\''c d'\'' >said; echo $$ >up; exec sleep 300')"; projects+=("$p9")
check "a command with quotes and a backslash starts" "ready" "$(site "$p9" start)"
check "the command ran verbatim" "a: b|c d" "$(paste -sd'|' "$p9/said")"
site "$p9" stop >/dev/null
# A YAML-quoted value is not decoded: it fails loudly instead of running something else.
p10="$(project http://localhost:5000/ "'echo \$\$ >up; exec sleep 300'")"; projects+=("$p10")
check "a YAML-quoted command is not unwrapped" "failed" "$(site "$p10" start | head -n 1)"

# --- one start at a time, and only our own state directory -----------------------
p11="$(project http://localhost:5000/ "$serve")"; projects+=("$p11")
mkdir -p "$(state "$p11")/lock"
site "$p11" start >"$p11/out" & held=$!
sleep 2
check "a start waits while another start holds the lock" "absent" "$([ -e "$p11/starts" ] && echo present || echo absent)"
rmdir "$(state "$p11")/lock"; wait "$held"
check "the waiting start then runs" "ready" "$(head -n 1 "$p11/out")"
check "the lock is released" "absent" "$([ -e "$(state "$p11")/lock" ] && echo present || echo absent)"
site "$p11" stop >/dev/null
# A symlinked state directory is never read: its pid could name any process group.
p12="$(project http://localhost:5000/ none)"; projects+=("$p12")
planted="$(new_tmpdir)"; set -m; sleep 300 & victim=$!; set +m
echo "$victim" >"$planted/pid"; ln -s "$planted" "$(state "$p12")"
check "stop ignores a symlinked state directory" "stopped" "$(site "$p12" stop)"
check "the process a planted pid names survives" "alive" "$(kill -0 "$victim" 2>/dev/null && echo alive || echo gone)"
kill -- "-$victim" 2>/dev/null

finish
