#!/usr/bin/env bash
# Context-hygiene guard (not a security guard): blocks raw reads of very large
# files. Fails OPEN — a missing library or jq, or a path that is absent or not a
# regular file, skips the check rather than blocking.
#
# The limits live in hooks/lib/guard-lib.sh.
_lib="${BASH_SOURCE[0]%/*}/lib/guard-lib.sh"
# shellcheck disable=SC1090,SC1091  # resolved at runtime
. "$_lib" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

guard_read_payload
# One jq pass for both fields; the path is the untrusted one (see guard_jq2).
guard_jq2 '(.tool_input.file_path // .tool_input.path) // ""' '(.tool_input.limit // "") | tostring' || exit 0
# shellcheck disable=SC2154  # set by guard_jq2 in the library sourced above
path="$guard_untrusted"
# shellcheck disable=SC2154
limit="$guard_trusted"

if [ -z "$path" ] || [ ! -f "$path" ]; then
  exit 0
fi

# An explicit `limit` of at most GUARD_READ_MAX_BOUNDED_LINES lines is the
# bounded, targeted read context-discipline asks for, so it passes at any file
# size. A larger or non-numeric limit falls through to the size check: fail-open
# is for missing inputs, not for a bound the guard can't trust.
case "$limit" in
  ''|*[!0-9]*) ;;
  *) if [ "$limit" -gt 0 ] && [ "$limit" -le "$GUARD_READ_MAX_BOUNDED_LINES" ]; then exit 0; fi ;;
esac

size=$(wc -c < "$path" 2>/dev/null || echo 0)
if [ "$size" -gt "$GUARD_READ_MAX_BYTES" ]; then
  echo "Blocked: $path is ${size} bytes. Don't read it raw — pass an explicit limit (<= ${GUARD_READ_MAX_BOUNDED_LINES} lines) for the slice you need, or grep/jq/script it and surface only the result (see context-discipline)." >&2
  exit 2
fi
exit 0
