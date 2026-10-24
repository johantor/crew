#!/usr/bin/env bash
# Prints one version's CHANGELOG section: its `## [X.Y.Z]` heading through the
# line before the next `## [` heading. Those lines are the GitHub Release notes
# (AGENTS.md, "Releasing"). A script rather than inline awk in auto-release.yml
# so it is shellchecked and covered by release.test.sh before a merge.
#   scripts/release-notes.sh . 4.0.1
set -euo pipefail

plugin_dir="${1:-}"
version="${2:-}"
if [ -z "$plugin_dir" ] || [ -z "$version" ]; then
  echo "usage: $0 <plugin-dir> <version>   e.g. $0 . 4.0.1" >&2
  exit 2
fi
changelog="$plugin_dir/CHANGELOG.md"
[ -f "$changelog" ] || { echo "no changelog at $changelog" >&2; exit 1; }

# The closing `]` is part of the match, so 4.0.1 never picks up 4.0.10's section.
notes="$(awk -v ver="## [${version}]" '
  /^## \[/ { if (found) exit; if (index($0, ver) == 1) { found = 1; print; next } }
  found { print }
' "$changelog")"
[ -n "$notes" ] || { echo "no '## [${version}]' section in $changelog" >&2; exit 1; }
printf '%s\n' "$notes"
