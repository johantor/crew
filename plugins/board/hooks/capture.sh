#!/usr/bin/env bash
# Hands the hook payload to capture.mjs, which appends it to the board's event
# log. Always exits 0: the board is a view, and a missing Node must not disturb
# the session.
command -v node >/dev/null 2>&1 || exit 0
node "$(dirname "${BASH_SOURCE[0]}")/../server/capture.mjs" || true
exit 0
