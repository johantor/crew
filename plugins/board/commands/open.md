---
description: "Start the session board in the background, if it is not running, and open it in the browser."
---

Run this one command with the Bash tool, exactly as written. Pass `$ARGUMENTS` through after it
only when the user gave `--port <n>` or `--days <n>`:

```bash
node "${CLAUDE_PLUGIN_ROOT}/server/board.mjs" --detach --open
```

It prints the board's URL, whether it started the server or found one already running. Report
that URL in one line, as printed: its `?t=` token is what lets the browser in.

If it fails:

- `node: command not found`: the board needs Node.js 18 or later. Say so and stop.
- `Port <n> is in use`: another program holds the port, or another user's board does. Offer
  `--port <other>`; the hooks need no change, since they write a file, not to the port.
- Anything else: show the error as printed and stop. Do not retry in a loop.
