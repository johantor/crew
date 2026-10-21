# Changelog

All notable changes to the `board` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-21

### Added

- A local kanban of every Claude Code session; hooks log to `~/.claude/board/events.jsonl` (#318).
- `/board:open` starts the server on 127.0.0.1, behind a per-user token.
- Transcripts in `~/.claude/projects` fill the board with sessions from before the plugin.
- Subagents show on their session's card; a Crew run gets a Crew badge.
- Copy resume copies `cd '<dir>'; claude --resume <id>`; light, dark or browser theme.
