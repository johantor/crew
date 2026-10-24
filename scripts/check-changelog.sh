#!/usr/bin/env bash
# Fails a PR that changes the plugin without bumping its version.
# `claude plugin update` keys on `version`, and a version's release notes are its
# CHANGELOG section, so an unbumped change ships described nowhere.
#
# Shipped = everything under plugin/: the marketplace installs that directory and
# nothing else. johantor/crew and johantor/board carry the same script.
#   scripts/check-changelog.sh [<branch>]     # default: main
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

base_ref="${1:-${GITHUB_BASE_REF:-main}}"
# Remote-tracking form first: on CI the local branch of the same name is absent or the PR head.
base_sha=""
for candidate in "origin/$base_ref" "$base_ref"; do
  if base_sha="$(git rev-parse --verify --quiet "$candidate^{commit}")"; then break; fi
done
[ -n "$base_sha" ] || { echo "FAIL: cannot resolve base ref '$base_ref'" >&2; exit 1; }
merge_base="$(git merge-base "$base_sha" HEAD)"

manifest="plugin/.claude-plugin/plugin.json"
changed="$(git diff --name-only "$merge_base" -- plugin)"
if [ -z "$changed" ]; then
  echo "Changelog check passed (no shipped changes)."
  exit 0
fi

base_version="$(git show "$merge_base:$manifest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
head_version="$(jq -r '.version // empty' "$manifest")"
if [ "$base_version" = "$head_version" ]; then
  echo "FAIL: shipped files changed without a version bump: bump 'version' in $manifest and add a '## [X.Y.Z]' entry to CHANGELOG.md. Changed: $(printf '%s' "$changed" | tr '\n' ' ')" >&2
  exit 1
fi
grep -qF "## [${head_version}]" CHANGELOG.md || { echo "FAIL: CHANGELOG.md has no '## [${head_version}]' entry" >&2; exit 1; }
echo "Changelog check passed: ${base_version:-none} -> $head_version."
