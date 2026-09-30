#!/usr/bin/env bash
# Behavior tests for scripts/gate.sh, the review-gate runner (#245): start runs
# the command detached and records its exit code and log, poll reports that code,
# stop kills the whole process group, and a reused or malformed <id> is refused.
# A green run is cached by tree and command; a changed tree, a red exit or no
# repo runs the command again.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"
GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/gate.sh"

# Ids are unique per run so parallel suites never share a /tmp directory.
id="t-$$-$RANDOM"; id2="${id}-b"
# Extends the harness's EXIT trap (which removes FIXTURE_ROOT) rather than replacing it.
trap 'rm -rf "$FIXTURE_ROOT" /tmp/crew-gate-"$id"*' EXIT
# The cache is per suite run, never the machine's, so a stale entry cannot pass a test.
export CREW_GATE_CACHE_DIR="$FIXTURE_ROOT/gate-cache"

check() {  # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then _pass; else _fail "$1: expected [$2], got [$3]"; fi
}
# gate <cwd> <op> <id> [command] — runs the runner from <cwd>, since the cache keys on its repo.
gate() { local cwd="$1"; shift; (cd "$cwd" && bash "$GATE" "$@"); }
cached() { grep -c '^crew-gate: cached' "/tmp/crew-gate-$1/log"; }

check "start prints the gate dir" "/tmp/crew-gate-$id" "$(bash "$GATE" start "$id" 'echo built; exit 4')"
check "poll reports the command's exit code" "4" "$(bash "$GATE" poll "$id")"
check "the log holds the command's output" "built" "$(grep -o built "/tmp/crew-gate-$id/log")"
# The exit code lands by rename, so no half-written temp file is left behind.
check "no temp exit file remains" "absent" "$([ -e "/tmp/crew-gate-$id/exit.tmp" ] && echo present || echo absent)"

bash "$GATE" start "$id" 'true' >/dev/null 2>&1
check "a reused id is refused" "3" "$?"
bash "$GATE" start 'Bad_Id' 'true' >/dev/null 2>&1
check "a malformed id is refused" "2" "$?"
bash "$GATE" poll "$id-missing" >/dev/null 2>&1
check "polling an unknown gate fails" "3" "$?"

# A command that starts children: stop must take the whole group down.
bash "$GATE" start "$id2" 'sleep 300 & sleep 300' >/dev/null
check "stop kills the process group" "stopped" "$(bash "$GATE" stop "$id2")"

# --- The cache: keyed by the working tree and the command --------------------
repo="$(make_git_branch main)"
printf 'a\n' >"$repo/a.txt"
gate "$repo" start "$id-c1" 'echo one' >/dev/null
check "a green run is recorded" "0" "$(gate "$repo" poll "$id-c1")"
check "the first run is not a cache hit" "0" "$(cached "$id-c1")"
gate "$repo" start "$id-c2" 'echo one' >/dev/null
check "the same command on the same tree is answered from the cache" "0" "$(gate "$repo" poll "$id-c2")"
check "a cached log says so on its first line" "1" "$(cached "$id-c2")"
check "a cached log carries the original output" "one" "$(grep -o one "/tmp/crew-gate-$id-c2/log")"
check "stop on a cached gate reports stopped" "stopped" "$(gate "$repo" stop "$id-c2")"
check "hashing leaves the real index alone" "" "$(git -C "$repo" diff --cached --name-only)"
gate "$repo" start "$id-c3" 'echo two' >/dev/null; gate "$repo" poll "$id-c3" >/dev/null
check "a different command on the same tree is not a hit" "0" "$(cached "$id-c3")"
printf 'b\n' >"$repo/a.txt"
gate "$repo" start "$id-c4" 'echo one' >/dev/null; gate "$repo" poll "$id-c4" >/dev/null
check "an edited tree is not a hit" "0" "$(cached "$id-c4")"
gate "$repo" start "$id-c5" 'exit 4' >/dev/null; gate "$repo" poll "$id-c5" >/dev/null
gate "$repo" start "$id-c6" 'exit 4' >/dev/null
check "a red run is never cached" "4" "$(gate "$repo" poll "$id-c6")"
plain="$(new_tmpdir)"
gate "$plain" start "$id-c7" 'echo one' >/dev/null; gate "$plain" poll "$id-c7" >/dev/null
gate "$plain" start "$id-c8" 'echo one' >/dev/null; gate "$plain" poll "$id-c8" >/dev/null
check "outside a git repo nothing is cached" "0" "$(cached "$id-c8")"

finish
