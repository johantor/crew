# board — quick reference for agents working on this plugin

Board-specific map. **Keep it accurate: a PR that changes anything stated here updates this file
in the same commit.** Rules shared by every plugin: [AGENTS.md](../../AGENTS.md).

## Map

- `hooks/capture.sh` — the one hook, wired on 11 events in `hooks/hooks.json`, async on all but
  `SessionEnd` (synchronous, `timeout: 5`, so it lands before the process exits). A Bash
  wrapper so validator §3/§6 apply; it execs `server/capture.mjs` and always exits 0.
- `server/capture.mjs` — `distill()` turns a hook payload into one record (`v`, `ts`, `e`,
  `sid`, plus per-event fields); `null` drops events the board ignores, such as an
  `idle_prompt` notification. Strings are clipped so a line stays under 4 KiB: appends from
  several sessions then do not interleave. `gitInfo()` reads `.git/HEAD` as a file, no fork.
- `server/reduce.mjs` — `apply(board, record)` is the fold. Record kinds: hook events, `History`
  (backfill; fills gaps, never overrides a hook), `BoardArchive` (written by the server).
  A record with `aid` is a subagent's: it updates the worker strip and moves the card only to
  and from `needs`.
- `server/history.mjs` — reads the head and tail 256 KiB of each transcript. The format is
  undocumented: every field is optional, a bad line is skipped.
- `server/board.mjs` — the HTTP server, `createTail()` (byte offset, holds a partial line),
  `--detach` (spawns itself detached, waits for `/api/health`). Host allow-list against DNS
  rebinding; `POST /api/archive` needs JSON and no foreign `Origin`.
- `server/public/` — the page. `columns.mjs` holds the time rules (`STALE_MS`, `GONE_MS`) and is
  imported by the page and the tests. The CSP is `default-src 'self'`: no inline script or
  style, so `theme.js` is a file, loaded before paint.
- `commands/open.md` — `/board:open`, runs `board.mjs --detach --open`.
- `tests/capture.test.sh` — the hook end to end, then `node --test tests/*.test.mjs` (reducer,
  columns, history, tail, server). Node is required; a missing one fails the suite.

## Gotchas

- The log path is fixed (`~/.claude/board`, `CLAUDE_BOARD_DIR`), not `CLAUDE_PLUGIN_DATA`: a
  server started from a terminal must find the file the hooks write.
- Async hooks can append slightly out of order. The reducer applies records in file order; a
  `Stop` lands seconds after the turn's last tool call, so a misordered pair is unlikely, and the
  next event corrects the card.
