#!/usr/bin/env bash
# Runs the project's site detached and bounded, so `lead` can start it before a
# worker that needs the running URL and stop it after (AGENTS.md, site runner).
# It takes no command: it reads `runCommand` and `runUrl` from .claude/crew.md
# in the current directory, so an allow rule for it grants only that command.
#
#   site.sh start    start the site and wait up to ~9 min for runUrl to answer.
#                    Prints `ready`, `external` (it answers, another process
#                    runs it), `starting` (call again) or `failed` plus the log's tail
#   site.sh status   prints `ready`, `starting`, `external` or `stopped`
#   site.sh stop     kills the process group `start` launched; prints `stopped`
#                    or `still-running`, or `external` and touches nothing
#
# State lives in /tmp/crew-site-<checkout>/{log,pid}. The site is killed after
# $CREW_SITE_TTL seconds (default 3600), so a run that ends without `stop`
# leaves no server behind.
set -u

die() { echo "site.sh: $1" >&2; exit 3; }

# Prints a scalar slot from the frontmatter, one pair of surrounding quotes dropped.
slot() {
  local line first=1 v
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [ "$first" = 1 ]; then first=0; [ "$line" = '---' ] || return 0; continue; fi
    [ "$line" = '---' ] && return 0
    case "$line" in "$1:"*) ;; *) continue ;; esac
    v="${line#"$1:"}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    case "$v" in \"*\"|\'*\') v="${v#?}"; v="${v%?}" ;; esac
    printf '%s' "$v"; return 0
  done <.claude/crew.md
}

# Any HTTP response counts, an error page included: the site is up. -k, since a
# local dev certificate is self-signed.
answers() { curl -ks -o /dev/null --max-time 5 --url "$url" 2>/dev/null; }

# True while the process group `start` launched is alive; sets $p. A dead
# group's pid file is dropped, so a reused pid is never taken for the site.
own_alive() {
  [ -O "$d" ] && [ -s "$d/pid" ] || return 1
  # The site's own exit removes the file, possibly between the test and this read.
  p="$(head -c 16 "$d/pid" 2>/dev/null)"
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 -- "-$p" 2>/dev/null || { rm -f "$d/pid"; return 1; }
}

wait_ready() {
  while [ "$SECONDS" -lt "$wait" ]; do
    if ! own_alive; then
      echo failed; echo "--- $d/log"; tail -n 20 "$d/log"
      exit 1
    fi
    answers && { echo ready; return 0; }
    sleep 2
  done
  echo starting
}

case "${1-}" in start|status|stop) ;; *) echo "usage: site.sh start | status | stop" >&2; exit 2 ;; esac
[ -f .claude/crew.md ] || die "no .claude/crew.md here; run it from the project root"
command -v curl >/dev/null 2>&1 || die "curl is required to probe runUrl"
url="$(slot runUrl)"
case "$url" in
  http://*|https://*) ;;
  *) die "runUrl is '${url:-missing}' in .claude/crew.md; run /crew:init" ;;
esac
d="/tmp/crew-site-$(pwd -P | cksum | cut -d' ' -f1)"
ttl="${CREW_SITE_TTL-3600}"; case "$ttl" in ''|*[!0-9]*) ttl=3600 ;; esac
wait="${CREW_SITE_WAIT-540}"; case "$wait" in ''|*[!0-9]*) wait=540 ;; esac
p=''

case "$1" in
  start)
    if own_alive; then wait_ready; exit 0; fi
    if answers; then echo external; exit 0; fi
    cmd="$(slot runCommand)"
    case "$cmd" in ''|unset|none) die "runCommand is '${cmd:-missing}' in .claude/crew.md; run /crew:init" ;; esac
    # /tmp is shared: the directory is ours and private, or nothing starts.
    (umask 077 && mkdir "$d") 2>/dev/null
    [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ] || die "$d is not a directory this user owns"
    # Job control gives the job its own process group, so stop kills the whole
    # tree. Inside it job control is off, so the time limit shares that group
    # and `kill 0` ends it: at the limit, or when the command exits by itself.
    set -m
    (
      set +m
      ( sleep "$ttl"; echo "crew-site: stopped at the ${ttl}s time limit"; rm -f "$d/pid"; kill -TERM 0 ) &
      bash -c "$cmd"
      echo "crew-site: the command exited with $?"
      rm -f "$d/pid"
      kill -TERM 0
    ) >"$d/log" 2>&1 &
    echo $! >"$d/pid"
    # Out of the job table: this shell waits on, and would report the job's end.
    disown
    wait_ready
    ;;
  status)
    if own_alive; then
      if answers; then echo ready; else echo starting; fi
    elif answers; then echo external
    else echo stopped
    fi
    ;;
  stop)
    if ! own_alive; then
      if answers; then echo external; else echo stopped; fi
      exit 0
    fi
    kill -TERM -- "-$p" 2>/dev/null
    for ((i = 0; i < 60; i++)); do kill -0 -- "-$p" 2>/dev/null || break; sleep 1; done
    if own_alive; then echo still-running; else echo stopped; fi
    ;;
esac
