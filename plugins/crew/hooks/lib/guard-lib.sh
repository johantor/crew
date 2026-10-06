#!/usr/bin/env bash
# Shared runtime for crew's hook guards: payload plumbing, the command-shape
# patterns the Bash guard enforces, and per-session state files.
#
# Sourced, never executed, and wired in no hooks.json -- validator §6 wires only
# the top-level hooks/*.sh entry points.
#
# Two rules shape everything below.
#
# 1. No forks on the hot path -- PreToolUse(Bash) runs before *every* Bash tool
#    call. Matching uses bash's own =~ and parameter expansion, and the single
#    `jq` that parses the payload is the only child a guard spawns. Patterns stay
#    POSIX (`[[:space:]]`, never the GNU-only `\s`) for BSD/macOS regcomp.
# 2. The caller owns the failure posture: security guards source this file
#    fail-closed, context/advisory hooks fail-open. The guard_block_* helpers are
#    the exception -- they exist to block.

# shellcheck disable=SC2034
# ^ GUARD_* and guard_* are this library's public surface. shellcheck cannot
#   follow a `source` whose path is built at runtime, so it sees them as unused.

# Idempotent: two hooks in one process (or a re-source) must not redefine state.
# A full `if` rather than `[ ... ] && return`, whose non-zero status on the first
# load would trap a caller running under `set -e`.
if [ -n "${GUARD_LIB_VERSION:-}" ]; then return 0; fi
GUARD_LIB_VERSION=1

# ------------------------------------------------------------------ constants

# Branches no agent may commit onto. One list, so the two guards cannot disagree.
GUARD_PROTECTED_BRANCHES='main|master|develop'

# read-guard's context-hygiene limits: raw reads above this size are refused
# unless the call carries an explicit line bound no larger than the cap.
GUARD_READ_MAX_BYTES=65536
GUARD_READ_MAX_BOUNDED_LINES=2000

# How long a per-session state file stays interesting. Swept opportunistically in
# guard_state_path, so the files do not accumulate forever.
GUARD_STATE_TTL_MINUTES=1440

# Record separator used to join fields out of a single jq pass.
GUARD_RS=$'\x1e'

# ------------------------------------------------------------------- payload

# guard_read_payload -- read all of stdin into $guard_payload without forking.
# `read -d ''` stops only at a NUL, which JSON never contains, so this consumes
# the whole payload; its non-zero return at EOF is the normal case.
guard_read_payload() {
  guard_payload=''
  IFS= read -r -d '' guard_payload || :
}

# guard_jq2 <untrusted-expr> <trusted-expr>
#   Pulls two fields out of $guard_payload in ONE jq pass and splits them at the
#   LAST separator, setting $guard_untrusted and $guard_trusted. Non-zero when
#   the payload is not valid JSON -- the caller decides what that means (block
#   for a security guard, exit 0 for an advisor).
#
#   Argument order is load-bearing: the untrusted field goes FIRST because it may
#   itself contain the separator byte, and the trusted one (a small
#   harness-controlled value like `agent_type`) anchors the split from the right.
#   See AGENTS.md, "Recurring review findings". Joined with `-j` rather than
#   @tsv, which would escape newlines and tabs and corrupt the command text.
guard_jq2() {
  local _fields
  _fields="$(jq -j --arg rs "$GUARD_RS" "($1) + \$rs + ($2)" <<<"$guard_payload" 2>/dev/null)" || return 1
  guard_untrusted="${_fields%"$GUARD_RS"*}"
  guard_trusted="${_fields##*"$GUARD_RS"}"
}

# guard_agent_type -- sets $agent_type from the trusted field. Crew's agents call
# tools as `crew:backend`; the rosters hold bare names, so only that prefix is
# dropped. Any other agent, a project's own bare `backend` included, gets an
# `ext:` prefix: still an agent session, never on a roster.
guard_agent_type() {
  case $guard_trusted in
    crew:*) agent_type="${guard_trusted#crew:}" ;;
    *) agent_type="${guard_trusted:+ext:$guard_trusted}" ;;
  esac
}

# guard_normalize <cmd> -- sets $guard_cmd as one line, every newline flattened
# to a space, so a multi-line command cannot slip a clause past the single-line
# patterns below. The text as typed is kept in $guard_cmd_raw for the one pattern
# that must see a line start, GUARD_RE_GIT_MV -- an allowance, where a newline
# read as a separator cannot refuse anything. A backslash-newline is joined there
# as bash joins it, so `git mv \` + newline + `-f a b` still shows its `-f`.
#
# KNOWN GAP, deliberately left open: flattening welds a later line onto the
# previous command's operands, so a command-position anchor sees only the first
# command. Separating on the newline instead needs to tell data from syntax and
# was tried three ways in #226. See AGENTS.md, "The Bash guards are floors, not
# sandboxes".
guard_normalize() { guard_cmd_raw="${1//\\$'\n'/ }"; guard_cmd="${1//$'\n'/ }"; }

# ------------------------------------------------- command-shape patterns

# Assembled once at source time. Patterns expect the normalized command in
# $guard_cmd unless noted otherwise; GUARD_RE_GIT_MV reads $guard_cmd_raw.

_g_flag='-[^[:space:]]*'                                     # any single flag token
_g_word='[^[:space:];|&<>]+'                                 # any token within one command
_g_rec='(-[A-Za-z]*[rR][A-Za-z]*|--recursive)'               # token containing recursive
_g_frc='(-[A-Za-z]*f[A-Za-z]*|--force)'                      # token containing force
_g_comb='-[A-Za-z]*([rR][A-Za-z]*f|f[A-Za-z]*[rR])[A-Za-z]*'  # both in one token

# Recursive+force rm of /, ~ or * -- flags combined in either order (-rf, -fr) or
# separate/long (-r -f, --recursive --force), with other flag tokens and
# arguments (including `--`) before the dangerous target. `\b` is a backspace in
# ERE, so `rm` is anchored on a separator rather than a word boundary. Any target
# that STARTS with `/`, `~` or `*` is refused, absolute build dirs included: a
# narrower match was tried in #264 and every version let a root-wide spelling
# through (`/*/`, `/tmp/../*`). Out-of-tree cleanup uses `rm -r` without `-f`.
_g_rm_rf="rm[[:space:]]+(${_g_flag}[[:space:]]+)*(${_g_comb}|${_g_rec}[[:space:]]+(${_g_flag}[[:space:]]+)*${_g_frc}|${_g_frc}[[:space:]]+(${_g_flag}[[:space:]]+)*${_g_rec})([[:space:]]+${_g_word})*"'[[:space:]]+(/|~|\*)'

# The rest of the destructive set: force-push via --force or short -f (but not
# the safe --force-with-lease / --force-if-includes -- `-[A-Za-z]*f` cannot cross
# their second dash); a redirect into `.env`; a redirect or removal aimed inside
# the repository's own `.git/`. `\|?` after every redirect operator covers `>|`,
# the noclobber override, without which its target hides behind the `|` and the
# redirect reads as targetless.
_g_dotgit='\.git/'
GUARD_RE_DESTRUCTIVE="${_g_rm_rf}"'|git[[:space:]]+push[^;&|]*[[:space:]](--force([^-]|$)|-[A-Za-z]*f)|>>?\|?[[:space:]]*\.env|>>?\|?[^|;&]*'"${_g_dotgit}"'|(^|[[:space:];|&(])rm[[:space:]][^|;&]*'"${_g_dotgit}"

# A command position: start of line, or just after a separator. guard_normalize
# flattens a newline to a space rather than a separator, so a later line does NOT
# reach this anchor -- see its comment, and AGENTS.md "The Bash guards are floors,
# not sandboxes".
_g_cmdpos='(^|[;&|][&|]?[[:space:]]*)'
# Prefixes that must not smuggle a command past that anchor: leading env
# assignments, `env`, `command`.
_g_pfx='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|env[[:space:]]+|command[[:space:]]+)*'

# Any git invocation at a command position (for the workers' no-git check).
GUARD_RE_GIT_AT_CMD="${_g_cmdpos}${_g_pfx}"'git([[:space:]]|$)'
# git global flags before a subcommand (`git -c k=v commit`, `git -C dir mv`): a
# flag token, optionally followed by its value token.
_g_gitopt='(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*'
GUARD_RE_GIT_COMMIT="${_g_cmdpos}${_g_pfx}"'git[[:space:]]+'"${_g_gitopt}"'commit([[:space:]]|$)'
# The whole command is `git commit …`, `git -C <dir> commit …` or
# `cd <dir> && git commit …`, with a plain <dir> (no leading `-`) and no
# separator, substitution, redirect, escape or newline after it. Matched against
# $guard_cmd_raw; <dir> is group 2 or 3, empty for a plain commit.
_g_litdir='([A-Za-z0-9._/][A-Za-z0-9._/-]*)'
_g_plain_tail=$'([[:blank:]][^;&|`$()<>\\\\\n]*)?$'
GUARD_RE_COMMIT_IN_DIR='^[[:blank:]]*(git[[:blank:]]+-C[[:blank:]]+'"$_g_litdir"'[[:blank:]]+commit|cd[[:blank:]]+'"$_g_litdir"'[[:blank:]]*&&[[:blank:]]*git[[:blank:]]+commit|git[[:blank:]]+commit)'"$_g_plain_tail"
# `git mv` at a command position, with at least one operand after it. Alone among
# the patterns it is matched against $guard_cmd_raw, and a line start counts as a
# command position. It can afford to: the match is an ALLOWANCE (the token is
# masked so the generic write check does not read it as `mv`), so a newline that
# is data rather than syntax can at worst wave through a `git mv` sitting inside
# a string -- never refuse ordinary work, which is what the blocking patterns
# risk if they separate on newlines (see guard_normalize). Only blanks may sit
# between `git`, its global flags and `mv`: `git` on one line and `mv a b` on the
# next is two commands, the second a bare `mv`, and stays refused. Matched ONLY
# here, never at an arbitrary word boundary: `find -exec git mv` and a subshell
# `(git mv ...)` fall through to the generic write check and are refused, which
# is the failure direction a guard wants.
_g_nl=$'\n'
_g_linepos="(^|[;&|][&|]?[[:space:]]*|${_g_nl}[[:blank:]]*)"
_g_gitopt_bl='(-[^[:space:]]+[[:blank:]]+([^-[:space:]][^[:space:]]*[[:blank:]]+)?)*'
GUARD_RE_GIT_MV="${_g_linepos}${_g_pfx}"'git[[:blank:]]+'"${_g_gitopt_bl}"'mv[[:blank:]]'
# A force flag among `git mv`'s operands: `-f`, bundled (`-kf`, `-fk`) or long.
GUARD_RE_GIT_MV_FORCE="(^|[[:space:]])${_g_frc}"'([[:space:]]|$)'

# Watch/dev/serve commands never terminate, so an agent turn that launches one
# hangs until its maxTurns/timeout. `--watch` matches the bare flag only, not
# `--watch=false` (the disable spelling); `vite build` stays allowed.
# Grouped per ecosystem; every stack the crew resolves has its own.
_g_watch_web='dotnet[[:space:]]+watch([[:space:]]|$)|(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(dev|start|serve|watch)([[:space:]]|$)|vite([[:space:]]+(dev|serve|preview)([[:space:]]|$)|[[:space:]]+-|[[:space:]]*($|[;&|]))|(next|nuxt)[[:space:]]+dev([[:space:]]|$)|ng[[:space:]]+serve([[:space:]]|$)|nodemon([[:space:]]|$)|webpack[[:space:]]+serve([[:space:]]|$)|webpack-dev-server([[:space:]]|$)'
# Python: the servers block with or without --reload, so they match bare;
# `runserver` needs its script prefix, being too generic on its own.
_g_watch_py='(uvicorn|hypercorn|gunicorn|daphne|watchmedo|ptw|pytest-watch|http\.server)([[:space:]]|$)|fastapi[[:space:]]+(dev|run)([[:space:]]|$)|(([^[:space:]]*/)?manage\.py|django-admin|django)[[:space:]]+runserver([[:space:]]|$)|flask([[:space:]]+--[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+run([[:space:]]|$)'
# Go/Rust: live-reload runners, plus `cargo watch`, a subcommand spelling the
# bare `--watch` alternative below does not reach.
_g_watch_gors='(air|reflex|gow)([[:space:]]|$)|cargo([[:space:]]+[-+][^[:space:]]+)*[[:space:]]+watch([[:space:]]|$)|trunk[[:space:]]+serve([[:space:]]|$)'
# JVM: the run goals and Gradle's continuous build. Tasks may be module-qualified
# (`:service:bootRun`). `-t` is matched only in the Gradle arm -- under Maven it
# is --toolchains.
_g_watch_jvm='(mvn|([^[:space:]]*/)?mvnw)[[:space:]]+([^[:space:]]+[[:space:]]+)*(spring-boot:run|quarkus:dev|jetty:run|tomcat7:run)([[:space:]]|$)|(gradle|([^[:space:]]*/)?gradlew)[[:space:]]+([^[:space:]]+[[:space:]]+)*((:[A-Za-z0-9_.:-]*)?(bootRun|quarkusDev)|--continuous|-t)([[:space:]]|$)'
# Tool-agnostic re-runners: these wrap ANY command and never terminate, so they
# belong to no single stack. `watch` is coreutils'; the rest are file watchers.
_g_watch_any='(watch|watchexec|entr|fswatch|nodemon)([[:space:]]|$)'
_g_watch="${_g_watch_web}|${_g_watch_py}|${_g_watch_gors}|${_g_watch_jvm}|${_g_watch_any}"
GUARD_RE_WATCH="${_g_cmdpos}${_g_pfx}"'((npx|bunx|(uv|poetry|pdm|pipenv)([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+run([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*|([^[:space:]]*/)?python[0-9.]*[[:space:]]+-m|([^[:space:]]*/)?python[0-9.]*)[[:space:]]+)*(([^[:space:]]*/)?('"${_g_watch}"'))|--watch([[:space:]]|$)'

# Raw/streaming reads: a `cat` of a whole file, a pager, a `tail -f`. Such a read
# reaches no PreToolUse(Read) hook, so read-guard's size bound never applies.
#
# A HABIT REDIRECT, not a boundary: it catches the spelling a session reaches for
# and names `Read` instead. `grep . f` and a dozen others dump the same file and
# are deliberately allowed, so a missed read costs nothing while a wrongly
# refused one costs a turn. Hence one line, and a pipe or ANY redirect ends the
# match. Before widening this, read AGENTS.md, "The Bash guards are floors, not
# sandboxes" -- #226 widened it and reverted.
#
# ${_g_pfx} stops `env cat f`, `command cat f` and `FOO=1 cat f` walking a read
# past the anchor, as the git block already does.
GUARD_RE_PAGER="${_g_cmdpos}${_g_pfx}"'(less|more)[[:space:]]+'
GUARD_RE_STREAM="${_g_cmdpos}${_g_pfx}"'tail[[:space:]]+-f([[:space:]]|$)'
GUARD_RE_CAT="${_g_cmdpos}${_g_pfx}"'cat[[:space:]]+[^|><;&]+([[:space:]]*($|[;&]|&&|\|\|))'

# Bash can mutate a file without any Edit|Write hook seeing it: a redirect, a
# `tee`, an in-place stream edit, a copy into the tree. Such a write skips every
# PreToolUse(Edit|Write) guard (write lanes, write allowlists) and every
# PostToolUse(Edit|Write) one (formatting), so for an agent session it is a way
# around a guard rather than a matter of style.
#
# Two patterns, enforced by guard_block_file_writes. A file-mutating command is
# matched at any word boundary rather than only at a command position, so a
# `find ... -exec` form is caught too. The stream editors need their in-place
# flag: short spellings bundle it (`-pi`, `-i.bak`), the long one spells it out,
# and `--expression` cannot match the short form because [A-Za-z] does not cross
# the second dash. Destinations are deliberately not analysed: `cp`/`mv` are
# refused outright, one rule instead of an operand table per command. The one
# carve-out is a plain `git mv`, for any agent -- a rename, not a write; see
# guard_block_file_writes.
_g_anypos='(^|[[:space:];|&(])'
GUARD_RE_WRITE_CMD="${_g_anypos}"'(tee|patch|cp|mv)([[:space:]]|$)'"|${_g_anypos}"'(sed|perl|ruby|awk|gawk)[[:space:]]+([^;|&]*[[:space:]])?(-[A-Za-z]*i([[:space:]]|[.=]|$)|--in-place)'
# A redirect and its target, glued or spaced (`>file`, `>> file`, `2>`, `&>`, and
# the noclobber `>|`). The target excludes `&`, so an fd dup (`2>&1`) captures
# nothing and reads as the exempt sink it is. `<` is absent by design: an input
# redirect writes nothing.
GUARD_RE_REDIRECT='([0-9]*|&)>>?\|?[[:space:]]*([^[:space:];|&<>]*)'

# --------------------------------------------------------- blocking helpers
#
# The floor, as functions: each inspects $guard_cmd and exits 2 with the message
# the agent sees. Order and wording are part of the contract.

guard_block_destructive() {
  if [[ $guard_cmd =~ $GUARD_RE_DESTRUCTIVE ]]; then
    echo "Blocked: unsafe command." >&2
    exit 2
  fi
}

guard_block_watch_commands() {
  if [[ $guard_cmd =~ $GUARD_RE_WATCH ]]; then
    echo "Blocked: watch/dev/serve commands never terminate. Use the project's one-shot build/test command instead." >&2
    exit 2
  fi
}

guard_block_raw_reads() {
  if [[ $guard_cmd =~ $GUARD_RE_PAGER ]]; then
    echo "Blocked: interactive raw reads are disallowed — a raw Bash read reaches no Read hook, so read-guard's size bound never applies. Use the Read tool for a file in the checkout, or targeted grep/rg/jq/scripted summaries." >&2
    exit 2
  fi
  if [[ $guard_cmd =~ $GUARD_RE_STREAM ]]; then
    echo "Blocked: streaming raw output is disallowed — it never ends, and a raw Bash read reaches no Read hook either. Capture/filter and surface only the needed result." >&2
    exit 2
  fi
}

# A habit redirect for agents; callers scope it to agent sessions, since the
# operator reading a file with `cat` bypasses nothing they rely on.
guard_block_cat() {
  if [[ $guard_cmd =~ $GUARD_RE_CAT ]]; then
    echo "Blocked: unbounded cat reads are disallowed — a raw Bash read reaches no Read hook, so read-guard's size bound never applies. Use the Read tool for a file in the checkout, or pipe/filter with grep/rg/jq." >&2
    exit 2
  fi
}

# ------------------------------------------------- file writes through Bash
#
# The two patterns above, enforced. A floor, not a sandbox: an interpreter a
# build runs can still write files, and a write hidden inside a quoted `bash -c`
# string is not read as one. What this closes is the routine path -- editing
# through Bash instead of Edit/Write.

# Placeholder that replaces a quoted span. Deliberately not an exempt sink: a
# quoted target (`> "src/x.cs"`) must still read as a write.
GUARD_QUOTED='@quoted@'

# guard_write_sink_exempt <target> -- true for a target a write may reach without
# escaping the Edit|Write guards: the null/std streams, an fd dup (which captures
# as the empty string), the temp locations agents use for scratch output, and an
# absolute path outside the project (guard_outside_project).
# Anything else counts as a path in the checkout, relative paths included:
# resolving one costs a fork, and a guard that guesses permissively is the hole
# it exists to close. `-` is NOT exempt -- `> -` writes a file named `-`.
#
# The /dev list is enumerated rather than globbed: `/dev/*` would also exempt
# every device node, and `/dev/tcp/<host>/<port>`, which bash turns into a socket
# write.
guard_write_sink_exempt() {
  case "$1" in
    '') return 0 ;;
    /dev/null|/dev/stdout|/dev/stderr|/dev/tty) return 0 ;;
    /dev/fd/*|/proc/self/fd/*) return 0 ;;
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) return 0 ;;
    "${TMPDIR:-/tmp}"/*) return 0 ;;
    /dev/*|/proc/*) return 1 ;;
  esac
  guard_outside_project "$1"
}

# guard_outside_project <path> -- true for an absolute path outside
# $CLAUDE_PROJECT_DIR, such as an out-of-tree build root (#240): the lane and
# format hooks guard only the checkout. An allow-list, so it fails closed: the
# path must be absolute and every segment plain (`[A-Za-z0-9_-][A-Za-z0-9._-]*`),
# so `$VAR`, a backtick, a glob, `.`, `..`, `//` or a hidden segment counts as
# inside. Parsing what bash would expand was tried in #264 and leaked. On Windows
# shells `C:\x`, `C:/x` and Git Bash `/c/x` compare equal; elsewhere they are
# relative names. The compare ignores case, so a mismatch errs toward "inside".
# Unquoted targets only: a quoted one is masked before it gets here.
guard_outside_project() {
  local p root inside=1 had_nocase=0
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] || return 1
  _guard_posix_path "$1"; p="$_guard_path"
  _guard_posix_path "$CLAUDE_PROJECT_DIR"; root="${_guard_path%/}"
  [[ $p =~ ^(/[A-Za-z0-9_-][A-Za-z0-9._-]*)+$ ]] || return 1
  [ -n "$root" ] || return 1
  shopt -q nocasematch && had_nocase=1
  shopt -s nocasematch
  [[ $p == "$root" || $p == "$root"/* ]] || inside=0
  [ "$had_nocase" -eq 1 ] || shopt -u nocasematch
  [ "$inside" -eq 0 ]
}

# _guard_posix_path <path> -- sets $_guard_path. On a Windows shell only,
# backslashes become slashes and `X:/` becomes `/X/`; a drive-relative `X:foo`
# stays relative. Elsewhere the path is unchanged: there `D:/x` and `a\b` are
# relative names. CREW_OSTYPE is a test override. Assigns rather than echoing,
# so a caller pays no `$(...)` fork.
_guard_posix_path() {
  _guard_path="$1"
  case "${CREW_OSTYPE:-${OSTYPE:-}}" in msys*|cygwin*|win*) ;; *) return 0 ;; esac
  _guard_path="${_guard_path//\\//}"
  if [[ $_guard_path =~ ^([A-Za-z]):(/.*)$ ]]; then
    _guard_path="/${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  fi
}

# guard_mask_quotes <cmd> -- sets $guard_masked to <cmd> with every single- or
# double-quoted span replaced by GUARD_QUOTED. One substitution, two jobs: a `>`
# inside a string (`grep "a>b" f`, `awk '$3 > 5'`) stops looking like a redirect,
# and a quoted path still leaves a non-exempt target behind, so quoting cannot
# hide a write. Quote types are tracked properly: an apostrophe inside `"..."`
# opens nothing.
#
# An unterminated quote drops the remainder, and a `\"` inside a double-quoted
# span ends it here where bash would keep going. Both mis-parses close a span
# EARLY, so the scan masks less than it should and over-detects: the failure
# direction is a refused command, never a write that slips through.
guard_mask_quotes() {
  local s="$1" out='' pre rest q sq dq
  while :; do
    case "$s" in
      *\'*|*\"*) ;;
      *) guard_masked="$out$s"; return 0 ;;
    esac
    # The shorter prefix marks the quote that comes first; a quote type that is
    # absent yields the whole string, so it always loses the comparison.
    sq="${s%%\'*}"; dq="${s%%\"*}"
    if [ "${#sq}" -lt "${#dq}" ]; then q=\'; pre="$sq"; else q='"'; pre="$dq"; fi
    out+="$pre$GUARD_QUOTED"
    rest="${s#"$pre$q"}"
    case "$rest" in
      *"$q"*) s="${rest#*"$q"}" ;;
      *) s='' ;;
    esac
  done
}

# guard_write_refuse <what> -- the one message both halves below report with.
guard_write_refuse() {
  echo "Blocked: $1 writes a file from Bash, which reaches no Edit|Write hook — write lanes and formatting are wired to Edit/Write, so the write would land unguarded. Use Edit/Write for files in the checkout; send scratch output under /tmp." >&2
  exit 2
}

# A heredoc operator and its delimiter word, quotes still on (`<<'EOF'`, `<<-EOF`).
# A word must start like a name or a quote, so `$((1<<2))` opens no body.
GUARD_RE_HEREDOC='(^|[[:space:];|&])<<(-?)[[:space:]]*([A-Za-z_'"'"'"\\][^[:space:];|&<>()]*)'
GUARD_RE_HEREDOC_MASKED='(^|[[:space:];|&])<<-?[[:space:]]*[A-Za-z_@\\]'

# _guard_strip_heredocs <cmd> -- sets $_guard_noheredoc to <cmd> without heredoc
# bodies. A body is stdin data, so `<h3>` or "apply the patch" in a ticket draft
# is no write. Line by line, one body per operator line: a second body on the
# same line stays in and over-detects. Open gap: `bash <<EOF` runs its body, as
# `bash -c '…'` does (AGENTS.md, "The Bash guards are floors, not sandboxes").
_guard_strip_heredocs() {
  local line delim='' tabs='' out=''
  case "$1" in *'<<'*) ;; *) _guard_noheredoc="$1"; return 0 ;; esac
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$delim" ]; then
      [ -n "$tabs" ] && line="${line#"${line%%[!$'\t']*}"}"
      [ "$line" = "$delim" ] && delim=''
      continue
    fi
    out+="$line"$'\n'
    # The operator must be outside quotes; the delimiter comes from the raw line,
    # where a quoted one is still readable.
    guard_mask_quotes "$line"
    [[ $guard_masked =~ $GUARD_RE_HEREDOC_MASKED ]] || continue
    [[ $line =~ $GUARD_RE_HEREDOC ]] || continue
    tabs="${BASH_REMATCH[2]}"
    delim="${BASH_REMATCH[3]//[\'\"\\]/}"
  done <<<"$1"
  _guard_noheredoc="$out"
}

# Placeholder for a permitted `git mv` subcommand token. `mv` followed by `@`
# matches neither GUARD_RE_GIT_MV (which wants a blank after it) nor the generic
# write pattern, so the loop below terminates and the masked command keeps every
# other token where it was.
GUARD_GIT_MV_MASK='@gitmv@'

# guard_block_file_writes -- refuse a Bash command that edits a file in the
# checkout. Callers scope it to agent sessions: the operator's own session is not
# lane-guarded, so it has no guard to route around.
#
# `git mv` is the one carve-out, for every agent. It renames a tracked path and
# records the rename in the index; no bytes change, so there is nothing for a
# lane guard or a formatter to inspect, and the rename lands in a commit, where
# it is reviewed. Which agents may run git at all is the roster's policy, after
# the floor; guard_is_plain_git_mv is the one git a worker may run.
# `-f`/`--force` stays
# refused for everyone: it can clobber an existing destination, which IS a write.
#
# The loop reads $guard_cmd_raw, so a `git mv` on a later line is recognised (see
# GUARD_RE_GIT_MV). Each `git mv` is masked out, the masked text is flattened,
# and the generic check runs on that: an allowed `git mv a b` cannot carry a bare
# `mv c d` behind it, on the same line or the next. `${cmd/"$m"/...}` replaces
# the FIRST literal occurrence of the match, which is the match itself: a regex
# match is leftmost, and an identical earlier occurrence would itself have
# matched (the pattern reads no context beyond the separator it consumes), so at
# worst two identical `git mv`s swap places.
#
# The command check reads the raw command, so a quoted argument cannot hide a
# `sed -i`; the redirect scan reads the quote-masked copy, where a quoted `>` is
# no longer an operator. Both skip heredoc bodies (_guard_strip_heredocs).
guard_block_file_writes() {
  local cmd rest target what m ops
  _guard_strip_heredocs "$guard_cmd_raw"
  cmd="$_guard_noheredoc"
  while [[ $cmd =~ $GUARD_RE_GIT_MV ]]; do
    m="${BASH_REMATCH[0]}"
    # Operands up to the next separator or line end, quotes stripped so `'-f'`
    # still reads as the flag git would see. A filename that merely looks like a
    # force flag is refused too: the failure direction is a refused rename, never
    # a clobber. `$m` stays QUOTED inside every expansion below, as in the
    # redirect scan: unquoted it would be a glob, and a `*` or `[` in a flag
    # value (`git -C "*" mv`) or an operand would widen the match and mask what
    # follows.
    ops="${cmd#*"$m"}"; ops="${ops%%[;|&$'\n']*}"; ops="${ops//[\'\"]/}"
    if [[ $ops =~ $GUARD_RE_GIT_MV_FORCE ]]; then
      echo "Blocked: git mv -f/--force can overwrite an existing path, which is a write. Rename without it; if the destination exists, move or remove it as its own step first." >&2
      exit 2
    fi
    cmd="${cmd/"$m"/"${m%mv*}${GUARD_GIT_MV_MASK}${m##*mv}"}"
  done
  cmd="${cmd//$'\n'/ }"
  if [[ $cmd =~ $GUARD_RE_WRITE_CMD ]]; then
    what="${BASH_REMATCH[0]#[[:space:];|\&(]}"   # drop the separator it matched
    guard_write_refuse "${what%%[[:space:]]*}"
  fi
  case "$cmd" in *'>'*) ;; *) return 0 ;; esac
  guard_mask_quotes "$cmd"
  rest="$guard_masked"
  while [[ $rest =~ $GUARD_RE_REDIRECT ]]; do
    # Saved first: the exempt check runs its own `=~`, which resets BASH_REMATCH.
    m="${BASH_REMATCH[0]}"; target="${BASH_REMATCH[2]}"
    if ! guard_write_sink_exempt "$target"; then
      # Never report the mask back as if it were the path itself -- a target can
      # also merely contain it (`b"` in `echo "a \" > b" > f`).
      case "$target" in *"$GUARD_QUOTED"*) target='a quoted path' ;; esac
      guard_write_refuse "a redirect into $target"
    fi
    # Advance past this match. The interpolation stays QUOTED so a glob
    # metacharacter in the matched text (`> /tmp/out[1]`) stays literal and the
    # trim lands where the match ended; unquoted it would match nothing and loop
    # forever. Every match is at least one character, so this terminates.
    rest="${rest#*"$m"}"
  done
}

# guard_is_plain_git_mv -- true when the whole command, as typed, is one
# `git mv [-k|-n|-v] <operands>` with relative operands: no `-C`, no `cd`, no
# second command or line, no quoting, variable, glob or brace expansion, no
# absolute, `~` or `..` path. A worker may run exactly that, so a rename stays in
# the tree it was dispatched to. Open gap: a cwd the worker moved with an earlier
# `cd` call. (`]` leads each class so it is literal, `-` trails the first.)
_g_mvop='[^]/~[:space:];&|<>$`()"'"'"'\\*?[{}-][^][:space:];&|<>$`()"'"'"'\\*?[{}]*'
GUARD_RE_PLAIN_GIT_MV='^[[:blank:]]*git[[:blank:]]+mv([[:blank:]]+(-[knv]+|--dry-run|--verbose))*([[:blank:]]+'"${_g_mvop}"'){2,}[[:blank:]]*$'
guard_is_plain_git_mv() {
  [[ $guard_cmd_raw =~ $GUARD_RE_PLAIN_GIT_MV ]] && [[ $guard_cmd_raw != *..* ]]
}

# guard_block_protected_branch_commit <agent_type> <advice>
#   Backstop for any agent that reaches a `git commit`: refuse it on a protected
#   branch. Scoped by the caller to agent sessions, so a normal user session is
#   never intercepted. Forks only for a command that already looks like a commit.
#
#   The branch is read where the commit runs (#224): the payload's `cwd`, or the
#   literal <dir> of GUARD_RE_COMMIT_IN_DIR. Any other shape also checks the hook's
#   own directory, as before, so it is never weaker than that. See AGENTS.md,
#   "The Bash guards are floors, not sandboxes".
guard_block_protected_branch_commit() {
  local agent_type="$1" advice="$2" branch dir d also_here=1
  [ -n "$agent_type" ] || return 0
  [[ $guard_cmd =~ $GUARD_RE_GIT_COMMIT ]] || return 0
  dir="$(jq -r '.cwd // ""' <<<"$guard_payload" 2>/dev/null || true)"
  if [[ $guard_cmd_raw =~ $GUARD_RE_COMMIT_IN_DIR ]]; then
    also_here=''
    d="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    case "$d" in '') ;; /*) dir="$d" ;; *) dir="${dir:-.}/$d" ;; esac
  fi
  branch="$(git -C "${dir:-.}" branch --show-current 2>/dev/null || true)"
  if [ -n "$also_here" ] && ! [[ $branch =~ ^($GUARD_PROTECTED_BRANCHES)$ ]]; then
    branch="$(git branch --show-current 2>/dev/null || true)"
  fi
  if [[ $branch =~ ^($GUARD_PROTECTED_BRANCHES)$ ]]; then
    echo "Blocked: ${agent_type} may not commit on protected branch '$branch'. ${advice}" >&2
    exit 2
  fi
}

# ---------------------------------------------------------------- crew config
#
# Crew configuration lives in `.claude/crew.md` as YAML frontmatter, one key per
# slot. It is the only location: the `--local` file and the legacy `CLAUDE.md`
# block went in 5.0.0 (#248). Read by lane-guard (lanes) and format (the matrix).

# guard_config_load -- the frontmatter into $_cfg_text, once, in the PARENT
# shell (config_slot runs in `$(...)`, so a lazy load would be discarded). The
# body is prose and may quote an example block, so only the frontmatter counts.
guard_config_load() {
  local _cfg_raw="" _cfg_line _cfg_first=1
  _cfg_text=""
  [ -f .claude/crew.md ] || return 0
  IFS= read -r -d '' _cfg_raw < .claude/crew.md || :
  while IFS= read -r _cfg_line; do
    if [ "$_cfg_first" = 1 ]; then
      _cfg_first=0
      # No opening delimiter on line 1 means no frontmatter, so nothing is configured.
      [ "$_cfg_line" = "---" ] || break
      continue
    fi
    [ "$_cfg_line" = "---" ] && break
    _cfg_text+="$_cfg_line"$'\n'
  done <<<"$_cfg_raw"
}

# config_slot <frontmatter-key> -- a slot's scalar value. Missing file, missing
# slot, or the unset/none placeholders all mean "not configured" -> empty string.
config_slot() {
  local line v=""
  [ -n "${_cfg_text:-}" ] || return 0
  while IFS= read -r line; do
    # Only the key is a literal here; the trailing * is the glob. Slot names are
    # fixed strings, so a caller cannot turn this into a pattern.
    case "$line" in
      "$1:"*) v="${line#"$1:"}" ;;
      *) continue ;;
    esac
    v="${v#"${v%%[![:space:]]*}"}"       # trim leading whitespace
    # Unwrap quotes, then drop a ` #` comment: either left in place builds a lane
    # glob that matches nothing, which reads as "no lane" and widens the agent.
    case "$v" in
      '"'*) v="${v#\"}"; v="${v%%\"*}" ;;
      "'"*) v="${v#\'}"; v="${v%%\'*}" ;;
      *[[:space:]]'#'*) v="${v%%[[:space:]]#*}" ;;
    esac
    v="${v%"${v##*[![:space:]]}"}"       # trim trailing whitespace
    break
  done <<<"$_cfg_text"
  case "$v" in
    # The `unset` placeholder, empty, and any value starting with "none" (e.g.
    # "none (no e2e suite detected)") all mean not configured.
    unset|none|none[!A-Za-z0-9]*|'') return 0 ;;
    *) printf '%s' "$v" ;;
  esac
}

# config_block <frontmatter-key> -- the lines of a block scalar (`key: |`),
# indentation, blank lines and `#` comments dropped; a scalar value is not a
# block -> nothing.
config_block() {
  local line in_block=0
  [ -n "${_cfg_text:-}" ] || return 0
  while IFS= read -r line; do
    if [ "$in_block" = 0 ]; then
      case "$line" in
        "$1:"*) ;;
        *) continue ;;
      esac
      line="${line#"$1:"}"
      line="${line#"${line%%[![:space:]]*}"}"
      case "$line" in
        '|'|'|-'|'|+') in_block=1; continue ;;
        *) return 0 ;;
      esac
    fi
    case "$line" in
      '') continue ;;
      [![:space:]]*) break ;;
    esac
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
      ''|'#'*) continue ;;
    esac
    printf '%s\n' "$line"
  done <<<"$_cfg_text"
}

# ---------------------------------------------------------------- state files
#
# Advisory hooks (dispatch-denied) keep a tiny per-session counter.
# A non-zero return means "cannot count", never a reason to block.

# guard_state_path <dir> <name-prefix> <key-source> <tag>
#   Sets $guard_state_path to "<dir>/<prefix>.<hash>.<tag>", or returns non-zero
#   when <dir> is unusable or <key-source> is empty. <tag> is dropped unless it
#   is plainly filename-safe. cksum is POSIX (and present on BSD/macOS) and keeps
#   the name short however long a transcript path is.
#
#   A path that does not exist yet also triggers the TTL sweep below: at most one
#   `find` per agent instance per session, rather than one per tool call.
guard_state_path() {
  local dir="$1" prefix="$2" key_src="$3" tag="$4" key
  [ -n "$key_src" ] || return 1
  [ -d "$dir" ] && [ -w "$dir" ] || return 1
  case "$tag" in
    ''|*[!A-Za-z0-9_-]*) tag="state" ;;
  esac
  key="$(printf '%s' "$key_src" | cksum | tr -s ' \t' '--')"
  guard_state_path="$dir/$prefix.$key.$tag"
  # `-mmin` and `-delete` are extensions rather than POSIX `find`, but both GNU
  # and BSD/macOS find carry them. The sweep is best-effort anyway: errors are
  # swallowed and `|| :` keeps a failure off the caller's exit status, so a find
  # without them degrades to the files accumulating, never to a guard that stops
  # guarding.
  if [ ! -e "$guard_state_path" ]; then
    find "$dir" -maxdepth 1 -name "$prefix.*" -type f \
      -mmin "+$GUARD_STATE_TTL_MINUTES" -delete 2>/dev/null || :
  fi
  return 0
}

# guard_read_counter <file> -- sets $guard_count and $guard_stage from the file's
# first two whitespace-separated fields, normalising a missing file, a short line
# or anything non-numeric to zero. Assigns rather than echoing, so a caller pays
# no `$(...)` fork for two integers.
guard_read_counter() {
  guard_count=0 guard_stage=0
  if [ -f "$1" ]; then
    read -r guard_count guard_stage < "$1" 2>/dev/null || :
    case "$guard_count" in ''|*[!0-9]*) guard_count=0 ;; esac
    case "$guard_stage" in ''|*[!0-9]*) guard_stage=0 ;; esac
  fi
}
