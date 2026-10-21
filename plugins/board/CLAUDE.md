# board — quick reference for agents working on this plugin

Board-specific map. **Keep it accurate: a PR that changes anything stated here updates this file
in the same commit.** Rules shared by every plugin: [AGENTS.md](../../AGENTS.md).

## Map

- `hooks/capture.sh` — the one hook, wired on 12 events in `hooks/hooks.json`, async on all but
  `SessionEnd` (synchronous, `timeout: 5`, so it lands before the process exits). A Bash
  wrapper so validator §3/§6 apply; it runs `node server/capture.mjs` and always exits 0.
- `server/capture.mjs` — `distill()` turns a hook payload into one record (`v`, `ts`, `e`,
  `sid`, plus per-event fields); `null` drops events the board ignores, such as a
  `permission_prompt` notification (PermissionRequest reports it). Strings are clipped so a line stays under 4 KiB: appends from
  several sessions then do not interleave. `gitInfo()` reads `.git/HEAD` as a file, no fork,
  and only a plain file of this user's (`readSmall`): a planted FIFO would block the read.
- `server/reduce.mjs` — `apply(board, record)` is the fold. Record kinds: hook events, `History`
  (backfill; fills gaps, never overrides a hook), `BoardArchive` (written by the server).
  A record with `aid` is a subagent's: it updates the worker strip and moves the card into
  `needs`. `needsBy` records who did: only that subagent's PostToolUse or SubagentStop moves the
  card out, back to the state saved in `before`; the session's own events leave it there.
  `PreToolUse` never leaves `needs` (see Gotchas); an `idle_prompt` notification ends a turn
  that had no `Stop` (Esc, a denied prompt).
- `server/history.mjs` — reads the head and tail 256 KiB of each transcript, and only a file
  whose mtime and size changed since the last scan. The format is undocumented: every field is
  optional, a bad line is skipped.
- `server/paths.mjs` — the fixed paths, and `isMain()`, which compares real paths: a symlinked
  install otherwise never runs its main.
- `server/board.mjs` — the HTTP server, `createTail()` (byte offset, 4 MiB chunks, holds a
  partial line, replays when the file shrinks or its inode changes), `--port 0` for the tests,
  `--detach` (checks the port, spawns itself detached, waits for `/api/health`). Host allow-list
  against DNS rebinding. Session data needs the token in `<board dir>/token` (0600, created
  once): `/?t=` sets an HttpOnly cookie, `X-Board-Token` works for scripts, and `isBoard` sends
  it, so a squatter on the port reads as busy. `POST /api/archive` needs JSON and no foreign
  `Origin`. `/api/stream` opens with a full `state` event and then sends changed `cards`; the
  page loads from the stream alone, so no push falls between a snapshot and the subscribe.
- `server/public/` — the page. `columns.mjs` (the time rules, `STALE_MS`, `GONE_MS`) and
  `resume.mjs` (the copied command, single-quoted) are imported by the page and the tests. The
  CSP is `default-src 'self'`: no inline script or style, so `theme.js` is a file, loaded
  before paint. `app.mjs` rebuilds a card only when its content changes and puts focus back on
  the same button (`data-action`): a push arrives every second while a session works.
- `commands/open.md` — `/board:open`, runs `board.mjs --detach --open`.
- `tests/capture.test.sh` — the hook end to end, then `node --test tests/*.test.mjs` (reducer,
  columns, history, tail, server). Node is required; a missing one fails the suite.

## Gotchas

- The log path is fixed (`~/.claude/board`, `CLAUDE_BOARD_DIR`), not `CLAUDE_PLUGIN_DATA`: a
  server started from a terminal must find the file the hooks write.
- Async hooks append out of order. A `PreToolUse` and the `PermissionRequest` of the same call
  are milliseconds apart and land inverted often (a review measured up to 25 of 60), so no
  transition may depend on their order: that is why `PreToolUse` never leaves `needs`. A `Stop`
  lands seconds after the turn's last tool call, so that pair is unlikely to invert.
