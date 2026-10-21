# board

A local kanban board of every Claude Code session on your machine. It answers three questions:
which sessions need you now, what is running and where, and what you worked on yesterday and how
to get back into it.

```bash
claude plugin marketplace add johantor/crew
claude plugin install board@johantor
```

Then, in any Claude Code session, run `/board:open`. It starts the server in the background and
opens `http://127.0.0.1:7428/`.

## The columns

| Column | A card is here when |
|---|---|
| Needs me | A permission prompt, a question, or an API error waits for you. |
| Working | Claude is on a turn. A `stale?` badge marks a card silent for 10 minutes. |
| Your turn | The turn ended and Claude waits for your next prompt. |
| Closed today | The session ended today, or went silent 12 hours ago without an end event. |
| Earlier | The last 7 days. Search reaches back 30 days (`--days`). |

Each card shows the title (a `/rename` name, else the first prompt), the repo and branch, the
latest activity, and how long ago it happened. Click a card to copy
`cd "<dir>"; claude --resume <id>`, which runs in bash, zsh and PowerShell. **More** shows the
last reply, the last tool calls and the subagents. **Archive** hides a card; the **Archived**
filter brings it back.

**Subagents are not cards.** A subagent runs inside its parent session, so it shows on that
session's card: each running subagent with its current tool, plus a count of finished ones. A
subagent's permission prompt moves the parent card to Needs me. Sessions that run a `crew:` agent
get a Crew badge, and the Crew filter shows them alone.

The theme follows the browser until you pick Light or Dark; the choice is saved in the browser.

## How it works

1. Async hooks on 11 session events run `hooks/capture.sh`, which hands the payload to Node. Node
   distills it to one short line and appends it to `~/.claude/board/events.jsonl`. The hooks never
   block a session and never fail one: no Node, a bad payload or a full disk all exit 0.
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
| `CLAUDE_BOARD_DIR` | `~/.claude/board` | Where the event log lives. Set it for the hooks too. |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Where the transcripts are read from. |

To reset the board, stop the server and delete `events.jsonl`. History comes back from the
transcripts.

## Privacy

Prompts and replies can hold client code and secrets, so the board stays on your machine. The
server listens on 127.0.0.1 only and refuses a request that names another host. Archiving takes
a JSON request from the board's own origin. The log is written with mode 600, and each line keeps
at most the first 200 characters of a prompt and 300 of a reply. Nothing is sent anywhere.

## Requirements

Node.js 18 or later on the `PATH` that Claude Code's hooks see. On Windows the hooks run in Git
Bash, as every Claude Code command hook does.

## Known gaps

- The event log grows without bound, about 300 bytes per tool call. Delete it to start over.
- The transcript format is not documented. A Claude Code update can break the history read; the
  hooks keep working.
- A session that ran while the plugin was off shows only its history: title, repo and last reply.
