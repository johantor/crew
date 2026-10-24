#!/usr/bin/env bash
# Runs one review-gate command detached and bounded, so it ends inside the
# worker's turn (#239) and a headless worker can run it under one allow rule
# (#245): each call is a single simple command, where the inline recipe it
# replaces was a compound one that Claude's permission check refuses.
#
#   gate.sh start <id> <command> [nocache]   launch; fails if <id> was used before
#   gate.sh poll  <id>             wait up to ~9 min; print the exit code or `running`
#   gate.sh stop  <id>             kill the process group; print `stopped` or `still-running`
#
# <id> is minted per handoff by the dispatcher (lane plus 8 hex characters).
# State lives in /tmp/crew-gate-<id>/{log,exit,pid}; grep the log for findings.
#
# A green run's log is kept under $CREW_GATE_CACHE_DIR (default
# /tmp/crew-gate-cache), keyed by the working tree's git hash, the physical
# directory and the command; a repeat on an unchanged tree is answered from it,
# with `crew-gate: cached` as the log's first line (AGENTS.md, gate command).
# `nocache` runs without reading or writing it: for a run whose result a later
# check may still discard, such as a Parallel gates recipe's.
set -u

usage() { echo "usage: gate.sh start <id> <command> [nocache] | poll <id> | stop <id>" >&2; exit 2; }

[ $# -ge 2 ] || usage
op="$1" id="$2"
case "$id" in
  ''|*[!a-z0-9-]*) echo "gate.sh: <id> must be lowercase letters, digits and dashes" >&2; exit 2 ;;
esac
d="/tmp/crew-gate-$id"
cache="${CREW_GATE_CACHE_DIR-/tmp/crew-gate-cache}"
# An override is an absolute path or nothing: a relative one reads as an option.
case "$cache" in /*|'') ;; *) cache='' ;; esac

# Prints the cache key for <command>, or nothing outside a git repo and when
# the hashed tree holds a gitlink (a submodule's or an embedded repo's dirty
# content is invisible to the outer hash). The tree hash covers tracked and
# untracked files as git sees them (ignored files, so build outputs,
# excluded), taken through a copy of the index so it never touches the real
# one. The physical directory is part of the key: two checkouts with one tree
# can differ in ignored dependencies. Fields are NUL-delimited, since a path
# or a command may contain a newline.
cache_key() {
  local tree
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  cp "$(git rev-parse --git-path index)" "$d/index" 2>/dev/null
  tree="$(GIT_INDEX_FILE="$d/index" git add -A >/dev/null 2>&1 \
    && ! GIT_INDEX_FILE="$d/index" git ls-files -s 2>/dev/null | grep -q '^160000 ' \
    && GIT_INDEX_FILE="$d/index" git write-tree 2>/dev/null)"
  rm -f "$d/index"
  [ -n "$tree" ] && printf '%s\0%s\0%s\0' "$tree" "$(pwd -P)" "$1" | git hash-object --stdin
}

# The cache is trusted only as a private directory of this user: /tmp is
# shared, and an override may name a directory others can write. A permission
# query that fails counts as writable.
cache_ok() {
  local w
  [ -n "$cache" ] && [ -d "$cache" ] && [ ! -L "$cache" ] && [ -O "$cache" ] || return 1
  w="$(find "$cache" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>&1)" && [ -z "$w" ]
}

case "$op" in
  start)
    case "$#:${4-}" in 3:|4:nocache) ;; *) usage ;; esac
    # umask, not `mkdir -m`: Git Bash's mkdir creates the directory, then fails the mode.
    (umask 077 && mkdir "$d") 2>/dev/null || { echo "gate.sh: $d already exists; mint a new <id>" >&2; exit 3; }
    # An empty key is a run outside the cache, on both the read and the write.
    key=''; [ "${4-}" = nocache ] || key="$(cache_key "$3")"
    # A hit needs the whole cached log; a copy that fails runs the gate instead.
    if [ -n "$key" ] && cache_ok \
      && { echo "crew-gate: cached; this command ran green on this tree before"; cat "$cache/$key"; } >"$d/log" 2>/dev/null; then
      echo 0 >"$d/exit"
      echo "$d"
      exit 0
    fi
    # Job control gives the background job its own process group, so stop can
    # kill the whole tree the command starts.
    set -m
    # Each file lands via a rename, so poll never reads a half-written one. The
    # log is cached only for exit 0 and only if the tree is what it was at
    # start, and before the exit code is published, so a repeat after poll hits.
    (
      bash -c "$3" >"$d/log" 2>&1; rc=$?
      if [ "$rc" -eq 0 ] && [ -n "$key" ] && [ "$(cache_key "$3")" = "$key" ]; then
        [ -n "$cache" ] && (umask 077 && mkdir "$cache") 2>/dev/null
        cache_ok && cp "$d/log" "$cache/$key.$id" && mv "$cache/$key.$id" "$cache/$key"
      fi
      echo "$rc" >"$d/exit.tmp"; mv "$d/exit.tmp" "$d/exit"
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
