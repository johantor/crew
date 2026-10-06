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
# Git Bash's mkdir creates the directory, then fails `-m`; start must not need it.
gitbash="$(new_tmpdir)"; real_mkdir="$(command -v mkdir)"
# shellcheck disable=SC2016  # $a and $@ belong to the fake script
printf '#!/bin/sh\nfor a; do case "$a" in -m*) %s "$@"; exit 1 ;; esac; done\nexec %s "$@"\n' \
  "$real_mkdir" "$real_mkdir" >"$gitbash/mkdir"
chmod +x "$gitbash/mkdir"
check "start works where mkdir -m fails after creating" "/tmp/crew-gate-$id-gb" \
  "$(PATH="$gitbash:$PATH" bash "$GATE" start "$id-gb" 'true' 2>&1)"
check "the gate directory is private" "" "$(find "/tmp/crew-gate-$id-gb" -maxdepth 0 -perm -g=r -o -maxdepth 0 -perm -o=r)"
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
mkdir -p "$repo/apps/api" "$repo/apps/web"
gate "$repo/apps/api" start "$id-c9" 'echo one' >/dev/null; gate "$repo/apps/api" poll "$id-c9" >/dev/null
gate "$repo/apps/web" start "$id-c10" 'echo one' >/dev/null; gate "$repo/apps/web" poll "$id-c10" >/dev/null
check "the same command from another package directory is not a hit" "0" "$(cached "$id-c10")"
gate "$repo/apps/api" start "$id-c11" 'echo one' >/dev/null; gate "$repo/apps/api" poll "$id-c11" >/dev/null
check "the same command from the same subdirectory is a hit" "1" "$(cached "$id-c11")"
printf 'b\n' >"$repo/a.txt"
gate "$repo" start "$id-c4" 'echo one' >/dev/null; gate "$repo" poll "$id-c4" >/dev/null
check "an edited tree is not a hit" "0" "$(cached "$id-c4")"
entries() { local n=0 f; for f in "$CREW_GATE_CACHE_DIR"/*; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }
before="$(entries)"
gate "$repo" start "$id-c19" 'echo three' >/dev/null; gate "$repo" poll "$id-c19" >/dev/null
check "the cached log is published before the exit code" "$((before + 1))" "$(entries)"
check "no per-run temp file is left in the cache" "absent" "$(for f in "$CREW_GATE_CACHE_DIR"/*.*; do [ -e "$f" ] && echo present; done; echo absent)"
# Another checkout of the very same tree can differ in ignored dependencies.
git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm base
git -C "$repo" worktree add -q "$repo-wt" -b wt 2>/dev/null
gate "$repo" start "$id-c12" 'echo one' >/dev/null; gate "$repo" poll "$id-c12" >/dev/null
gate "$repo-wt" start "$id-c13" 'echo one' >/dev/null; gate "$repo-wt" poll "$id-c13" >/dev/null
check "another checkout of the same tree is not a hit" "0" "$(cached "$id-c13")"
# A command that writes into the tree changes the key it would be cached under.
gate "$repo" start "$id-c14" 'echo out >built.txt' >/dev/null; gate "$repo" poll "$id-c14" >/dev/null
gate "$repo" start "$id-c15" 'echo out >built.txt' >/dev/null; gate "$repo" poll "$id-c15" >/dev/null
check "a run that changed the tree is not cached" "0" "$(cached "$id-c15")"
# A cache directory others can write is not trusted, for a hit or a write.
chmod g+w "$CREW_GATE_CACHE_DIR"
gate "$repo" start "$id-c16" 'echo one' >/dev/null; gate "$repo" poll "$id-c16" >/dev/null
check "a group-writable cache directory is not read" "0" "$(cached "$id-c16")"
chmod g-w "$CREW_GATE_CACHE_DIR"
# nocache: a run whose result a later check may discard neither reads nor writes.
gate "$repo" start "$id-c22" 'echo four' nocache >/dev/null; gate "$repo" poll "$id-c22" >/dev/null
gate "$repo" start "$id-c23" 'echo four' >/dev/null; gate "$repo" poll "$id-c23" >/dev/null
check "a nocache run writes no entry" "0" "$(cached "$id-c23")"
gate "$repo" start "$id-c24" 'echo four' nocache >/dev/null; gate "$repo" poll "$id-c24" >/dev/null
check "a nocache run reads no entry" "0" "$(cached "$id-c24")"
bash "$GATE" start "$id-c25" 'true' other >/dev/null 2>&1
check "an unknown fourth argument is refused" "2" "$?"
# A failing permission query is not an empty one: the cache is then untrusted.
fakebin="$(new_tmpdir)"; printf '#!/bin/sh\nexit 1\n' >"$fakebin/find"; chmod +x "$fakebin/find"
PATH="$fakebin:$PATH" gate "$repo" start "$id-c20" 'echo one' >/dev/null; gate "$repo" poll "$id-c20" >/dev/null
check "a failed permission query is not a hit" "0" "$(cached "$id-c20")"
# A relative override would read as an option to the query; it disables the cache.
(cd "$repo" && CREW_GATE_CACHE_DIR=-cache bash "$GATE" start "$id-c21" 'echo one' >/dev/null; bash "$GATE" poll "$id-c21" >/dev/null)
check "a relative cache directory is never a hit" "0" "$(cached "$id-c21")"
check "a relative cache directory is never created" "absent" "$([ -e "$repo/-cache" ] && echo present || echo absent)"
# A submodule's dirty content is invisible to the superproject's tree hash: a
# checked-out gitlink, with or without .gitmodules, disables the cache.
git init -q "$repo/sub" && printf 's\n' >"$repo/sub/s.txt"
git -C "$repo" update-index --add --cacheinfo "160000,$(git -C "$repo" rev-parse HEAD),sub"
gate "$repo" start "$id-c17" 'echo one' >/dev/null; gate "$repo" poll "$id-c17" >/dev/null
gate "$repo" start "$id-c18" 'echo one' >/dev/null; gate "$repo" poll "$id-c18" >/dev/null
check "a repo with a checked-out gitlink is never a hit" "0" "$(cached "$id-c18")"
git -C "$repo" update-index --force-remove sub; rm -rf "$repo/sub"
# An untracked embedded repo is staged as a gitlink by the hashing add: same rule.
git init -q "$repo/embedded" && printf 'e\n' >"$repo/embedded/e.txt"
gate "$repo" start "$id-c26" 'echo one' >/dev/null; gate "$repo" poll "$id-c26" >/dev/null
gate "$repo" start "$id-c27" 'echo one' >/dev/null; gate "$repo" poll "$id-c27" >/dev/null
check "an untracked embedded repo is never a hit" "0" "$(cached "$id-c27")"
rm -rf "$repo/embedded"
# Key fields are NUL-delimited: `true` from a directory named "a<newline>exit 1"
# and "exit 1<newline>true" from "a" would otherwise share a key.
mkdir -p "$repo/a"$'\n'"exit 1" "$repo/a"
gate "$repo/a"$'\n'"exit 1" start "$id-c28" 'true' >/dev/null
check "the newline-collision setup ran green" "0" "$(gate "$repo/a"$'\n'"exit 1" poll "$id-c28")"
gate "$repo/a" start "$id-c29" $'exit 1\ntrue' >/dev/null
check "a newline-shifted key is not a hit" "1" "$(gate "$repo/a" poll "$id-c29")"
# A hit needs the whole cached log: an entry that cannot be read runs the gate.
gate "$repo" start "$id-c30" 'echo five' >/dev/null; gate "$repo" poll "$id-c30" >/dev/null
for f in "$CREW_GATE_CACHE_DIR"/*; do grep -q five "$f" 2>/dev/null && rm -f "$f" && mkdir "$f"; done
gate "$repo" start "$id-c31" 'echo five' >/dev/null
check "an unreadable entry runs the gate" "0" "$(gate "$repo" poll "$id-c31")"
check "an unreadable entry is not reported as a hit" "0" "$(cached "$id-c31")"
check "the gate that ran holds its own output" "five" "$(grep -o five "/tmp/crew-gate-$id-c31/log")"
gate "$repo" start "$id-c5" 'exit 4' >/dev/null; gate "$repo" poll "$id-c5" >/dev/null
gate "$repo" start "$id-c6" 'exit 4' >/dev/null
check "a red run is never cached" "4" "$(gate "$repo" poll "$id-c6")"
plain="$(new_tmpdir)"
gate "$plain" start "$id-c7" 'echo one' >/dev/null; gate "$plain" poll "$id-c7" >/dev/null
gate "$plain" start "$id-c8" 'echo one' >/dev/null; gate "$plain" poll "$id-c8" >/dev/null
check "outside a git repo nothing is cached" "0" "$(cached "$id-c8")"

finish
