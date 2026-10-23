# board

A local kanban board of every Claude Code session on your machine. It answers three questions:
which sessions need you now, what is running and where, and what you worked on yesterday and how
to get back into it.

```bash
claude plugin marketplace add johantor/crew
claude plugin install board@johantor
```

Then, in any Claude Code session, run `/board:open`. It starts the server in the background and
opens `http://127.0.0.1:7428/?t=<token>`. The token keeps other users on the machine out. The
page moves it into the browser's local storage for that port, so a bookmark of
`http://127.0.0.1:7428/` works after that.

## The columns

| Column | A card is here when |
|---|---|
| Needs me | A permission prompt, a question, or an API error waits for you. |
| Working | Claude is on a turn. A `stale?` badge marks a card silent for 10 minutes. |
| Your turn | The turn ended and Claude waits for your next prompt. |
| Closed today | The session ended today. A session silent for 12 hours counts as ended. |
| Earlier | It ended before today, within the last 7 days. Search reaches back 30 days (`--days`). |

Each card shows the title (a `/rename` name, else the first prompt), the repo and branch, the
latest activity, and how long ago it happened. **Copy resume** (or a click on the card) copies
`cd '<dir>'; claude --resume <id>`, which runs in bash, zsh and PowerShell. The quotes are single,
so a folder name cannot run code when you paste it. A folder name with a character outside
letters, digits and plain ASCII punctuation (a quote of any kind, a tab) gets no `cd`, and the
board says so. **More** shows the
last reply, the last tool calls and the subagents. **Archive** hides a card; the **Archived**
filter brings it back.

**Subagents are not cards.** A subagent runs inside its parent session, so it shows on that
session's card: each running subagent with its current tool, plus a count of finished ones. A
subagent's permission prompt moves the parent card to Needs me. The card stays there while any
question is open, the session's own or a subagent's, and each closes only with its own answer.
Sessions that run a `crew:` agent get a Crew badge, and the Crew filter shows them alone.

The theme follows the browser until you pick Light or Dark; the choice is saved in the browser.

## How it works

1. Hooks on 12 session events run `hooks/capture.sh`, which hands the payload to Node. Node
   distills it to one short line and appends it to `~/.claude/board/events.jsonl`. Ten hooks are
   async and never block a session. Two run in the foreground, for up to 5 seconds:
   `PermissionRequest`, so its line lands before the tool runs (it adds about 0.1 s before the
   prompt shows), and `SessionEnd`, so its line lands before Claude Code exits. None fails a
   session: no Node, a bad payload or a full disk all exit 0.
2. The server replays that log into cards and tails it every second. It writes to the same file
   only when you archive a card.
3. On start, and every 5 minutes, it reads the session transcripts under `~/.claude/projects`
   (only the first and last 256 KiB of each). That fills the board with sessions from before the
   plugin.

The hooks write a file, not to the server, so no event is lost while the server is down.

## Options

```bash
node <plugin dir>/server/board.mjs [--port 7428] [--days 30] [--detach] [--open]
```

| Setting | Default | Effect |
|---|---|---|
| `--port`, `CLAUDE_BOARD_PORT` | `7428` | The server's port. The hooks do not use it. |
| `--days` | `30` | How far back the board loads sessions. |
| `CLAUDE_BOARD_DIR` | `~/.claude/board` | Where the event log and the token live. Set it for the hooks too. |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Where the transcripts are read from. |

To reset the board, stop the server and delete `events.jsonl`. History comes back from the
transcripts.

## Privacy

Prompts and replies can hold client code and secrets, so the board stays on your machine. The
server listens on 127.0.0.1 only and refuses a request that names another host. Every request for
session data needs the token from `~/.claude/board/token` (mode 600), since 127.0.0.1 is open to
every user on the machine. The token goes only as a header (as `?t=` on the live stream), never as
a cookie, which the browser would also send to other ports on 127.0.0.1. `/board:open` checks for
a running board by having it sign a random value with the token, so a program squatting on the
port never receives the token. Archiving takes a JSON request from the board's own origin. The log is
written with mode 600, and each line keeps at most the first 200 characters of a prompt and 300
of a reply. Nothing is sent anywhere.

Repo and branch come from `.git/HEAD`, read as a file. The hook skips a `.git` another user owns
and a `HEAD` that is not a plain file, so a planted FIFO cannot hang it.

## Requirements

Node.js 18 or later on the `PATH` that Claude Code's hooks see. On Windows the hook needs Git for
Windows: without Git Bash, Claude Code runs command hooks in PowerShell, and `capture.sh` does not
run there.

## Known gaps

- No hook fires when you approve a permission prompt, so the card stays in Needs me until the
  approved tool finishes. A long build shows as Needs me while it runs.
- Esc during a turn fires no `Stop`. The card moves to Your turn when Claude Code reports the
  session idle, about a minute later.
- The event log grows without bound, about 300 bytes per tool call. Delete it to start over.
- The transcript format is not documented. A Claude Code update can break the history read; the
  hooks keep working.
- A session that ran while the plugin was off shows only its history: title, repo and last reply.
- The `/board:open` check that a port holds your board can be fooled by another local user who
  relays it from their port to your board on a second port; `--open` would then open their page
  with your token in the URL. It needs another user on the machine and two of your boards
  running. Run one board, on the default port.
