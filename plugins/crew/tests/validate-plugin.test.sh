#!/usr/bin/env bash
# Self-tests for scripts/validate-plugin.sh: prove every section's guards bite.
# Each case builds a throwaway repo, breaks one thing, and asserts that guard's
# FAIL message. A per-section silent control (shared by that section's bites)
# proves the guard discriminates rather than firing unconditionally.
#
# Assert on the guard's message, not the exit code: a minimal fixture trips
# unrelated sections (e.g. §2's manifest keys), which would mask which fired.
# Pick a substring that appears ONLY in the FAIL text, never in an ok: line.
#
# Every section carries a fixture; see AGENTS.md, "Validating changes".
# shellcheck source=tests/hooks/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/hooks/lib.sh"

VALIDATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/validate-plugin.sh"
[ -f "$VALIDATOR" ] || { echo "FATAL: $VALIDATOR not found" >&2; exit 1; }

# new_repo -> echoes a throwaway git repo carrying a copy of the validator.
new_repo() {
  local d
  d="$(new_tmpdir)"
  git init -q "$d" || die "git init failed in $d"
  mkdir -p "$d/scripts" || die "mkdir failed in $d"
  cp "$VALIDATOR" "$d/scripts/validate-plugin.sh" || die "cp validator failed into $d"
  printf '%s' "$d"
}

# run_validator <dir> — stages the tree and runs the validator inside it,
# capturing merged stdout+stderr in _vout. The validator exits non-zero on a
# minimal fixture (unrelated scaffolding gaps), which is fine: the asserts key on
# the specific guard message, not the exit code. Not cached: only 17 of the 117
# assertions reuse an unchanged fixture (measured for #251), so a cache would
# add state to the harness for an 8% saving.
run_validator() {
  git -C "$1" add -A >/dev/null 2>&1
  _vout="$(cd "$1" && bash scripts/validate-plugin.sh 2>&1)" || true
}

assert_emits() {  # <label> <dir> <substr>
  run_validator "$2"
  if [[ "$_vout" == *"$3"* ]]; then _pass; else _fail "$1: validator did not emit '$3' — output: $_vout"; fi
}
assert_silent() { # <label> <dir> <substr>
  run_validator "$2"
  if [[ "$_vout" != *"$3"* ]]; then _pass; else _fail "$1: validator unexpectedly emitted '$3'"; fi
}

mk_manifest() { mkdir -p "$1/.claude-plugin"; printf '{"name":"%s","version":"%s"}\n' "$2" "$3" > "$1/.claude-plugin/plugin.json"; }
mk_changelog() { printf '## [%s]\n- note\n' "$2" > "$1/CHANGELOG.md"; }
# new_repo_foo -> new_repo plus a valid plugin foo 1.0.0 (manifest + changelog):
# the scaffold most cases start from, so §2 and §2h stay silent under them.
new_repo_foo() {
  local d
  d="$(new_repo)"
  mk_manifest "$d/plugins/foo" foo 1.0.0; mk_changelog "$d/plugins/foo" 1.0.0
  printf '%s' "$d"
}

# Raw-JSON writers for the shapes the two above can't express: a manifest missing
# a key, declaring component paths, or carrying a description; a marketplace.
mk_manifest_json() { mkdir -p "$1/.claude-plugin"; printf '%s\n' "$2" > "$1/.claude-plugin/plugin.json"; }
mk_marketplace()   { mkdir -p "$1/.claude-plugin"; printf '%s\n' "$2" > "$1/.claude-plugin/marketplace.json"; }

# mk_hook <plugin_dir> <filename> <body> — a valid, executable hook, so §3's two
# guards stay silent and the fixture isolates whichever section is under test.
mk_hook() {
  mkdir -p "$1/hooks"
  printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/hooks/$2"
  chmod +x "$1/hooks/$2"
}
# mk_lib <plugin_dir> <filename> <body> — a sourced library under hooks/lib/,
# left non-executable, which is the mode §3 requires of one.
mk_lib() {
  mkdir -p "$1/hooks/lib"
  printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/hooks/lib/$2"
  chmod -x "$1/hooks/lib/$2"
}
# mk_hooks_json <plugin_dir> <command-string> — wiring in §6's expected shape.
mk_hooks_json() {
  mkdir -p "$1/hooks"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s"}]}]}}\n' "$2" > "$1/hooks/hooks.json"
}
# Wiring commands, shared by §2e/§6. Single-quoted so the "${VAR}" text stays
# literal — it is JSON content here, not a shell expansion — and the \" pairs
# become real quotes when printf writes them.
# shellcheck disable=SC2016
wired_x='\"${CLAUDE_PLUGIN_ROOT}\"/hooks/x.sh'
# shellcheck disable=SC2016
wired_missing='\"${CLAUDE_PLUGIN_ROOT}\"/hooks/missing.sh'
# shellcheck disable=SC2016
wired_lib='\"${CLAUDE_PLUGIN_ROOT}\"/hooks/lib/guard-lib.sh'

# --- §2h: manifest version must match the newest CHANGELOG entry ---------------
d="$(new_repo)"; mk_manifest "$d/plugins/foo" foo 9.9.9; mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2h bites on version/changelog mismatch" "$d" "!= newest"
d="$(new_repo_foo)"
assert_silent "§2h silent when they match" "$d" "!= newest"

# --- §2g: an agent's skills: ref must resolve to a real skill -----------------
mk_agent() {  # <plugin_dir> <skill_ref>
  mkdir -p "$1/agents"
  printf -- '---\nname: bar\ndescription: d\nskills:\n  - %s\n---\nbody\n' "$2" > "$1/agents/bar.md"
}
d="$(new_repo_foo)"
mk_agent "$d/plugins/foo" nonexistent-skill
assert_emits "§2g bites on an unresolved skill ref" "$d" "does not resolve"
d="$(new_repo_foo)"
mkdir -p "$d/plugins/foo/skills/real"; printf -- '---\nname: real\ndescription: d\n---\n' > "$d/plugins/foo/skills/real/SKILL.md"
mk_agent "$d/plugins/foo" real
assert_silent "§2g silent when the skill exists" "$d" "does not resolve"

# --- §9: hook rosters must be in lockstep with agent owns-git/lane-guarded -----
mk_roster_agent() {  # <plugin_dir> <name> <tools> <owns-git> <lane-guarded>
  mkdir -p "$1/agents"
  printf -- '---\nname: %s\ndescription: d\ntools: %s\nowns-git: %s\nlane-guarded: %s\n---\nbody\n' \
    "$2" "$3" "$4" "$5" > "$1/agents/$2.md"
}
mk_roster_hook() {  # <plugin_dir> <hook-basename> <roster-name> <arm-alternation>
  mkdir -p "$1/hooks"
  # The `$agent_type` below is fixture text in the shape §9 parses, not a value
  # to expand here.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\n# crew-roster: %s -- fixture\ncase "$agent_type" in\n  %s) ;;\n  *) exit 0 ;;\nesac\n' \
    "$3" "$4" > "$1/hooks/$2"
}
# A Bash-capable non-owner missing from the no-git roster would run git unguarded.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" hand "Read, Bash" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'other'
assert_emits "§9 bites on a Bash agent missing from the no-git roster" "$d" \
  "no no-git roster entry for 'hand'"
assert_emits "§9 bites on a stale no-git roster name" "$d" \
  "roster entry 'other' does not match any"

# Listing the git owner in the no-git roster would block the one agent that must commit.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'boss'
assert_emits "§9 bites when the git owner is in the no-git roster" "$d" \
  "lists the git owner 'boss'"

# Exactly one owner: neither zero nor two.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" a "Read, Bash" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'a'
assert_emits "§9 bites when no agent owns git" "$d" "exactly one agent with 'owns-git: true'"
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" a "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" b "Read, Bash" true false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'none'
assert_emits "§9 bites on two git owners" "$d" "found 2"

# A new agent that declares neither fact is the drift this section exists to catch.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'none'
printf -- '---\nname: newbie\ndescription: d\ntools: Read, Bash\n---\nbody\n' > "$d/plugins/foo/agents/newbie.md"
assert_emits "§9 bites on an agent declaring no owns-git" "$d" \
  "plugins/foo/agents/newbie.md has no 'owns-git'"

# Dropping the marker must fail loudly, not silently disable the check.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mkdir -p "$d/plugins/foo/hooks"; printf '#!/usr/bin/env bash\nexit 0\n' > "$d/plugins/foo/hooks/bash-safety.sh"
assert_emits "§9 bites on a missing no-git marker" "$d" "has no parseable '# crew-roster: no-git'"

# No hook file at all must report, not abort the validator under `set -e`.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
assert_emits "§9 bites when the hook file is absent entirely" "$d" \
  "has no parseable '# crew-roster: no-git'"
assert_emits "§9 keeps running after an absent hook" "$d" "Plugin validation failed."

# A reformatted arm must fail loudly, not silently resolve to another case
# statement further down the hook (bash-safety has a `main|master|develop)` arm).
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mkdir -p "$d/plugins/foo/hooks"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\n# crew-roster: no-git -- fixture\ncase "$agent_type" in\n  a | b)\n  ;;\nesac\ncase "$branch" in\n  main|master|develop) ;;\nesac\n' \
  > "$d/plugins/foo/hooks/bash-safety.sh"
assert_emits "§9 bites on a reformatted arm instead of scanning on" "$d" \
  "has no parseable '# crew-roster: no-git'"
assert_silent "§9 does not adopt a later case statement's arm" "$d" "'main'"

# A duplicated roster name is a copy-paste error, not a silent dedupe.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" hand "Read, Bash" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'hand|hand'
assert_emits "§9 bites on a duplicated roster name" "$d" "names 'hand' more than once"

# lane-guarded, both directions.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" laned "Read, Bash" false true
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'laned'
mk_roster_hook "$d/plugins/foo" lane-guard.sh lane-guarded 'other'
assert_emits "§9 bites when a lane-guarded agent is missing from the roster" "$d" \
  "roster omits 'laned'"
assert_emits "§9 bites on a stale lane roster name" "$d" \
  "lane roster entry 'other' does not match any"
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" laned "Read, Bash" false true
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'laned'
mk_roster_hook "$d/plugins/foo" lane-guard.sh lane-guarded 'laned|laned'
assert_emits "§9 bites on a duplicated lane roster name" "$d" \
  "lane roster names 'laned' more than once"

# An empty `owns-git:` must fail loudly, not skip §9 for the whole plugin.
d="$(new_repo_foo)"
mkdir -p "$d/plugins/foo/agents"
printf -- '---\nname: boss\ndescription: d\ntools: Read, Bash\nowns-git:\nlane-guarded: false\n---\nbody\n' \
  > "$d/plugins/foo/agents/boss.md"
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'none'
assert_emits "§9 opt-in keys on presence, not value" "$d" \
  "plugins/foo/agents/boss.md has no 'owns-git'"

# A Bash-less agent in the no-git roster is a dead entry: it can never run git.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" looker "Read, Grep" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'looker'
assert_emits "§9 bites on a Bash-less agent in the no-git roster" "$d" \
  "has no Bash tool; remove the dead entry"

# An inline YAML comment on a declaration is valid YAML, not a broken value.
d="$(new_repo_foo)"
mkdir -p "$d/plugins/foo/agents"
printf -- '---\nname: boss\ndescription: d\ntools: Read, Bash\nowns-git: true  # sole git owner\nlane-guarded: false\n---\nbody\n' \
  > "$d/plugins/foo/agents/boss.md"
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'none'
assert_silent "§9 accepts an inline comment after a declaration" "$d" "expected true or false"

d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" free "Read, Bash" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'free'
mk_roster_hook "$d/plugins/foo" lane-guard.sh lane-guarded 'free'
assert_emits "§9 bites when the roster lists a lane-guarded: false agent" "$d" \
  "declares 'lane-guarded: false'"

# A Bash-less agent needs no no-git entry, and the control must stay silent.
d="$(new_repo_foo)"
mk_roster_agent "$d/plugins/foo" boss "Read, Bash" true false
mk_roster_agent "$d/plugins/foo" laned "Read, Bash" false true
mk_roster_agent "$d/plugins/foo" looker "Read, Grep" false false
mk_roster_hook "$d/plugins/foo" bash-safety.sh no-git 'laned'
mk_roster_hook "$d/plugins/foo" lane-guard.sh lane-guarded 'laned'
# Assert on FAIL-only phrasing: the `ok:` lines also contain the word "roster".
assert_silent "§9 silent when both rosters are in lockstep" "$d" "add it to the arm"
assert_silent "§9 silent: no stale-name complaint in lockstep" "$d" "remove the stale name"
assert_silent "§9 silent: no owner complaint in lockstep" "$d" "exactly one agent"

# A plugin whose agents declare neither field is skipped entirely.
d="$(new_repo_foo)"
mkdir -p "$d/plugins/foo/agents"
printf -- '---\nname: plain\ndescription: d\n---\nbody\n' > "$d/plugins/foo/agents/plain.md"
assert_silent "§9 silent for a plugin that hasn't opted in" "$d" "crew-roster"

# --- §1: every tracked .json must parse ----------------------------------------
d="$(new_repo)"; mkdir -p "$d/plugins/foo"; printf '{\n' > "$d/plugins/foo/broken.json"
assert_emits "§1 bites on unparseable JSON" "$d" "invalid JSON: plugins/foo/broken.json"
d="$(new_repo)"; mkdir -p "$d/plugins/foo"; printf '{"a":1}\n' > "$d/plugins/foo/broken.json"
assert_silent "§1 silent on well-formed JSON" "$d" "invalid JSON: plugins/foo/broken.json"

# --- §2a: manifest identity fields ---------------------------------------------
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo"}'; mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2a bites on a manifest missing version" "$d" "missing required key: version"
d="$(new_repo_foo)"
assert_silent "§2a silent when identity keys are present" "$d" "missing required key"

# --- §2b: declared component paths must exist ----------------------------------
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","skills":"skills/nope"}'
mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2b bites on a declared path that is missing" "$d" "skills -> skills/nope declared in"
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","skills":"skills/real"}'
mk_changelog "$d/plugins/foo" 1.0.0
mkdir -p "$d/plugins/foo/skills/real"; printf -- '---\nname: real\ndescription: d\n---\n' > "$d/plugins/foo/skills/real/SKILL.md"
assert_silent "§2b silent when the declared path exists" "$d" "declared in"

# --- §2c: the auto-loaded hooks/hooks.json must not be declared ----------------
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","hooks":"hooks/hooks.json"}'
mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2c bites when the manifest declares hooks/hooks.json" "$d" "declares the auto-loaded hooks/hooks.json"
d="$(new_repo)"; mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","hooks":"hooks/extra.sh"}'
mk_changelog "$d/plugins/foo" 1.0.0
assert_emits "§2c bites on an additional hook file that is missing" "$d" "hooks -> hooks/extra.sh declared in"
d="$(new_repo_foo)"
assert_silent "§2c silent when the manifest omits it" "$d" "declares the auto-loaded hooks/hooks.json"

# --- §2d: an agents/ directory must hold agent files ---------------------------
d="$(new_repo_foo)"
mkdir -p "$d/plugins/foo/agents"; printf 'notes\n' > "$d/plugins/foo/agents/notes.txt"
assert_emits "§2d bites on an agents/ dir with no .md files" "$d" "agents/ exists but has no .md agent files"
d="$(new_repo_foo)"
mkdir -p "$d/plugins/foo/agents"; printf -- '---\nname: bar\ndescription: d\n---\nbody\n' > "$d/plugins/foo/agents/bar.md"
assert_silent "§2d silent when agents/ holds an agent" "$d" "agents/ exists but has no .md agent files"

# --- §2e: a hooks/ directory must carry the auto-loaded hooks.json -------------
d="$(new_repo_foo)"
mk_hook "$d/plugins/foo" x.sh 'exit 0'
assert_emits "§2e bites on a hooks/ dir with no hooks.json" "$d" "hooks/ exists but hooks/hooks.json missing"
d="$(new_repo_foo)"
mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hooks_json "$d/plugins/foo" "$wired_x"
assert_silent "§2e silent when hooks.json is present" "$d" "hooks/ exists but hooks/hooks.json missing"

# --- §2f: marketplace entries agree with the plugins on disk -------------------
d="$(new_repo)"
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"foo","source":"./plugins/nope"}]}'
assert_emits "§2f bites on a source that does not exist" "$d" "source ./plugins/nope does not exist"

# A source directory that exists but ships no manifest. git tracks files, not
# dirs, so the fixture needs a file inside for the source to survive `git add`.
d="$(new_repo)"; mkdir -p "$d/plugins/foo"; printf 'placeholder\n' > "$d/plugins/foo/README.md"
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"foo","source":"./plugins/foo"}]}'
assert_emits "§2f bites on a source with no manifest" "$d" "plugins/foo/.claude-plugin/plugin.json missing"

d="$(new_repo_foo)"
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"bar","source":"./plugins/foo"}]}'
assert_emits "§2f bites on an entry name != manifest name" "$d" "!= plugin.json name"

d="$(new_repo)"
mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","description":"canonical"}'
mk_changelog "$d/plugins/foo" 1.0.0
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"foo","source":"./plugins/foo","description":"stale"}]}'
assert_emits "§2f bites on a description that drifted" "$d" "description differs from"

d="$(new_repo)"
mk_manifest_json "$d/plugins/foo" '{"name":"foo","version":"1.0.0","description":"canonical"}'
mk_changelog "$d/plugins/foo" 1.0.0
mk_marketplace "$d" '{"name":"m","plugins":[{"name":"foo","source":"./plugins/foo","description":"canonical"}]}'
assert_silent "§2f silent when the entry matches its manifest" "$d" "description differs from"

# --- §3: hook scripts are valid bash and executable ----------------------------
d="$(new_repo_foo)"
mkdir -p "$d/plugins/foo/hooks"; printf '#!/usr/bin/env bash\nif [ 1\n' > "$d/plugins/foo/hooks/x.sh"
chmod +x "$d/plugins/foo/hooks/x.sh"   # chmod so only the syntax guard can fire
assert_emits "§3 bites on a bash syntax error" "$d" "bash syntax error: plugins/foo/hooks/x.sh"
d="$(new_repo_foo)"
mkdir -p "$d/plugins/foo/hooks"; printf '#!/usr/bin/env bash\nexit 0\n' > "$d/plugins/foo/hooks/x.sh"
assert_emits "§3 bites on a non-executable hook" "$d" "not executable (chmod +x): plugins/foo/hooks/x.sh"
d="$(new_repo_foo)"
mk_hook "$d/plugins/foo" x.sh 'exit 0'
# Two asserts, each on its own FAIL text: the bare path also appears in this
# section's `ok:` lines, so matching on it alone would never go silent.
assert_silent "§3 silent on valid syntax" "$d" "bash syntax error"
assert_silent "§3 silent on an executable hook" "$d" "not executable"

# hooks/lib/*.sh is the other kind of file in a hooks/ directory: sourced by the
# entry points, never executed, so §3 inverts the mode rule for it.
d="$(new_repo_foo)"
mk_lib "$d/plugins/foo" guard-lib.sh 'echo lib'; chmod +x "$d/plugins/foo/hooks/lib/guard-lib.sh"
assert_emits "§3 bites on an executable sourced library" "$d" "sourced library is executable (chmod -x): plugins/foo/hooks/lib/guard-lib.sh"
d="$(new_repo_foo)"
mk_lib "$d/plugins/foo" guard-lib.sh 'echo lib'
assert_silent "§3 silent on a non-executable library" "$d" "chmod"
# A library still has to parse — §3's syntax guard covers both kinds.
d="$(new_repo_foo)"
mk_lib "$d/plugins/foo" guard-lib.sh 'if [ 1'
assert_emits "§3 bites on a syntax error in a library" "$d" "bash syntax error: plugins/foo/hooks/lib/guard-lib.sh"

# --- §6: hooks.json wiring resolves, and every hook script is wired ------------
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hooks_json "$d/plugins/foo" './hooks/x.sh'
assert_emits "§6 bites on a command that skips CLAUDE_PLUGIN_ROOT" "$d" "does not start with"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hooks_json "$d/plugins/foo" "$wired_missing"
assert_emits "§6 bites on wiring a script that does not exist" "$d" "wires hooks/missing.sh but"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hook "$d/plugins/foo" y.sh 'exit 0'
mk_hooks_json "$d/plugins/foo" "$wired_x"
assert_emits "§6 bites on a hook script nothing wires" "$d" "plugins/foo/hooks/y.sh exists but is not wired"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'
mkdir -p "$d/plugins/foo/hooks"; printf '{"hooks":[]}\n' > "$d/plugins/foo/hooks/hooks.json"
assert_emits "§6 bites on valid JSON of the wrong shape" "$d" "does not have the expected shape"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'
mkdir -p "$d/plugins/foo/hooks"; printf '{\n' > "$d/plugins/foo/hooks/hooks.json"
assert_emits "§6 bites on unparseable wiring" "$d" "cannot cross-check its hook wiring"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_hooks_json "$d/plugins/foo" "$wired_x"
assert_silent "§6 silent when wiring and scripts agree" "$d" "is not wired"

# A sourced library is the one hooks/ file that must NOT be wired: wiring one
# would run a library with no main as a hook, which exits 0 having inspected
# nothing — a silent hole in a fail-closed guard rather than a visible error.
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_lib "$d/plugins/foo" guard-lib.sh 'echo lib'
mk_hooks_json "$d/plugins/foo" "$wired_x"
assert_silent "§6 does not demand a library be wired" "$d" "is not wired"
d="$(new_repo)"; mk_hook "$d/plugins/foo" x.sh 'exit 0'; mk_lib "$d/plugins/foo" guard-lib.sh 'echo lib'
mk_hooks_json "$d/plugins/foo" "$wired_lib"
assert_emits "§6 bites on wiring a sourced library as a hook" "$d" "but hooks/lib/*.sh are sourced libraries"

# --- §10: namespaced refs in prose must resolve to an agent or command --------
mk_prose_agent() {  # <plugin_dir> <name> <body>
  mkdir -p "$1/agents"
  printf -- '---\nname: %s\ndescription: d\n---\n%s\n' "$2" "$3" > "$1/agents/$2.md"
}
d="$(new_repo_foo)"
# Backticks below are Markdown code spans in fixture prose, not substitution:
# these refs are nearly always written as `crew:tank`, so §10 must see that form.
# shellcheck disable=SC2016
mk_prose_agent "$d/plugins/foo" bar 'Delegate to `foo:ghost` when stuck.'
assert_emits "§10 bites on a prose ref to a nonexistent agent" "$d" \
  "references 'foo:ghost' but no plugins/foo/agents/ghost.md"

# A ref that resolves to a command, not an agent, is equally valid.
d="$(new_repo_foo)"
# shellcheck disable=SC2016
mk_prose_agent "$d/plugins/foo" bar 'Run `/foo:ship` to finish.'
mkdir -p "$d/plugins/foo/commands"; printf -- '---\nname: ship\ndescription: d\n---\nbody\n' > "$d/plugins/foo/commands/ship.md"
assert_silent "§10 silent when the ref resolves to a command" "$d" "but no plugins/foo"

# A plugin name embedded in a longer word is not a reference. Guards the
# delimiter group that stands in for `\b` (a GNU extension we can't use).
d="$(new_repo_foo)"
mk_prose_agent "$d/plugins/foo" bar 'The xfoo:ghost marker is not a reference.'
assert_silent "§10 ignores a plugin name embedded in a longer word" "$d" "ghost"

# An unknown namespace is another marketplace's business, not ours.
d="$(new_repo_foo)"
# shellcheck disable=SC2016
mk_prose_agent "$d/plugins/foo" bar 'See `other:thing` for details.'
assert_silent "§10 ignores a namespace no plugin here declares" "$d" "other:thing"

# --- §11: init.md §1 slot keys <-> .claude/crew.md frontmatter keys -----------
mk_init_slots() {  # <repo> <slot-lines>
  mkdir -p "$1/plugins/crew/commands"
  printf '## 1. Canonical configuration slots\n\n%s\n\n## 2. Detect\n' "$2" \
    > "$1/plugins/crew/commands/init.md"
}
mk_crew_config() {  # <repo> <frontmatter-lines> [body]
  mkdir -p "$1/.claude"
  printf -- '---\n%s\n---\n\n%s\n' "$2" "${3:-Notes.}" > "$1/.claude/crew.md"
}

# Slot bullets in §1's shape. The backticks around the key are literal markdown
# -- the shape §11 parses -- so these stay single-quoted.
# shellcheck disable=SC2016
slot_base='- **Base branch** (`baseBranch`) — the branch to cut from.'
# shellcheck disable=SC2016
slot_plan='- **Plan directory** (`planDirectory`) — where plans go.'

d="$(new_repo)"
mk_init_slots "$d" "$slot_base"$'\n'"$slot_plan"
mk_crew_config "$d" 'baseBranch: main'
assert_emits "§11 bites on a slot key missing from .claude/crew.md" "$d" \
  "declares slot key 'planDirectory' but .claude/crew.md"

d="$(new_repo)"
mk_init_slots "$d" "$slot_base"
mk_crew_config "$d" 'baseBranch: main
deployTarget: prod'
assert_emits "§11 bites on a config key that is not a declared slot" "$d" \
  "carries 'deployTarget:', which is not a slot"

# Only the documented shapes count: a `- **Slot** (`key`) —` bullet under §1, and
# a top-level key inside the frontmatter. Bold used for emphasis is not a slot
# declaration, and a key named in the file's prose body is not configuration.
d="$(new_repo)"
mk_init_slots "$d" "$slot_base"$'\n''- **Note** this bullet is emphasis, not a slot.'
mk_crew_config "$d" 'baseBranch: main' 'A body line naming deployTarget: prod is prose.'
assert_silent "§11 ignores a non-slot bold bullet under §1" "$d" "'Note'"
assert_silent "§11 ignores a key named in the config file's body" "$d" "deployTarget"

# A slot bullet without its key is not parseable as a slot -- the key is the half
# that has to agree, so a label-only bullet must not read as a declaration.
d="$(new_repo)"
mk_init_slots "$d" '- **Base branch** — the branch to cut from, no key declared.'
mk_crew_config "$d" 'baseBranch: main'
assert_emits "§11 bites when a slot bullet declares no key" "$d" \
  "has no parseable slot list"

# An unparseable slot list must report, not silently verify nothing.
d="$(new_repo)"
mk_init_slots "$d" 'No slots here, just prose.'
mk_crew_config "$d" 'baseBranch: main'
assert_emits "§11 bites when the slot list is unparseable" "$d" \
  "has no parseable slot list"

# Frontmatter with no keys at all is reported, not passed over.
d="$(new_repo)"
mk_init_slots "$d" "$slot_base"
mk_crew_config "$d" '# just a comment'
assert_emits "§11 bites when the config file has no frontmatter keys" "$d" \
  "has no frontmatter keys"

d="$(new_repo)"
mk_init_slots "$d" "$slot_base"$'\n'"$slot_plan"
mk_crew_config "$d" 'baseBranch: main
planDirectory: docs/plans/'
assert_silent "§11 silent when the slot keys agree" "$d" "not a slot in"
assert_silent "§11 silent: no missing-key complaint when they agree" "$d" "but .claude/crew.md"

# --- §12: always-loaded footprint is reported, and an opt-in cap is enforced ----
# mk_capped_agent <plugin_dir> <name> <cap-or-empty> <body-line-count> [skill-ref]
# The cap line is omitted entirely when <cap> is empty, so the same helper builds
# both the opt-in and the report-only (uncapped) cases.
mk_capped_agent() {
  local dir="$1" name="$2" cap="$3" body="$4" skill="${5:-}" i
  mkdir -p "$dir/agents"
  {
    printf -- '---\nname: %s\ndescription: d\n' "$name"
    [ -n "$cap" ] && printf 'loaded-lines-cap: %s\n' "$cap"
    [ -n "$skill" ] && printf 'skills:\n  - %s\n' "$skill"
    printf -- '---\n'
    for ((i = 0; i < body; i++)); do printf 'body line %d\n' "$i"; done
  } > "$dir/agents/$name.md"
}
# mk_sized_skill <plugin_dir> <name> <extra-body-lines>
mk_sized_skill() {
  local dir="$1" name="$2" extra="$3" i
  mkdir -p "$dir/skills/$name"
  {
    printf -- '---\nname: %s\ndescription: d\n---\n' "$name"
    for ((i = 0; i < extra; i++)); do printf 'skill line %d\n' "$i"; done
  } > "$dir/skills/$name/SKILL.md"
}

# The footprint is reported for every agent, capped or not.
d="$(new_repo_foo)"
mk_capped_agent "$d/plugins/foo" plain "" 5
assert_emits "§12 reports an uncapped agent's footprint" "$d" "plain.md loaded footprint: 9 lines"

# A cap is enforced, and the preloaded skills count toward it: the agent body
# alone fits under 12, the agent plus its 6-line skill does not.
d="$(new_repo_foo)"
mk_sized_skill "$d/plugins/foo" heavy 2
mk_capped_agent "$d/plugins/foo" fat 12 5 heavy
assert_emits "§12 bites when the footprint exceeds its cap" "$d" \
  "fat.md loaded footprint 18 exceeds its 'loaded-lines-cap: 12'"
assert_emits "§12 counts preloaded skills toward the footprint" "$d" "(agent 12 + skills 6)"

d="$(new_repo_foo)"
mk_sized_skill "$d/plugins/foo" heavy 2
mk_capped_agent "$d/plugins/foo" lean 40 5 heavy
assert_silent "§12 silent when the footprint is within its cap" "$d" "exceeds its"

# A cap that can't be parsed must fail loudly, not silently stop enforcing.
d="$(new_repo_foo)"
mk_capped_agent "$d/plugins/foo" bad "not-a-number" 5
assert_emits "§12 bites on a non-numeric cap" "$d" "expected a plain line count"
d="$(new_repo_foo)"
mk_capped_agent "$d/plugins/foo" empty "" 5
# Written by hand: mk_capped_agent omits the key entirely when the cap is empty,
# but a present-with-no-value key is the case that must not skip the check.
printf -- '---\nname: empty\ndescription: d\nloaded-lines-cap:\n---\nbody\n' \
  > "$d/plugins/foo/agents/empty.md"
assert_emits "§12 bites on a present-but-empty cap" "$d" "has an empty 'loaded-lines-cap'"

# An unresolved skill ref is §2g's failure; §12 must not double-report it, and
# must still report the agent's own footprint.
d="$(new_repo_foo)"
mk_capped_agent "$d/plugins/foo" typo 40 5 ghost-skill
assert_emits "§12 still reports a footprint when a skill ref is unresolved" "$d" \
  "typo.md loaded footprint: 12 lines (agent 12 + skills 0)"
assert_silent "§12 leaves the unresolved ref to §2g" "$d" "measure its loaded footprint"

# A tracked file deleted from the worktree is listed by git ls-files but can't
# be read. §12 must report that loudly (not abort under set -e, not count 0 and
# maybe pass a cap). run_validator would re-stage the deletion away, so this
# runs the validator on the already-staged tree.
assert_emits_prestaged() {  # <label> <dir> <substr>
  _vout="$(cd "$2" && bash scripts/validate-plugin.sh 2>&1)" || true
  if [[ "$_vout" == *"$3"* ]]; then _pass; else _fail "$1: validator did not emit '$3' — output: $_vout"; fi
}
d="$(new_repo_foo)"
mk_capped_agent "$d/plugins/foo" gone "" 5
git -C "$d" add -A >/dev/null 2>&1; rm "$d/plugins/foo/agents/gone.md"
assert_emits_prestaged "§12 bites on a staged-but-deleted agent file" "$d" \
  "gone.md could not be read to measure its loaded footprint"
assert_emits_prestaged "§12 keeps running after an unreadable agent file" "$d" \
  "Plugin validation failed."

d="$(new_repo_foo)"
mk_sized_skill "$d/plugins/foo" heavy 2
mk_capped_agent "$d/plugins/foo" fine 12 5 heavy
git -C "$d" add -A >/dev/null 2>&1; rm "$d/plugins/foo/skills/heavy/SKILL.md"
assert_emits_prestaged "§12 bites on a staged-but-deleted skill file" "$d" \
  "preloads 'heavy' but plugins/foo/skills/heavy/SKILL.md could not be read"
# No footprint or cap verdict may be emitted for an uncountable agent: a 0-line
# count for the missing skill would have squeaked 'fine' under its cap of 12.
assert_emits_prestaged "§12 withholds the cap verdict when a skill is unreadable" "$d" \
  "Plugin validation failed."
_vout_check="$(cd "$d" && bash scripts/validate-plugin.sh 2>&1)" || true
if [[ "$_vout_check" != *"fine.md loaded footprint"* ]]; then _pass; else
  _fail "§12 reported a footprint for an agent whose skill was unreadable"
fi

# --- §13: MCP grants are server-scoped and cover both install paths ------------
# mk_tools_agent <plugin_dir> <name> <tools-line>
mk_tools_agent() {
  mkdir -p "$1/agents"
  printf -- '---\nname: %s\ndescription: d\ntools: %s\n---\nbody\n' "$2" "$3" > "$1/agents/$2.md"
}

# A bare server key alone leaves the plugin-install path unmatched.
d="$(new_repo_foo)"
mk_tools_agent "$d/plugins/foo" lonely "Read, mcp__figma"
assert_emits "§13 bites on a bare server key with no plugin form" "$d" \
  "add the plugin form 'mcp__plugin_<plugin>_figma'"

# ...and the reverse: a plugin form alone leaves .mcp.json-keyed installs out.
d="$(new_repo_foo)"
mk_tools_agent "$d/plugins/foo" scoped_only "Read, mcp__plugin_figma_figma"
assert_emits "§13 bites on a plugin form with no bare key" "$d" \
  "'mcp__plugin_figma_figma' names a server no bare key covers"

# A plugin and the server it bundles are keyed independently — the real
# chrome-devtools-mcp plugin ships a server called chrome-devtools — so the
# halves pair by suffix, not by being equal.
d="$(new_repo_foo)"
mk_tools_agent "$d/plugins/foo" asym \
  "Read, mcp__chrome-devtools, mcp__plugin_chrome-devtools-mcp_chrome-devtools"
assert_emits "§13 pairs a plugin whose name differs from its server" "$d" \
  "asym.md tools -> mcp__chrome-devtools has its plugin form"
assert_silent "§13 doesn't demand a same-name plugin form" "$d" \
  "add the plugin form"

# The suffix must be the server half, not any substring of the plugin half.
d="$(new_repo_foo)"
mk_tools_agent "$d/plugins/foo" wrong_half "Read, mcp__chrome-devtools, mcp__plugin_chrome-devtools_ohno"
assert_emits "§13 bites when only the plugin half matches the bare key" "$d" \
  "'mcp__chrome-devtools' covers only a server keyed in .mcp.json"

# A tool-scoped grant withholds the rest of the server's tools.
d="$(new_repo_foo)"
mk_tools_agent "$d/plugins/foo" narrow "Read, mcp__figma__get_design_context"
assert_emits "§13 bites on a tool-scoped MCP grant" "$d" \
  "grants a single MCP tool; allowlist the whole server as 'mcp__figma'"
# The malformed entry must not then be read as a server name of its own.
assert_silent "§13 doesn't re-report a malformed entry as an unpaired key" "$d" \
  "mcp__plugin_figma__get_design_context"

# A paired agent is silent, and `mcp__x__*` is the same grant as `mcp__x`.
d="$(new_repo_foo)"
mk_tools_agent "$d/plugins/foo" paired "Read, mcp__figma__*, mcp__plugin_figma_figma"
assert_silent "§13 silent when both install paths are granted" "$d" \
  "add the plugin form"
assert_emits "§13 treats mcp__x__* as the server grant" "$d" \
  "paired.md tools -> mcp__figma has its plugin form"

# Hosted connectors can't be plugin-installed, so they're exempt by name.
d="$(new_repo_foo)"
mk_tools_agent "$d/plugins/foo" hosted "Read, mcp__claude_ai_Figma"
assert_emits "§13 exempts a connector-only namespace" "$d" \
  "mcp__claude_ai_Figma is connector-only"

# The block-list `tools:` shape is read too — reading only the inline form would
# let a list-form allowlist skip the section without a word.
d="$(new_repo_foo)"
mkdir -p "$d/plugins/foo/agents"
printf -- '---\nname: listy\ndescription: d\ntools:\n  - Read\n  - mcp__figma\n---\nbody\n' \
  > "$d/plugins/foo/agents/listy.md"
assert_emits "§13 reads a list-form tools: block" "$d" \
  "listy.md tools -> 'mcp__figma' covers only a server keyed in .mcp.json"

# A trailing YAML comment must not ride along into the server name.
d="$(new_repo_foo)"
# The commented entry is last and bare, so without stripping it becomes the
# server name `figma # design` and the pairing check fails on a name that isn't
# in the file.
mk_tools_agent "$d/plugins/foo" commented "Read, mcp__plugin_figma_figma, mcp__figma # design"
assert_silent "§13 strips a trailing comment from the tools list" "$d" \
  "figma # design"
assert_emits "§13 reads the commented entry as its server" "$d" \
  "commented.md tools -> mcp__figma has its plugin form"

# `mcp__*` grants no server, so it must be reported rather than passed over.
d="$(new_repo_foo)"
mk_tools_agent "$d/plugins/foo" starry "Read, mcp__*"
assert_emits "§13 bites on a serverless mcp__* grant" "$d" \
  "'mcp__*' names no server"

# `Agent(a, b)` splits on the same commas as the tool list; those fragments are
# not MCP entries and must not be read as one.
d="$(new_repo_foo)"
mk_tools_agent "$d/plugins/foo" delegator "Agent(foo:one, foo:two), Read, Bash"
assert_silent "§13 ignores an agent with no MCP grants" "$d" "delegator.md tools ->"

# --- §14: frontmatter parses as YAML -----------------------------------------
# mk_fm_file <path> <description-value> — an agent/command/skill file whose
# description is written verbatim, so a case can supply an unquoted scalar, a
# quoted one, or a colon that YAML tolerates.
mk_fm_file() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\nname: sample\ndescription: %s\n---\nbody\n' "$2" > "$1"
}

# The trap: prose with a colon+space. YAML reads `takes: server-side` as a
# nested mapping and drops the whole block, so the file loads with no name and
# no description at all.
d="$(new_repo_foo)"
mk_fm_file "$d/plugins/foo/agents/prose.md" 'Implements whatever shape it takes: server-side logic and data access.'
assert_emits "§14 bites on an unquoted description with a colon+space" "$d" \
  "agents/prose.md:3 frontmatter 'description' is an unquoted scalar carrying a colon before whitespace"

# Commands and skills carry the same hand-written descriptions, so the sweep
# must reach them too and not just agents/.
d="$(new_repo_foo)"
mk_fm_file "$d/plugins/foo/commands/say.md" 'Messages a peer. Best-effort delivery: it never acts on their behalf.'
assert_emits "§14 reaches commands/" "$d" "commands/say.md:3 frontmatter 'description'"

d="$(new_repo_foo)"
mk_fm_file "$d/plugins/foo/skills/steer/SKILL.md" 'Use when direction arrives mid-run: authenticate it on the token.'
assert_emits "§14 reaches skills/" "$d" "skills/steer/SKILL.md:3 frontmatter 'description'"

# A value ending in a colon opens a mapping just the same.
d="$(new_repo_foo)"
mk_fm_file "$d/plugins/foo/agents/trailing.md" 'Resolves one of the following:'
assert_emits "§14 bites on a value ending in a colon" "$d" \
  "agents/trailing.md:3 frontmatter 'description' is an unquoted scalar carrying a trailing colon"

# Quoting is the fix the message names, so a quoted value must clear the guard
# with the same prose in it.
d="$(new_repo_foo)"
mk_fm_file "$d/plugins/foo/agents/quoted.md" '"Implements whatever shape it takes: server-side logic and data access."'
assert_silent "§14 accepts the same prose once quoted" "$d" "agents/quoted.md:3 frontmatter"

# A colon with no space after it stays inside the plain scalar, and YAML is
# fine with it: flagging `mcp__plugin_foo:bar` style text would be a false bite.
d="$(new_repo_foo)"
mk_fm_file "$d/plugins/foo/agents/tight.md" 'Routes foo:bar and foo:baz to the right lane.'
assert_silent "§14 leaves a colon with no space alone" "$d" "agents/tight.md:3 frontmatter"

# A staged-but-deleted file is still listed by git ls-files; awk dies on it, and
# under `set -e` that would end the run before any later section reported.
#
# Prestaged, like §12's pair: assert_emits re-stages, and staging the deletion
# would drop the path from git ls-files so the guard never sees it at all.
d="$(new_repo_foo)"
mk_fm_file "$d/plugins/foo/agents/gone.md" 'A plain description.'
git -C "$d" add -A >/dev/null 2>&1; rm "$d/plugins/foo/agents/gone.md"
assert_emits_prestaged "§14 bites on a staged-but-deleted file" "$d" \
  "agents/gone.md could not be read to check its frontmatter"
# The run has to reach its own verdict rather than dying mid-sweep on the awk.
assert_emits_prestaged "§14 keeps running after an unreadable file" "$d" \
  "Plugin validation failed."

finish
