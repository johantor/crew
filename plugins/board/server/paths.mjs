// Where the board keeps its log, and where Claude Code keeps its transcripts. A
// fixed directory, not CLAUDE_PLUGIN_DATA: a server started from a terminal must
// find the same file the hooks write.
import os from 'node:os';
import path from 'node:path';

export function boardDir() {
  return process.env.CLAUDE_BOARD_DIR || path.join(os.homedir(), '.claude', 'board');
}

export function eventsFile() {
  return path.join(boardDir(), 'events.jsonl');
}

export function projectsDir() {
  const config = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
  return path.join(config, 'projects');
}
