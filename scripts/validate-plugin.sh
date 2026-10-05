#!/usr/bin/env bash
# Validates every plugin's structure so manifest/file drift fails fast.
# Repo tooling, not part of any plugin: it needs this monorepo's layout and
# never runs in an installed plugin. Runnable locally (`scripts/validate-plugin.sh`)
# and in CI.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }
ok()  { echo "ok:   $*"; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# Associative arrays (declare -A in §2g/§6/§9) need Bash 4+; macOS's
# stock /bin/bash is 3.2. Fail with a pointer instead of the cryptic
# `declare: -A: invalid option` those sections would otherwise die with.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "FAIL: this validator needs Bash >= 4 (associative arrays); on macOS run it with a newer bash (e.g. brew install bash)" >&2
  exit 1
fi

# 1. Every JSON file parses.
while IFS= read -r f; do
  if jq empty "$f" >/dev/null 2>&1; then
    ok "valid JSON: $f"
  else
    err "invalid JSON: $f"
  fi
done < <(git ls-files '*.json')

# 2. Validate each plugin under plugins/<name>/. Component paths in a plugin
#    manifest are resolved relative to that plugin's root.
while IFS= read -r manifest; do
  plugin_dir="$(dirname "$(dirname "$manifest")")"  # plugins/<name>
  if ! jq empty "$manifest" >/dev/null 2>&1; then
    # Malformed JSON is already reported above; skip content checks.
    err "$manifest is not valid JSON; skipping content checks"
    continue
  fi

  # 2a. Required identity fields.
  for key in name version; do
    if [ "$(jq -r --arg k "$key" 'has($k)' "$manifest")" != "true" ]; then
      err "$manifest missing required key: $key"
    else
      ok "$plugin_dir has key: $key"
    fi
  done

  # 2b. Component paths the manifest points at actually exist. A field may be a
  #     single path string or an array of paths; validate every path. `hooks` is
  #     handled by 2c, which has its own rule.
  for key in commands skills; do
    while IFS= read -r path; do
      path="${path%$'\r'}"  # tolerate CRLF checkouts on Windows
      [ -z "$path" ] && continue
      if [ -e "$plugin_dir/$path" ]; then
        ok "$plugin_dir $key -> $path exists"
      else
        err "$plugin_dir $key -> $path declared in $manifest but not found"
      fi
    done < <(jq -r --arg k "$key" '(.[$k] // empty) | if type == "array" then .[] else . end' "$manifest")
  done

  # 2c. The manifest may declare *additional* hook files, but must NOT declare the
  #     standard hooks/hooks.json — it is auto-loaded, so declaring it triggers a
  #     "Duplicate hooks file" load error. Validate that additional files exist.
  while IFS= read -r path; do
    path="${path%$'\r'}"  # tolerate CRLF checkouts on Windows
    [ -z "$path" ] && continue
    if [ "${path#./}" = "hooks/hooks.json" ]; then
      err "$plugin_dir declares the auto-loaded hooks/hooks.json in its manifest; remove it (only additional hook files belong in manifest.hooks)"
    elif [ -e "$plugin_dir/$path" ]; then
      ok "$plugin_dir hooks -> $path exists (additional hook file)"
    else
      err "$plugin_dir hooks -> $path declared in $manifest but not found"
    fi
  done < <(jq -r '(.hooks // empty) | if type == "array" then .[] else . end' "$manifest")

  # 2d. Agents are auto-discovered from the plugin's `agents/` directory, not the
  #     manifest (declaring them there passes validation but they never load).
  #     The directory itself is optional — a commands/skills-only plugin is fine —
  #     but if it exists it must contain agent files (an empty dir means drift).
  if [ -d "$plugin_dir/agents" ]; then
    if ls "$plugin_dir"/agents/*.md >/dev/null 2>&1; then
      ok "$plugin_dir agents/ exists with agent files"
    else
      err "$plugin_dir agents/ exists but has no .md agent files (agents are auto-discovered from there)"
    fi
  else
    ok "$plugin_dir has no agents/ (optional)"
  fi

  # 2e. Hooks are optional, but a hooks/ directory without the auto-loaded
  #     hooks/hooks.json means the hook scripts in it never run.
  if [ -d "$plugin_dir/hooks" ]; then
    if [ -f "$plugin_dir/hooks/hooks.json" ]; then
      ok "$plugin_dir hooks/hooks.json exists (auto-loaded)"
    else
      err "$plugin_dir hooks/ exists but hooks/hooks.json missing (nothing wires the hooks)"
    fi
  else
    ok "$plugin_dir has no hooks/ (optional)"
  fi
done < <(git ls-files 'plugins/*/.claude-plugin/plugin.json')

# 2f. Marketplace entries agree with the plugins on disk: every listed source
#     exists, has a manifest, its manifest name matches the entry name, and its
#     description matches the manifest's (plugin.json is canonical — the two
#     read the same to users, so wording drift is a doc bug).
marketplace=".claude-plugin/marketplace.json"
if [ -f "$marketplace" ] && jq empty "$marketplace" >/dev/null 2>&1; then
  while IFS=$'\t' read -r mname msource; do
    msource="${msource%$'\r'}"  # tolerate CRLF checkouts on Windows
    src="${msource#./}"
    if [ ! -d "$src" ]; then
      err "$marketplace entry '$mname': source $msource does not exist"
      continue
    fi
    pmanifest="$src/.claude-plugin/plugin.json"
    if [ ! -f "$pmanifest" ]; then
      err "$marketplace entry '$mname': $pmanifest missing"
      continue
    fi
    pname="$(jq -r '.name // empty' "$pmanifest")"
    pname="${pname%$'\r'}"  # tolerate CRLF checkouts on Windows
    if [ "$pname" = "$mname" ]; then
      ok "$marketplace entry '$mname' matches $pmanifest"
    else
      err "$marketplace entry '$mname' != plugin.json name '$pname' ($pmanifest)"
    fi
    # Descriptions are compared via jq (not the @tsv fields above) so tabs or
    # escapes in either value can't skew the comparison.
    mdesc="$(jq -r --arg n "$mname" '.plugins[] | select(.name == $n) | .description // ""' "$marketplace")"
    pdesc="$(jq -r '.description // ""' "$pmanifest")"
    if [ "$mdesc" = "$pdesc" ]; then
      ok "$marketplace entry '$mname' description matches $pmanifest"
    else
      err "$marketplace entry '$mname' description differs from $pmanifest (plugin.json is canonical; copy it into the marketplace entry)"
    fi
  done < <(jq -r '.plugins[] | select((.source | type) == "string") | [.name, .source] | @tsv' "$marketplace")
else
  err "$marketplace missing or invalid"
fi

# 2g. Every skill referenced in an agent's YAML frontmatter `skills:` list must
#     resolve to some plugins/*/skills/<name>/SKILL.md in the repo. Skills are
#     referenced unqualified (per the existing convention), so resolution is
#     "exists anywhere under any plugin's skills/ directory". A typo here would
#     otherwise fail silently at runtime — the skill just doesn't load.
declare -A skill_index=()
while IFS= read -r skill_md; do
  skill_name="$(basename "$(dirname "$skill_md")")"
  skill_index["$skill_name"]=1
done < <(git ls-files 'plugins/*/skills/*/SKILL.md')

while IFS= read -r agent; do
  while IFS= read -r skill_ref; do
    [ -z "$skill_ref" ] && continue
    if [ -n "${skill_index[$skill_ref]:-}" ]; then
      ok "$agent skills -> $skill_ref resolves"
    else
      err "$agent skills -> $skill_ref does not resolve to any plugins/*/skills/$skill_ref/SKILL.md"
    fi
  done < <(awk '
    BEGIN { in_fm = 0; in_skills = 0 }
    /^---[[:space:]]*$/ {
      if (in_fm == 0) { in_fm = 1; next }
      else { exit }
    }
    in_fm && in_skills {
      if ($0 ~ /^[[:space:]]+-[[:space:]]+/) {
        sub(/^[[:space:]]+-[[:space:]]+/, "")
        sub(/[[:space:]]+#.*$/, "")
        sub(/[[:space:]]+$/, "")
        gsub(/^["\047]|["\047]$/, "")
        if (length($0)) print
        next
      } else if ($0 !~ /^[[:space:]]*$/) {
        in_skills = 0
      }
    }
    in_fm && /^skills:[[:space:]]*$/ { in_skills = 1 }
  ' "$agent")
done < <(git ls-files 'plugins/*/agents/*.md')

# 2h. Each plugin's manifest version must match the newest entry in its CHANGELOG,
#     so a version bump can't ship without release notes (auto-release.yml pulls
#     notes from that section) and notes can't land without a bump. Every plugin
#     keeps its changelog next to its manifest: plugins/<name>/CHANGELOG.md.
while IFS= read -r manifest; do
  plugin_dir="$(dirname "$(dirname "$manifest")")"  # plugins/<name>
  # Malformed JSON is already reported by §1; skip so a bad manifest doesn't abort
  # the whole run under `set -e` (mirrors the §2 loop).
  jq empty "$manifest" >/dev/null 2>&1 || continue
  plugin_version="$(jq -r '.version // empty' "$manifest")"
  [ -z "$plugin_version" ] && continue  # missing version already reported by 2a
  changelog="$plugin_dir/CHANGELOG.md"
  if [ ! -f "$changelog" ]; then
    err "$plugin_dir declares version $plugin_version but has no changelog at $changelog"
    continue
  fi
  # grep -m1 reads the file directly and stops at the first hit (no `| head`,
  # which could SIGPIPE the producer under `set -o pipefail`); strip with
  # parameter expansion. `|| true` swallows grep's exit 1 when there's no match.
  newest_line="$(grep -m1 -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$changelog" || true)"
  newest_entry="${newest_line#*\[}"
  newest_entry="${newest_entry%%\]*}"
  if [ "$newest_entry" = "$plugin_version" ]; then
    ok "$plugin_dir version $plugin_version matches newest $changelog entry"
  else
    err "$plugin_dir version $plugin_version != newest $changelog entry (${newest_entry:-none}); bump the manifest and add its CHANGELOG entry together"
  fi
done < <(git ls-files 'plugins/*/.claude-plugin/plugin.json')

# 3. Hook shell files are syntactically valid and carry the file mode their role
#    implies:
#      - hooks/*.sh          entry points the harness executes -> must be +x;
#      - hooks/lib/*.sh      libraries the entry points source -> must NOT be +x.
#    An executable library reads as a hook and invites being wired as one, where
#    it would do nothing (it has no main) — so the wrong mode is a real error.
#    git's `*` crosses directory separators, so one listing covers both kinds and
#    the path shape decides which rule applies; §6 enforces the wiring half.
while IFS= read -r h; do
  if bash -n "$h" 2>/dev/null; then
    ok "syntax: $h"
  else
    err "bash syntax error: $h"
  fi
  case "$h" in
    */hooks/lib/*)
      if [ -x "$h" ]; then
        err "sourced library is executable (chmod -x): $h — hooks/lib/*.sh are sourced, not run"
      else
        ok "not executable (sourced library): $h"
      fi ;;
    *)
      if [ -x "$h" ]; then
        ok "executable: $h"
      else
        err "not executable (chmod +x): $h"
      fi ;;
  esac
done < <(git ls-files 'plugins/*/hooks/*.sh')

# 4-5. Unused numbers; later sections keep theirs so §N references stay stable.

# 6. Hook wiring cross-check: every command in a plugin's hooks/hooks.json must
#    resolve (via its "${CLAUDE_PLUGIN_ROOT}"/ prefix) to a file in that plugin,
#    and every hooks/*.sh on disk must be wired by some command — an unwired
#    guard script silently never runs (the same failure class §2g catches for
#    agent skills: references).
# Single-quoted: the literal, unexpanded prefix as it appears in the JSON.
# shellcheck disable=SC2016
wiring_pfx='"${CLAUDE_PLUGIN_ROOT}"/'
while IFS= read -r hooks_json; do
  plugin_dir="${hooks_json%/hooks/hooks.json}"
  # Malformed JSON is already reported by §1; skip the cross-check.
  if ! jq empty "$hooks_json" >/dev/null 2>&1; then
    err "$hooks_json is not valid JSON; cannot cross-check its hook wiring"
    continue
  fi
  # Fail loudly on a structurally wrong file (valid JSON, wrong shape): the
  # extraction below would otherwise spray a raw jq error and report every
  # script as "not wired", which misdiagnoses the actual problem.
  if ! jq -e '(.hooks | type == "object")
              and ([.hooks[] | type == "array"] | all)
              and ([.hooks[][] | .hooks | type == "array"] | all)' "$hooks_json" >/dev/null 2>&1; then
    err "$hooks_json does not have the expected shape ({hooks: {<event>: [{hooks: [{command}]}]}}); cannot cross-check its hook wiring"
    continue
  fi
  declare -A wired=()
  while IFS= read -r hcmd; do
    hcmd="${hcmd%$'\r'}"  # tolerate CRLF checkouts on Windows
    [ -z "$hcmd" ] && continue
    rel="${hcmd#"$wiring_pfx"}"
    if [ "$rel" = "$hcmd" ]; then
      err "$hooks_json command '$hcmd' does not start with $wiring_pfx — a plugin's own hooks must resolve through CLAUDE_PLUGIN_ROOT"
      continue
    fi
    rel="${rel%% *}"  # a command may carry arguments; the script path is the first token
    if [ -f "$plugin_dir/$rel" ]; then
      ok "$hooks_json -> $rel exists"
    else
      err "$hooks_json wires $rel but $plugin_dir/$rel does not exist"
    fi
    wired["$rel"]=1
  done < <(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command // empty' "$hooks_json")
  while IFS= read -r sh_file; do
    rel="${sh_file#"$plugin_dir/"}"
    # hooks/lib/*.sh is the other half of §3's split: sourced by the entry points,
    # never wired. A wired library would exit 0 having inspected nothing — for a
    # fail-closed guard, a silent hole rather than a visible error.
    case "$rel" in
      hooks/lib/*)
        if [ -n "${wired[$rel]:-}" ]; then
          err "$hooks_json wires $rel, but hooks/lib/*.sh are sourced libraries — wire the entry point that sources it instead"
        else
          ok "$plugin_dir does not wire $rel (sourced library)"
        fi
        continue ;;
    esac
    if [ -n "${wired[$rel]:-}" ]; then
      ok "$plugin_dir wires $rel"
    else
      err "$sh_file exists but is not wired in $hooks_json — it never runs"
    fi
  done < <(git ls-files "$plugin_dir/hooks/*.sh")
done < <(git ls-files 'plugins/*/hooks/hooks.json')

# 9. Hook rosters <-> agent `owns-git`/`lane-guarded`, both ways. These hooks
#    gate on a hardcoded name list, which fails OPEN for any name missing from
#    it. See AGENTS.md, "Validating changes".
#
#    Opt-in per plugin, keyed on the fields being declared, so plugins that gate
#    differently are skipped. lane-guard's per-agent
#    dispatch arms are deliberately NOT checked -- nested `case`, and a parser
#    that misread them would report false lockstep.

# Read one `key: value` from a Markdown file's YAML frontmatter.
#
# The key must start at column 1: top-level YAML keys always do, so an indented
# `owns-git:` is a nested key belonging to something else and must not match.
# A trailing `  # comment` is stripped -- YAML requires whitespace before an
# inline comment, so this can't truncate a value that merely contains a `#`.
fm_field() {
  awk -v key="$2" '
    /^---[[:space:]]*$/ { if (in_fm == 0) { in_fm = 1; next } else exit }
    in_fm && index($0, key ":") == 1 {
      sub(/^[^:]*:[[:space:]]*/, "")
      sub(/[[:space:]]+#.*$/, "")
      sub(/[[:space:]]*$/, "")
      print; exit
    }
  ' "$1"
}

# True when the key is present in frontmatter at all, whatever its value.
# Opt-in must key on presence, not value: `owns-git:` with an empty value would
# otherwise skip §9 for the whole plugin rather than failing the empty value.
fm_has_key() {
  awk -v key="$2" '
    /^---[[:space:]]*$/ { if (in_fm == 0) { in_fm = 1; next } else exit }
    in_fm && index($0, key ":") == 1 { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

# Read the `a|b|c)` case arm introduced by a `# crew-roster: <name>` marker, as
# space-separated names.
#
# The scan is pinned rather than "first arm-looking line after the marker":
# these hooks contain other case statements, so an unbounded scan would silently
# read the wrong roster when the arm's formatting changes. Pinned means the
# marker's comment block, then `case ... in`, then the arm on the very next line.
# Anything else yields nothing, which the caller reports as unparseable.
roster_arm() {
  awk -v marker="# crew-roster: $2" '
    index($0, marker) == 1 { found = 1; next }
    !found { next }
    /^[[:space:]]*#/ { next }                       # rest of the marker comment
    /^[[:space:]]*$/ { next }
    !seen_case {                                    # must be the case header
      if ($0 ~ /^[[:space:]]*case[[:space:]]/) { seen_case = 1; next }
      exit
    }
    {                                               # the very next line is the arm
      if ($0 ~ /^[[:space:]]*[A-Za-z0-9_|-]+\)/) {
        sub(/^[[:space:]]*/, ""); sub(/\).*$/, ""); gsub(/\|/, " "); print
      }
      exit
    }
  ' "$1"
}

while IFS= read -r plugin_manifest; do
  plugin_dir="${plugin_manifest%/.claude-plugin/plugin.json}"
  agents=()
  while IFS= read -r a; do [ -n "$a" ] && agents+=("$a"); done \
    < <(git ls-files "$plugin_dir/agents/*.md")
  [ "${#agents[@]}" -eq 0 ] && continue

  # Does this plugin opt in? (any agent declaring the field)
  declares_git=0 declares_lane=0
  for agent in "${agents[@]}"; do
    fm_has_key "$agent" owns-git && declares_git=1
    fm_has_key "$agent" lane-guarded && declares_lane=1
  done

  if [ "$declares_git" -eq 1 ]; then
    hook="$plugin_dir/hooks/bash-safety.sh"
    # Not `arm="$([ -f ... ] && ...)"`: a missing hook makes the substitution
    # exit non-zero, which under `set -e` aborts the whole validator.
    arm=""
    if [ -f "$hook" ]; then arm="$(roster_arm "$hook" no-git)"; fi
    read -ra arm_names <<<"$arm"
    if [ -z "$arm" ]; then
      err "$plugin_dir agents declare 'owns-git' but $hook has no parseable '# crew-roster: no-git' marker + case arm; cannot verify the no-git roster"
    else
      declare -A no_git=() git_seen=()
      for n in "${arm_names[@]}"; do
        [ -n "${no_git[$n]:-}" ] && err "$hook no-git roster names '$n' more than once"
        no_git["$n"]=1
      done
      owners=()
      for agent in "${agents[@]}"; do
        aname="$(basename "$agent" .md)"
        owns="$(fm_field "$agent" owns-git)"
        case "$owns" in
          true|false) ;;
          "") err "$agent has no 'owns-git' (sibling agents declare it); add 'owns-git: true|false'"; continue ;;
          *) err "$agent has 'owns-git: $owns'; expected true or false"; continue ;;
        esac
        [ "$owns" = true ] && owners+=("$aname")
        git_seen["$aname"]=1
        # Bash-less agents can't run git at all, so they need no roster entry.
        has_bash=0
        case ",$(fm_field "$agent" tools | tr -d ' ')," in *,Bash,*) has_bash=1 ;; esac
        if [ "$owns" = true ]; then
          if [ -n "${no_git[$aname]:-}" ]; then
            err "$hook lists the git owner '$aname' in its no-git roster; remove it or flip 'owns-git' in $agent"
          else
            ok "$aname owns git and is absent from $hook's no-git roster"
          fi
        elif [ "$has_bash" -eq 1 ]; then
          if [ -n "${no_git[$aname]:-}" ]; then
            ok "$hook no-git roster covers Bash-capable '$aname'"
          else
            err "$hook has no no-git roster entry for '$aname' (owns-git: false, has Bash); it would run git unguarded -- add it to the arm"
          fi
        elif [ -n "${no_git[$aname]:-}" ]; then
          err "$hook lists '$aname' in its no-git roster, but $agent has no Bash tool; remove the dead entry"
        else
          ok "$aname has no Bash tool (no no-git roster entry required)"
        fi
      done
      if [ "${#owners[@]}" -ne 1 ]; then
        err "$plugin_dir/agents must declare exactly one agent with 'owns-git: true' (found ${#owners[@]}: ${owners[*]:-none})"
      fi
      for n in "${arm_names[@]}"; do
        if [ -z "${git_seen[$n]:-}" ]; then
          err "$hook no-git roster entry '$n' does not match any $plugin_dir/agents/*.md; remove the stale name"
        fi
      done
    fi
  fi

  if [ "$declares_lane" -eq 1 ]; then
    hook="$plugin_dir/hooks/lane-guard.sh"
    arm=""
    if [ -f "$hook" ]; then arm="$(roster_arm "$hook" lane-guarded)"; fi
    read -ra arm_names <<<"$arm"
    if [ -z "$arm" ]; then
      err "$plugin_dir agents declare 'lane-guarded' but $hook has no parseable '# crew-roster: lane-guarded' marker + case arm; cannot verify the lane roster"
    else
      declare -A laned=() lane_seen=()
      for n in "${arm_names[@]}"; do
        [ -n "${laned[$n]:-}" ] && err "$hook lane roster names '$n' more than once"
        laned["$n"]=1
      done
      for agent in "${agents[@]}"; do
        aname="$(basename "$agent" .md)"
        lg="$(fm_field "$agent" lane-guarded)"
        case "$lg" in
          true|false) ;;
          "") err "$agent has no 'lane-guarded' (sibling agents declare it); add 'lane-guarded: true|false'"; continue ;;
          *) err "$agent has 'lane-guarded: $lg'; expected true or false"; continue ;;
        esac
        lane_seen["$aname"]=1
        if [ "$lg" = true ] && [ -z "${laned[$aname]:-}" ]; then
          err "$agent declares 'lane-guarded: true' but $hook's roster omits '$aname'; it would write outside any lane -- add it to the arm"
        elif [ "$lg" = false ] && [ -n "${laned[$aname]:-}" ]; then
          err "$hook's roster lists '$aname' but $agent declares 'lane-guarded: false'; drop one side"
        else
          ok "$aname lane-guarded: $lg matches $hook's roster"
        fi
      done
      for n in "${arm_names[@]}"; do
        if [ -z "${lane_seen[$n]:-}" ]; then
          err "$hook lane roster entry '$n' does not match any $plugin_dir/agents/*.md; remove the stale name"
        fi
      done
    fi
  fi
done < <(git ls-files 'plugins/*/.claude-plugin/plugin.json')

# 10. Every `<plugin>:<name>` in prose must resolve to an agent or command file
#     (§2g does this for `skills:` frontmatter). Namespaces no plugin here
#     declares are ignored. See AGENTS.md, "Validating changes".
plugin_names=""
while IFS= read -r m; do
  d="${m%/.claude-plugin/plugin.json}"
  plugin_names="$plugin_names ${d##*/}"
done < <(git ls-files 'plugins/*/.claude-plugin/plugin.json')

while IFS= read -r doc; do
  # A leading delimiter stands in for `\b`, which is a GNU extension (AGENTS.md:
  # stay BSD/macOS-portable); sed drops it again. Without it, `xcrew:tank` would
  # match the `crew:tank` inside it.
  # `|| true`: grep's exit 1 on no match would abort the run under `set -e`.
  refs="$(grep -ohE '(^|[^A-Za-z0-9_-])('"$(echo "$plugin_names" | tr -s ' ' '|' | sed 's/^|//; s/|$//')"'):[a-z][a-z0-9-]*' "$doc" 2>/dev/null \
    | sed 's/^[^A-Za-z]//' | sort -u || true)"
  [ -z "$refs" ] && continue
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    rp="${ref%%:*}"; rn="${ref##*:}"
    if [ -f "plugins/$rp/agents/$rn.md" ] || [ -f "plugins/$rp/commands/$rn.md" ]; then
      ok "$doc -> $ref resolves"
    else
      err "$doc references '$ref' but no plugins/$rp/agents/$rn.md or plugins/$rp/commands/$rn.md exists"
    fi
  done <<<"$refs"
done < <(git ls-files 'plugins/*/agents/*.md' 'plugins/*/commands/*.md' 'plugins/*/skills/*/SKILL.md')

# 11. init.md §1 (the declared source of truth for crew config slots) <-> the
#     frontmatter keys of this repo's own `.claude/crew.md`, both directions.
#     Reads only the two exact shapes below -- a `- **Slot** (`key`) —` bullet
#     under §1, and a top-level `key:` inside the config file's frontmatter --
#     so bold used for emphasis isn't read as a slot, and a key named in the
#     file's prose body isn't read as configuration. See AGENTS.md, "Validating
#     changes".
init_cmd="plugins/crew/commands/init.md"
crew_cfg=".claude/crew.md"
if [ -f "$init_cmd" ] && [ -f "$crew_cfg" ]; then
  # A slot declares its key in backticked parentheses; that is what the config
  # file carries, so the key -- not the prose label -- is what must agree.
  # The backticks in the sed script are literal markdown to match, not command
  # substitution, so single quotes are exactly right here.
  # shellcheck disable=SC2016
  init_slots="$(sed -n '/^## 1\./,/^## 2\./p' "$init_cmd" \
    | sed -n 's/^- \*\*[^*]*\*\* (`\([A-Za-z][A-Za-z0-9]*\)`) —.*/\1/p')"
  # Frontmatter only: from the opening `---` to the closing one. The body is
  # free-text notes, and a key mentioned there is prose, not configuration.
  cfg_keys="$(awk 'NR==1 && $0=="---"{inside=1; next} inside && $0=="---"{exit} inside' "$crew_cfg" \
    | sed -n 's/^\([A-Za-z][A-Za-z0-9]*\):.*/\1/p')"
  if [ -z "$init_slots" ]; then
    err "$init_cmd has no parseable slot list under '## 1.' (expected '- **<Slot>** (\`key\`) — ...' lines, with an em dash); cannot verify $crew_cfg"
  elif [ -z "$cfg_keys" ]; then
    err "$crew_cfg has no frontmatter keys; $init_cmd §1 declares slots that reconcile must write there"
  else
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      if grep -qxF "$s" <<<"$cfg_keys"; then
        ok "crew config slot '$s' present in $crew_cfg"
      else
        err "$init_cmd §1 declares slot key '$s' but $crew_cfg has no '$s:' key; /crew:init would write a slot this repo's own config never carries"
      fi
    done <<<"$init_slots"
    while IFS= read -r u; do
      [ -z "$u" ] && continue
      grep -qxF "$u" <<<"$init_slots" || \
        err "$crew_cfg carries '$u:', which is not a slot in $init_cmd §1 (the declared source of truth); add it there or drop it here"
    done <<<"$cfg_keys"
  fi
fi

# 12. Always-loaded context footprint per agent: the agent file plus every skill
#     its frontmatter preloads is in the window on every run, so the repo measures
#     what it preaches to workers (`context-discipline`). The number is always
#     reported; an agent may also declare `loaded-lines-cap: <n>` to fail CI past
#     a chosen budget, so raising it is a visible frontmatter edit rather than
#     silent creep. See AGENTS.md, "Prompt design rationale".
#
#     Unresolvable skill refs are §2g's failure: skipped here, so one typo yields
#     one error.

# Line count of a file, or empty if missing/unreadable. Always exits 0: a
# non-zero status inside the callers' `$(...)` assignments would trip `set -e`
# and kill the validator before it could report the unreadable file.
file_lines() {
  if [ -f "$1" ] && [ -r "$1" ]; then awk 'END { print NR }' "$1"; fi
  return 0
}

# Skill name -> SKILL.md path, indexed via git ls-files exactly like §2g, so
# both sections share one staging rule (see the plugin CLAUDE.md gotcha).
# A name shipped by several plugins keeps the first path found.
declare -A skill_file=()
while IFS= read -r skill_md; do
  sname="$(basename "$(dirname "$skill_md")")"
  [ -n "${skill_file[$sname]:-}" ] || skill_file["$sname"]="$skill_md"
done < <(git ls-files 'plugins/*/skills/*/SKILL.md')

# The frontmatter `skills:` list, one name per line (§2g's parser, reused).
agent_skill_refs() {
  awk '
    BEGIN { in_fm = 0; in_skills = 0 }
    /^---[[:space:]]*$/ {
      if (in_fm == 0) { in_fm = 1; next }
      else { exit }
    }
    in_fm && in_skills {
      if ($0 ~ /^[[:space:]]+-[[:space:]]+/) {
        sub(/^[[:space:]]+-[[:space:]]+/, "")
        sub(/[[:space:]]+#.*$/, "")
        sub(/[[:space:]]+$/, "")
        gsub(/^["\047]|["\047]$/, "")
        if (length($0)) print
        next
      } else if ($0 !~ /^[[:space:]]*$/) {
        in_skills = 0
      }
    }
    in_fm && /^skills:[[:space:]]*$/ { in_skills = 1 }
  ' "$1"
}

while IFS= read -r agent; do
  agent_lines="$(file_lines "$agent")"
  if [ -z "$agent_lines" ]; then
    err "$agent could not be read to measure its loaded footprint"
    continue
  fi
  skill_lines=0 skills_readable=1
  while IFS= read -r skill_ref; do
    [ -z "$skill_ref" ] && continue
    # An unresolved ref is already a §2g failure; don't double-report it.
    resolved="${skill_file[$skill_ref]:-}"
    [ -z "$resolved" ] && continue
    n="$(file_lines "$resolved")"
    if [ -z "$n" ]; then
      # A resolved-but-unreadable skill must fail loudly: silently counting it
      # as 0 lines could under-count the footprint straight past a cap.
      err "$agent preloads '$skill_ref' but $resolved could not be read; cannot verify the loaded footprint"
      skills_readable=0
      continue
    fi
    skill_lines=$((skill_lines + n))
  done < <(agent_skill_refs "$agent")
  [ "$skills_readable" -eq 1 ] || continue
  footprint=$((agent_lines + skill_lines))
  ok "$agent loaded footprint: $footprint lines (agent $agent_lines + skills $skill_lines)"

  # The cap is opt-in, but a present-and-unusable value is a hard failure: a
  # check that can't parse its own threshold cannot verify its claim.
  fm_has_key "$agent" loaded-lines-cap || continue
  cap="$(fm_field "$agent" loaded-lines-cap)"
  case "$cap" in
    "") err "$agent has an empty 'loaded-lines-cap'; give it a number or remove the key" ;;
    *[!0-9]*) err "$agent has 'loaded-lines-cap: $cap'; expected a plain line count" ;;
    *)
      if [ "$footprint" -le "$cap" ]; then
        ok "$agent loaded footprint $footprint within its cap of $cap"
      else
        err "$agent loaded footprint $footprint exceeds its 'loaded-lines-cap: $cap' (agent $agent_lines + skills $skill_lines); trim the prompt (AGENTS.md, 'Prompt design rationale') or raise the cap deliberately in its frontmatter"
      fi
      ;;
  esac
done < <(git ls-files 'plugins/*/agents/*.md')

# 13. MCP entries in an agent's frontmatter `tools:` must be server-scoped, and
#     every bare server key must be paired with its plugin-scoped twin. Tools from
#     a plugin-bundled MCP server are named `mcp__plugin_<plugin>_<server>__<tool>`,
#     so a bare `mcp__<key>` grant never matches them: the same server installed
#     as a plugin reads to the agent as "not configured" rather than as denied.
#     Carrying both forms is what keeps an agent working under either install
#     path. See the crew README, "Server keys map to tool namespaces".
#
#     Hosted connectors can't be plugin-installed, so they are exempt from the
#     pairing rule -- a plugin twin would assert a namespace that cannot exist.
#     Each surfaces under two namespaces: `claude_ai_<Display Name>` in the CLI
#     and the bare display name on claude.ai, so the agents allowlist both.
mcp_connector_only=" claude_ai_Figma Figma claude_ai_GitHub GitHub claude_ai_Linear Linear claude_ai_Atlassian Atlassian claude_ai_Sentry Sentry "

# Every `tools:` entry, one per line, from either YAML shape: the inline comma
# list the agents here use, or a `  - name` block list. Reading only the inline
# form would let a list-form `tools:` skip this section silently.
#
# `Agent(crew:tank, crew:trinity)` splits across commas too; those fragments
# aren't MCP entries, and the `mcp__` filter below drops them.
agent_tools_entries() {
  awk '
    /^---[[:space:]]*$/ { if (in_fm == 0) { in_fm = 1; next } else exit }
    in_fm && in_list {
      if ($0 ~ /^[[:space:]]+-[[:space:]]+/) {
        sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]+#.*$/, ""); print; next
      } else if ($0 !~ /^[[:space:]]*$/) { in_list = 0 }
    }
    in_fm && index($0, "tools:") == 1 {
      # A trailing YAML comment is dropped before the split, or it would ride
      # along on the last entry and be read as part of a server name.
      v = $0; sub(/^tools:[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v)
      if (length(v)) { n = split(v, a, ","); for (i = 1; i <= n; i++) print a[i] }
      else { in_list = 1 }
    }
  ' "$1"
}

# ...narrowed to the MCP grants, with any trailing `__*` wildcard dropped:
# `mcp__x` and `mcp__x__*` name the same server.
agent_mcp_entries() {
  agent_tools_entries "$1" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep '^mcp__' \
    | sed 's/^\(mcp__..*\)__\*$/\1/' || true
}

while IFS= read -r agent; do
  entries="$(agent_mcp_entries "$agent")"
  [ -z "$entries" ] && continue

  # A tool-scoped grant (`mcp__server__tool`) silently withholds the rest of the
  # server's tools; the convention here is server-scoped entries only. Checked
  # first so a malformed entry isn't then read as a server name below.
  scoped_ok=1
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    case "${e#mcp__}" in
      '*')
        # `mcp__*` is a disallowedTools shape; as a grant it names no server, so
        # it would silently match nothing. Report it instead of skipping it.
        err "$agent tools -> 'mcp__*' names no server; allowlist each server it stands for"
        scoped_ok=0
        ;;
      *__*)
        srv="${e#mcp__}"; srv="${srv%%__*}"
        err "$agent tools -> '$e' grants a single MCP tool; allowlist the whole server as 'mcp__$srv'"
        scoped_ok=0
        ;;
    esac
  done <<<"$entries"
  [ "$scoped_ok" -eq 1 ] || continue

  # The two grant forms, each space-delimited for membership tests. A plugin and
  # the server it bundles are keyed independently -- `chrome-devtools-mcp` ships
  # `chrome-devtools` -- so the halves are matched by suffix rather than by
  # assuming the names are equal: `plugin_<anything>_<key>` is the plugin form of
  # `<key>`, and the trailing space anchors that suffix to the end of an entry.
  bare_keys="" plugin_keys=""
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    case "$s" in
      plugin_*) plugin_keys="$plugin_keys $s " ;;
      *) bare_keys="$bare_keys $s " ;;
    esac
  done < <(printf '%s\n' "$entries" | sed 's/^mcp__//')

  while IFS= read -r k; do
    [ -z "$k" ] && continue
    case "$mcp_connector_only" in
      *" $k "*)
        ok "$agent tools -> mcp__$k is connector-only; no plugin form expected"
        continue
        ;;
    esac
    case "$plugin_keys " in
      *"_$k "*) ok "$agent tools -> mcp__$k has its plugin form" ;;
      *) err "$agent tools -> 'mcp__$k' covers only a server keyed in .mcp.json; add the plugin form 'mcp__plugin_<plugin>_$k' so the same server installed as a plugin resolves too (its tools are named mcp__plugin_<plugin>_<server>__<tool>)" ;;
    esac
  done < <(printf '%s\n' "$bare_keys" | tr ' ' '\n')

  # ...and the reverse, so a plugin form can't stand alone: whichever way the
  # user installed it, the other path must resolve too.
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    p_matched=0
    while IFS= read -r k; do
      [ -z "$k" ] && continue
      case "$p" in *"_$k") p_matched=1; break ;; esac
    done < <(printf '%s\n' "$bare_keys" | tr ' ' '\n')
    [ "$p_matched" -eq 1 ] && continue
    err "$agent tools -> 'mcp__$p' names a server no bare key covers; add 'mcp__<server>' for its .mcp.json install path"
  done < <(printf '%s\n' "$plugin_keys" | tr ' ' '\n')
done < <(git ls-files 'plugins/*/agents/*.md')

# 14. Frontmatter parses as YAML. A plain (unquoted) scalar cannot contain a
#     colon followed by whitespace: YAML reads it as a nested mapping, the whole
#     block fails to load, and a loader then sees an agent, command or skill with
#     no `name` and no `description` at all. Prose descriptions fall into this
#     naturally -- "Read-only: it investigates and reports" is the shape -- and
#     the file still looks right, so nothing about the failure is visible while
#     authoring. No other section here catches it either: they all read
#     frontmatter key by key with awk rather than parsing the block.
#
#     Targeted rather than a real parse: this repo ships no YAML dependency, and
#     the colon trap is the whole class that a hand-written description hits. A
#     value that opens with a quote, a block scalar (`|`, `>`), a flow collection
#     or an anchor/tag indicator has already declared its type, so it is left to
#     YAML's own rules.
while IFS= read -r f; do
  # A staged-but-deleted file is still listed here; awk would die on it and take
  # the whole run down under `set -e`, so report it and keep going.
  if [ ! -r "$f" ]; then
    err "$f could not be read to check its frontmatter"
    continue
  fi
  offenders="$(awk '
    /^---[[:space:]]*$/ { if (in_fm == 0) { in_fm = 1; next } else exit }
    in_fm && /^[A-Za-z][A-Za-z0-9_-]*:/ {
      key = $0
      sub(/:.*$/, "", key)
      val = $0
      sub(/^[A-Za-z][A-Za-z0-9_-]*:[[:space:]]*/, "", val)
      if (val == "") next
      if (index("\"\047|>[{&*!#", substr(val, 1, 1))) next
      # Name the pattern that fired: the two read differently to whoever has to
      # find it, and "colon+space" sends them hunting for a space that a
      # trailing colon does not have.
      if (val ~ /:[[:space:]]/) print FNR " " key " a colon before whitespace"
      else if (val ~ /:$/)      print FNR " " key " a trailing colon"
    }
  ' "$f")"
  if [ -z "$offenders" ]; then
    ok "frontmatter parses as YAML: $f"
  else
    while read -r lineno key reason; do
      err "$f:$lineno frontmatter '$key' is an unquoted scalar carrying $reason; YAML reads that as a nested mapping and drops the whole block (the file loads with no name and no description). Wrap the value in double quotes."
    done <<< "$offenders"
  fi
done < <(git ls-files 'plugins/*/agents/*.md' 'plugins/*/commands/*.md' 'plugins/*/skills/*/SKILL.md' '.claude/crew.md')

if [ "$fail" -ne 0 ]; then
  echo "Plugin validation failed." >&2
  exit 1
fi
echo "Plugin validation passed."
