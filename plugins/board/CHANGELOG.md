# Changelog

All notable changes to the `board` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-21

### Added

- A local kanban board of every Claude Code session in five columns: Needs me, Working, Your
  turn, Closed today, Earlier. Async hooks append each session's state to
  `~/.claude/board/events.jsonl`, and `/board:open` starts the server on 127.0.0.1.
- History from `~/.claude/projects` fills Closed today and Earlier with sessions from before the
  board.
- Subagents show on their session's card; a Crew run gets a Crew badge.
- A click copies `cd "<dir>"; claude --resume <id>`. Light, dark or browser theme, saved in the
  browser.
