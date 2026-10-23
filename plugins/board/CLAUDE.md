# board — quick reference for agents working on this plugin

Board-specific map. **Keep it accurate: a PR that changes anything stated here updates this file
in the same commit.** Rules shared by every plugin: [AGENTS.md](../../AGENTS.md).

## Map

- `hooks/capture.sh` — the one hook, wired on 12 events in `hooks/hooks.json`, async on all but
  `PermissionRequest` and `SessionEnd` (synchronous, `timeout: 5`: the first lands before its
  tool runs, the second before the process exits; `capture.test.sh` asserts the split). A Bash
  wrapper so validator §3/§6 apply; it runs `node server/capture.mjs` and always exits 0.
- `server/capture.mjs` — `distill()` turns a hook payload into one record (`v`, `ts`, `e`,
  `sid`, plus per-event fields); `null` drops events the board ignores, such as a
  `permission_prompt` notification (PermissionRequest reports it). Strings are clipped so a line stays under 4 KiB: appends from
  several sessions then do not interleave. `gitInfo()` reads `.git/HEAD` as a file, no fork,
  and only a plain file of this user's (`readSmall`): a planted FIFO would block the read.
- `server/reduce.mjs` — `apply(board, record)` is the fold. Record kinds: hook events, `History`
  (backfill; fills gaps, never overrides a hook), `BoardArchive` (written by the server).
  A card keeps the session's own `turn` (`working`/`yourTurn`/`closed`, activity `doing`) apart
  from its `open` questions, keyed by who asked (`''` the session, `!error` a failed turn, else
  a subagent's `aid`) and by tool call: `capture.mjs` writes `call`, a hash of tool name and
  input, on PermissionRequest and PostToolUse(Failure), since PermissionRequest has no
  `tool_use_id`. `derive()` shows `needs` while any question is open, else the turn, so one
  answer never hides another. A PostToolUse closes only its own call's question; SubagentStop
  closes all of that subagent's; `PreToolUse` answers nothing (see Gotchas); an `idle_prompt`
  notification ends a turn that had no `Stop` (Esc, a denied prompt).
- `server/history.mjs` — reads the head and tail 256 KiB of each transcript, and only a file
  whose mtime and size changed since the last scan. The format is undocumented: every field is
  optional, a bad line is skipped.
- `server/paths.mjs` — the fixed paths, and `isMain()`, which compares real paths: a symlinked
  install otherwise never runs its main.
- `server/board.mjs` — the HTTP server, `createTail()` (byte offset, 4 MiB chunks, holds a
  partial line, replays when the file shrinks or its inode changes), `--port 0` for the tests,
  `--detach` (checks the port, spawns itself detached, waits for `/api/health`). Host allow-list
  against DNS rebinding. Session data needs the token in `<board dir>/token` (0600, created
  once), sent as `X-Board-Token`, or as `?t=` on `/api/stream` only (EventSource sets no
  header); never a cookie, which reaches every port on 127.0.0.1. The page takes `?t=` once into
  localStorage (origin-scoped, so per port). `isBoard` sends a nonce and checks the HMAC
  `/api/health` returns, so the token never goes to a squatter on the port. `POST /api/archive` needs JSON and no foreign
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
  transition may depend on their order: that is why `PreToolUse` never leaves `needs`. Order
  that matters is bought with a foreground hook, not inferred: `PermissionRequest` is
  synchronous, so it always precedes its `PostToolUse`, and `SessionEnd` is synchronous and
  final (`ended`) until a new `SessionStart`, so a late async `Stop` cannot reopen the card.
