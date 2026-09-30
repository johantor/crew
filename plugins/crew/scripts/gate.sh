#!/usr/bin/env bash
# Runs one review-gate command detached and bounded, so it ends inside the
# worker's turn (#239) and a headless worker can run it under one allow rule
# (#245): each call is a single simple command, where the inline recipe it
# replaces was a compound one that Claude's permission check refuses.
#
#   gate.sh start <id> <command>   launch; fails if <id> was used before
#   gate.sh poll  <id>             wait up to ~9 min; print the exit code or `running`
#   gate.sh stop  <id>             kill the process group; print `stopped` or `still-running`
#
# <id> is minted per handoff by the dispatcher (lane plus 8 hex characters).
# State lives in /tmp/crew-gate-<id>/{log,exit,pid}; grep the log for findings.
#
# A green run's log is kept under $CREW_GATE_CACHE_DIR (default
# /tmp/crew-gate-cache), keyed by the working tree's git hash, the directory
# and the command; a repeat on an unchanged tree is answered from it, with
# `crew-gate: cached` as the log's first line (AGENTS.md, gate command).
set -u

usage() { echo "usage: gate.sh start <id> <command> | poll <id> | stop <id>" >&2; exit 2; }

[ $# -ge 2 ] || usage
op="$1" id="$2"
case "$id" in
  ''|*[!a-z0-9-]*) echo "gate.sh: <id> must be lowercase letters, digits and dashes" >&2; exit 2 ;;
esac
d="/tmp/crew-gate-$id"
cache="${CREW_GATE_CACHE_DIR-/tmp/crew-gate-cache}"

# Prints the cache key for <command>, or nothing outside a git repo. The tree
# hash covers tracked and untracked files as git sees them (ignored files, so
# build outputs, excluded), taken through a copy of the index so it never
# touches the real one. The directory is part of the key: one repo can hold
# several packages whose scripts share a name.
cache_key() {
  local tree
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  cp "$(git rev-parse --git-path index)" "$d/index" 2>/dev/null
  tree="$(GIT_INDEX_FILE="$d/index" git add -A >/dev/null 2>&1 && GIT_INDEX_FILE="$d/index" git write-tree 2>/dev/null)"
  rm -f "$d/index"
  [ -n "$tree" ] && printf '%s\n%s\n%s\n' "$tree" "$(git rev-parse --show-prefix)" "$1" | git hash-object --stdin
}

case "$op" in
  start)
    [ $# -eq 3 ] || usage
    mkdir -m 700 "$d" 2>/dev/null || { echo "gate.sh: $d already exists; mint a new <id>" >&2; exit 3; }
    key="$(cache_key "$3")"
    # Trusted only when this user owns the directory: /tmp is shared.
    if [ -n "$cache" ] && [ -n "$key" ] && [ -O "$cache" ] && [ -f "$cache/$key" ]; then
      { echo "crew-gate: cached; this command ran green on this tree before"; cat "$cache/$key"; } >"$d/log"
      echo 0 >"$d/exit"
      echo "$d"
      exit 0
    fi
    # Job control gives the background job its own process group, so stop can
    # kill the whole tree the command starts.
    set -m
    # The code lands via a rename, so poll never reads a half-written file; so
    # does the cached log, which is written only for exit 0.
    (
      bash -c "$3" >"$d/log" 2>&1; rc=$?
      echo "$rc" >"$d/exit.tmp"; mv "$d/exit.tmp" "$d/exit"
      if [ "$rc" -eq 0 ] && [ -n "$cache" ] && [ -n "$key" ]; then
        mkdir -m 700 "$cache" 2>/dev/null
        [ -O "$cache" ] && cp "$d/log" "$cache/$key.tmp" && mv "$cache/$key.tmp" "$cache/$key"
      fi
    ) >/dev/null 2>&1 &
    echo $! >"$d/pid"
    echo "$d"
    ;;
  poll)
    [ -d "$d" ] || { echo "gate.sh: no gate $d" >&2; exit 3; }
    for ((i = 0; i < 110; i++)); do [ -s "$d/exit" ] && break; sleep 5; done
    if [ -s "$d/exit" ]; then head -c 8 "$d/exit"; else echo running; fi
    ;;
  stop)
    # A cached gate never started a process, so there is nothing to stop.
    [ -f "$d/pid" ] || { [ -s "$d/exit" ] && { echo stopped; exit 0; }; echo "gate.sh: no gate $d" >&2; exit 3; }
    p="$(head -c 16 "$d/pid")"
    kill -TERM -- "-$p" 2>/dev/null
    for ((i = 0; i < 60; i++)); do kill -0 -- "-$p" 2>/dev/null || break; sleep 1; done
    if kill -0 -- "-$p" 2>/dev/null; then echo still-running; else echo stopped; fi
    ;;
  *) usage ;;
esac
