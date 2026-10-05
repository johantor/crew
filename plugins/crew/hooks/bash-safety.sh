#!/usr/bin/env bash
# PreToolUse(Bash) guard. Blocks destructive commands and raw/streaming reads
# that bypass context discipline, and keeps crew's workers out of git.
#
# The command-shape patterns and the floor they enforce live in
# hooks/lib/guard-lib.sh. What stays here is crew's own policy: which agents may
# run git, and what the messages tell them to do instead.
#
# Fails closed: a guard that can't read its input must block, not pass the
# command through uninspected. jq is a documented dependency.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck source=plugins/crew/hooks/lib/guard-lib.sh
# shellcheck disable=SC1090,SC1091
if ! . "$_lib" 2>/dev/null; then
  echo "Blocked: bash-safety could not load its guard library ($_lib)." >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: bash-safety needs jq to inspect commands." >&2
  exit 2
fi

guard_read_payload
# The command is the untrusted field (arbitrary text, possibly containing the
# separator byte); agent_type is the harness-controlled one. See guard_jq2.
if ! guard_jq2 '.tool_input.command // ""' '.agent_type // ""'; then
  echo "Blocked: bash-safety could not parse the hook payload." >&2
  exit 2
fi
guard_agent_type
guard_normalize "$guard_untrusted"

# The floor, in this order. Destructive ops, pagers and `tail -f` are refused for
# everyone; the watch/dev/serve, `cat` and file-write blocks are scoped to agent
# sessions, since the
# user's own session may legitimately run a dev server, and is not write-guarded
# on the Edit|Write path either. The file-write block lets any agent run a plain
# `git mv`.
guard_block_destructive
[ -n "$agent_type" ] && guard_block_watch_commands
guard_block_raw_reads
[ -n "$agent_type" ] && guard_block_cat
[ -n "$agent_type" ] && guard_block_file_writes

# Workers run no git but a plain `git mv` -- lead is the sole git owner (see
# AGENTS.md, "How the crew works"). A rename lands in lead's commit, where it
# is reviewed. visual-review, incident-triage and debt-scout carry no Bash tool, so they need no
# entry.
# crew-roster: no-git -- every Bash-capable agent that doesn't own git belongs in
# the arm below; validator §9 keeps it in lockstep with the agents' frontmatter
# `owns-git`, and parses exactly this shape: the marker, the `case` header, then
# the `a|b|c)` arm on the very next line.
case "$agent_type" in
  backend|frontend|unit-tests|e2e|generalist)
    if ! guard_is_plain_git_mv && [[ $guard_cmd =~ $GUARD_RE_GIT_AT_CMD ]]; then
      echo "Blocked: ${agent_type} runs no git but a plain \`git mv <from> <to>\`, alone in the command, with relative paths — lead owns branching and commits. Return your result; lead commits verified steps." >&2
      exit 2
    fi ;;
esac

# Any other agent (lead, an agent not on crew's roster) must not commit onto a
# protected base branch. Scoped via agent_type, so a normal main session (no
# agent_type) is never intercepted.
guard_block_protected_branch_commit "$agent_type" \
  "Work on a feature branch (lead owns branching)."

exit 0
