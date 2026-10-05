#!/usr/bin/env bash
# plan-guard.sh: in plan mode, a dispatch of a crew worker that edits files is
# refused; the orchestrator, read-only workers, agents not on crew's roster, and every
# other permission mode pass. Fails open on anything it can't read.
#
# The real agent files decide the shipped verdicts (backend blocks, incident-triage
# passes); a fixture agents dir (CREW_AGENTS_DIR) exercises the frontmatter
# parser on shapes the shipped agents don't all carry.
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"

# payload_dispatch <subagent_type> <permission_mode> — a PreToolUse(Agent)
# payload. Pass "" to omit either field.
payload_dispatch() {
  jq -nc --arg s "$1" --arg m "$2" \
    '{hook_event_name: "PreToolUse", tool_name: "Agent", tool_use_id: "tu_1",
      tool_input: ({description: "Implement step 3", prompt: "…"}
                   + (if $s != "" then {subagent_type: $s} else {} end))}
     + (if $m != "" then {permission_mode: $m} else {} end)'
}

hook=plan-guard.sh
msg="plan mode"

# --- Shipped agents: the writers wait, the readers and the orchestrator run ----
for w in backend frontend unit-tests e2e generalist; do
  assert_block "plan mode refuses crew:$w (edits files)" "$hook" "$(payload_dispatch "crew:$w" plan)" "$msg"
done
run_hook "$hook" "$(payload_dispatch crew:backend plan)"
if [[ "$_stderr" == *"crew:backend"* ]]; then _pass; else _fail "refusal should name the worker (got: $_stderr)"; fi
for w in incident-triage visual-review debt-scout; do
  assert_allow "plan mode lets crew:$w through (no Edit/Write)" "$hook" "$(payload_dispatch "crew:$w" plan)"
done
assert_allow "plan mode lets crew:lead through (owns git; it plans there)" "$hook" "$(payload_dispatch crew:lead plan)"

# --- Every other mode is not this guard's business ------------------------------
for m in default acceptEdits auto dontAsk bypassPermissions; do
  assert_allow "crew:backend passes in $m" "$hook" "$(payload_dispatch crew:backend "$m")"
done
assert_allow "no permission_mode -> allow" "$hook" "$(payload_dispatch crew:backend "")"

# --- Only crew dispatches -------------------------------------------------------------
assert_allow "built-in Explore passes in plan mode" "$hook" "$(payload_dispatch Explore plan)"
assert_allow "general-purpose passes in plan mode" "$hook" "$(payload_dispatch general-purpose plan)"
assert_allow "an unnamespaced 'backend' is not a crew dispatch" "$hook" "$(payload_dispatch backend plan)"
assert_allow "a bare 'crew:' prefix is not a dispatch" "$hook" "$(payload_dispatch crew: plan)"
assert_allow "an unknown crew worker fails open (it won't launch anyway)" "$hook" "$(payload_dispatch crew:nobody plan)"
assert_allow "a worker name that is not a file name is not ours" "$hook" "$(payload_dispatch 'crew:../agents/backend' plan)"
assert_allow "no subagent_type (not a dispatch) -> allow" "$hook" "$(payload_dispatch "" plan)"
assert_allow "unparseable payload -> fail open" "$hook" 'not json'
# A "plan" that is not the permission mode must not trip the fast path into a block.
assert_allow "the word plan elsewhere in the payload is not plan mode" "$hook" \
  "$(jq -nc '{tool_name: "Agent", permission_mode: "acceptEdits", tool_input: {subagent_type: "crew:backend", prompt: "write the plan"}}')"

# --- Frontmatter parser, on fixture agents ------------------------------------------
fx="$(make_tree \
  'agents/blocklist.md:---
name: blocklist
tools:
  - Read
  - Write
owns-git: false
---
Body.' \
  'agents/reader.md:---
name: reader
tools: Read, Grep, Glob, Bash, mcp__editor
owns-git: false
---
tools: Edit' \
  'agents/owner.md:---
name: owner
tools: Read, Edit, Write, Bash
owns-git: true
---
Body.' \
  'agents/nofm.md:tools: Edit
No frontmatter at all.' \
  'agents/spaced.md:---
name: spaced
tools:   Read ,  Edit  , Bash   # trailing comment
owns-git:   false
---' \
  'agents/lastcomment.md:---
name: lastcomment
tools: Read, Bash, Edit  # scoped later
owns-git: false
---' \
  'agents/ownercomment.md:---
name: ownercomment
tools: Read, Edit, Write, Bash
owns-git: true  # sole git owner
---' \
  'agents/blockcomment.md:---
name: blockcomment
tools:  # granted below
  - Read
  - Write
owns-git: false
---' \
  'agents/blockblank.md:---
name: blockblank
tools:
  - Read

  - Edit
owns-git: false
---' \
  'agents/blockitemcomment.md:---
name: blockitemcomment
tools:
  - Read
  - Edit  # trailing
owns-git: false
---' \
  'agents/blockcommentline.md:---
name: blockcommentline
tools:
  - Read
  # note between the items
  - Edit
owns-git: false
---' \
  'agents/hrbody.md:Prose first, so this file has no frontmatter.

---

tools: Edit' \
  'agents/editscoped.md:---
name: editscoped
tools: Read, Edit(src/**), Bash
owns-git: false
---' \
  'agents/notfirst.md:
---
name: notfirst
tools: Read, Edit
owns-git: false
---')"
export CREW_AGENTS_DIR="$fx/agents"
assert_block "block-list tools: with Write is refused" "$hook" "$(payload_dispatch crew:blocklist plan)" "$msg"
assert_allow "a tools: line in the prose body is not a grant" "$hook" "$(payload_dispatch crew:reader plan)"
assert_allow "an entry merely containing 'Edit' (mcp__editor) is not Edit" "$hook" "$(payload_dispatch crew:reader plan)"
assert_allow "owns-git: true passes with editing tools" "$hook" "$(payload_dispatch crew:owner plan)"
assert_allow "a file with no frontmatter grants nothing" "$hook" "$(payload_dispatch crew:nofm plan)"
assert_block "spacing and a trailing comment don't hide Edit" "$hook" "$(payload_dispatch crew:spaced plan)" "$msg"
# YAML comments: validator §13 strips them, so this reader must too, on both sides.
assert_block "a comment after the LAST entry doesn't hide Edit" "$hook" "$(payload_dispatch crew:lastcomment plan)" "$msg"
assert_allow "a comment on owns-git: true still reads as the owner (must not fail closed)" "$hook" "$(payload_dispatch crew:ownercomment plan)"
assert_block "a comment on the bare tools: line still opens the block list" "$hook" "$(payload_dispatch crew:blockcomment plan)" "$msg"
assert_block "a blank line inside a block list doesn't end it" "$hook" "$(payload_dispatch crew:blockblank plan)" "$msg"
assert_block "a comment on a block-list item doesn't hide Edit" "$hook" "$(payload_dispatch crew:blockitemcomment plan)" "$msg"
assert_block "a comment-only line inside a block list doesn't end it" "$hook" "$(payload_dispatch crew:blockcommentline plan)" "$msg"
# Frontmatter opens on line 1 or not at all: a later `---` is a markdown rule.
assert_allow "a --- rule in a body with no frontmatter grants nothing" "$hook" "$(payload_dispatch crew:hrbody plan)"
assert_allow "a --- that is not on line 1 does not open frontmatter" "$hook" "$(payload_dispatch crew:notfirst plan)"
# A scoped grant is still the editing tool.
assert_block "Edit(src/**) is still Edit" "$hook" "$(payload_dispatch crew:editscoped plan)" "$msg"
unset CREW_AGENTS_DIR

finish
