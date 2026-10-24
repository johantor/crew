#!/usr/bin/env bash
# Self-tests for the release scripts (johantor/crew and johantor/board carry the same suite):
#   scripts/check-changelog.sh — a change under plugin/ must bump the version. Diff-driven, so
#     each case builds a throwaway repo with real commits.
#   scripts/release-notes.sh   — one version's CHANGELOG section, the GitHub Release notes.
# Assert on the message, not the exit code, so it is clear which check fired.
# shellcheck source=tests/lib.sh
# shellcheck disable=SC1090,SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# new_gate_repo -> a repo on `main` holding the gate and a plugin in plugin/ (v1.0.0), with a
# `work` branch checked out. The base is local; the script falls back to it.
new_gate_repo() {
  local d
  d="$(new_tmpdir)"
  git init -q -b main "$d" 2>/dev/null \
    || { git init -q "$d"; git -C "$d" symbolic-ref HEAD refs/heads/main; }
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name "Test"
  git -C "$d" config commit.gpgsign false
  mkdir -p "$d/scripts" "$d/plugin/.claude-plugin" "$d/plugin/commands"
  cp "$REPO_ROOT/scripts/check-changelog.sh" "$d/scripts/" || die "cp script failed into $d"
  printf '{"name":"foo","version":"1.0.0"}\n' > "$d/plugin/.claude-plugin/plugin.json"
  printf '# Changelog\n\n## [1.0.0] - 2026-01-01\n\n### Added\n- initial\n' > "$d/CHANGELOG.md"
  printf 'readme v1\n' > "$d/README.md"
  printf 'open v1\n' > "$d/plugin/commands/open.md"
  gate_commit "$d" "initial"
  git -C "$d" checkout -q -b work
  printf '%s' "$d"
}

gate_commit() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -q -m "$2" || die "commit failed in $1"; }

# bump <repo> <version> [changelog: yes|no]
bump() {
  printf '{"name":"foo","version":"%s"}\n' "$2" > "$1/plugin/.claude-plugin/plugin.json"
  if [ "${3:-yes}" = yes ]; then
    printf '# Changelog\n\n## [%s] - 2026-02-02\n\n### Changed\n- bumped\n\n## [1.0.0] - 2026-01-01\n- initial\n' "$2" \
      > "$1/CHANGELOG.md"
  fi
}

run_gate() { _out="$(cd "$1" && bash scripts/check-changelog.sh main 2>&1)" || true; }

assert_out() {    # <label> <substr>
  if [[ "$_out" == *"$2"* ]]; then _pass; else _fail "$1: expected '$2' — output: $_out"; fi
}
assert_no_out() { # <label> <substr>
  if [[ "$_out" != *"$2"* ]]; then _pass; else _fail "$1: unexpectedly emitted '$2'"; fi
}

NOBUMP="without a version bump"

# --- A change under plugin/ needs a bump --------------------------------------
d="$(new_gate_repo)"; printf 'open v2\n' > "$d/plugin/commands/open.md"; gate_commit "$d" "fix: open"
run_gate "$d"; assert_out "bites on a plugin/ change with no bump" "$NOBUMP"

d="$(new_gate_repo)"; mkdir -p "$d/plugin/scripts"; printf 'x\n' > "$d/plugin/scripts/x.sh"; gate_commit "$d" "feat: x"
run_gate "$d"; assert_out "bites on a new file under plugin/" "$NOBUMP"

d="$(new_gate_repo)"; printf 'open v2\n' > "$d/plugin/commands/open.md"; bump "$d" 1.1.0
gate_commit "$d" "feat: open (v1.1.0)"
run_gate "$d"; assert_no_out "silent when the version is bumped" "$NOBUMP"
assert_out "names the bump" "1.0.0 -> 1.1.0"

d="$(new_gate_repo)"; printf 'open v2\n' > "$d/plugin/commands/open.md"; bump "$d" 1.1.0 no
gate_commit "$d" "feat: open (v1.1.0)"
run_gate "$d"; assert_out "a bump needs its changelog entry" "has no '## [1.1.0]' entry"

# Mid-branch: an uncommitted edit counts, so the check is useful before the commit.
d="$(new_gate_repo)"; printf 'open v2\n' > "$d/plugin/commands/open.md"
run_gate "$d"; assert_out "bites on an uncommitted plugin/ change" "$NOBUMP"

# --- Nothing outside plugin/ ships --------------------------------------------
for f in README.md tests/t.sh docs/index.html scripts/x.sh .claude/crew.md .github/x.yml AGENTS.md CLAUDE.md; do
  d="$(new_gate_repo)"; mkdir -p "$d/$(dirname "$f")"; printf 'x\n' >> "$d/$f"; gate_commit "$d" "chore: $f"
  run_gate "$d"; assert_no_out "silent on a $f-only change" "$NOBUMP"
done

# Unrelated commits on main since the branch forked are not this PR's changes.
d="$(new_gate_repo)"; git -C "$d" checkout -q main
printf 'open v2\n' > "$d/plugin/commands/open.md"; gate_commit "$d" "fix: on main"
git -C "$d" checkout -q work; mkdir -p "$d/tests"; printf 'x\n' > "$d/tests/t.sh"
gate_commit "$d" "test: add a case"
run_gate "$d"; assert_no_out "silent when only main moved" "$NOBUMP"

# --- The notes extractor: one version's section, nothing else -----------------
run_notes() { _out="$(bash "$REPO_ROOT/scripts/release-notes.sh" "$1" "$2" 2>&1)" || true; }

d="$(new_tmpdir)"
printf '# Changelog\n\n## [1.0.10] - 2026-03-03\n- ten\n\n## [1.0.1] - 2026-02-02\n\n### Fixed\n- one\n\n## [1.0.0] - 2026-01-01\n- initial\n' \
  > "$d/CHANGELOG.md"
run_notes "$d" 1.0.1
assert_out "notes carry the version's heading" "## [1.0.1]"
assert_out "notes carry the version's bullets" "- one"
assert_no_out "notes stop at the next heading" "- initial"
assert_no_out "1.0.1 does not match the 1.0.10 section above it" "- ten"
run_notes "$d" 9.9.9
assert_out "a missing section is an error, not empty notes" "no '## [9.9.9]' section"

finish
