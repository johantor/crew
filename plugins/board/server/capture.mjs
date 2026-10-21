// Hook entry: reads one Claude Code hook payload on stdin and appends a distilled
// record to <board dir>/events.jsonl. The server tails that file, so an event is
// kept even while the server is down. Never fails the hook: every error exits 0.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { boardDir, eventsFile, isMain } from './paths.mjs';

// One line stays well under 4 KiB so concurrent appends from several sessions do
// not interleave; the clip limits below keep it there.
const CLIP = { prompt: 200, msg: 300, tool: 120 };

export function clip(text, max) {
  if (typeof text !== 'string') return undefined;
  const flat = text.replace(/\s+/g, ' ').trim();
  return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat;
}

function relPath(file, cwd) {
  if (typeof file !== 'string') return '';
  // `/w/shop-api/a.ts` is not inside `/w/shop`: the next character must be a separator.
  if (cwd && file.startsWith(cwd) && /^[\\/]/.test(file.slice(cwd.length))) {
    const rel = file.slice(cwd.length).replace(/^[\\/]+/, '');
    if (rel) return rel;
  }
  return file;
}

// A tool call as one short line: what the card's activity row shows.
export function summarizeTool(name, input, cwd) {
  const i = input && typeof input === 'object' ? input : {};
  let detail = '';
  switch (name) {
    case 'Bash':
    case 'PowerShell':
      detail = String(i.command ?? '').split('\n')[0];
      break;
    case 'Read':
    case 'Edit':
    case 'MultiEdit':
    case 'Write':
    case 'NotebookEdit':
      detail = relPath(i.file_path ?? i.notebook_path, cwd);
      break;
    case 'Grep':
    case 'Glob':
      detail = String(i.pattern ?? '');
      break;
    case 'Agent':
    case 'Task':
      detail = [i.subagent_type, i.description].filter(Boolean).join(': ');
      break;
    case 'WebFetch':
      detail = String(i.url ?? '');
      break;
    case 'WebSearch':
      detail = String(i.query ?? '');
      break;
    default: {
      const mcp = /^mcp__(.+?)__(.+)$/.exec(name ?? '');
      if (mcp) return clip(`${mcp[1]}: ${mcp[2]}`, CLIP.tool);
    }
  }
  return clip(detail ? `${name} ${detail}` : String(name ?? 'tool'), CLIP.tool);
}

const UID = typeof process.getuid === 'function' ? process.getuid() : -1;

// Reads the start of a small regular file the user owns. A FIFO, a device or a
// symlink planted as `.git/HEAD` would otherwise block the read forever.
function readSmall(file) {
  const st = fs.lstatSync(file);
  if (!st.isFile() || (UID >= 0 && st.uid !== UID)) throw new Error('not a plain file of ours');
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(256);
    return buf.subarray(0, fs.readSync(fd, buf, 0, buf.length, 0)).toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
}

// Repo and branch from the nearest .git, read as files: no git process per event.
// A `.git` another user owns is skipped, as git's safe.directory does.
export function gitInfo(cwd) {
  if (typeof cwd !== 'string' || !cwd) return {};
  let dir = path.resolve(cwd);
  for (;;) {
    const dotgit = path.join(dir, '.git');
    let stat;
    try {
      stat = fs.lstatSync(dotgit);
    } catch {
      stat = null;
    }
    if (stat && (UID < 0 || stat.uid === UID) && (stat.isFile() || stat.isDirectory())) {
      let gitDir = dotgit;
      let repoRoot = dir;
      let branch;
      try {
        if (stat.isFile()) {
          // A worktree or submodule: `.git` names the real git dir.
          const m = /^gitdir:\s*(.+)$/m.exec(readSmall(dotgit));
          if (!m) return { repo: path.basename(dir) };
          gitDir = path.resolve(dir, m[1].trim());
          // <main>/.git/worktrees/<name> → name the repo after <main>.
          const wt = /[\\/]\.git[\\/]worktrees[\\/][^\\/]+$/.exec(gitDir);
          if (wt) repoRoot = gitDir.slice(0, wt.index);
        }
        const head = readSmall(path.join(gitDir, 'HEAD')).trim();
        const ref = /^ref:\s*refs\/heads\/(.+)$/.exec(head);
        branch = ref ? ref[1] : head.slice(0, 8);
      } catch {
        branch = undefined;
      }
      return { repo: path.basename(repoRoot), branch };
    }
    const parent = path.dirname(dir);
    if (parent === dir) return {};
    dir = parent;
  }
}

// `permission_prompt` is left out: PermissionRequest already reports it, and a
// late async copy could put an approved card back in Needs me. `idle_prompt` is the
// only sign a turn ended without a Stop (Esc, a denied prompt).
const NOTIFICATIONS = new Set(['elicitation_dialog', 'elicitation_url_dialog', 'agent_needs_input', 'idle_prompt']);

// Which tool call a question belongs to, so finishing one parallel call does not
// answer another's prompt. PermissionRequest carries no tool_use_id, so the key is
// a hash of what the call is: the same tool and input in both events.
export function callKey(name, input) {
  return crypto.createHash('sha256').update(`${name}\n${JSON.stringify(input ?? null)}`).digest('hex').slice(0, 16);
}

// Repo and branch for a card. A folder outside git names the repo and clears the
// branch, so a session that moved out of a repo does not keep the old one.
export function where(cwd) {
  if (typeof cwd !== 'string' || !cwd) return {};
  const g = gitInfo(cwd);
  return { repo: g.repo || path.basename(cwd), branch: g.branch || '' };
}

// Hook payload → the record the reducer reads. Returns null for events the board
// does not track, so they never reach the log.
export function distill(p, now = Date.now()) {
  if (!p || typeof p !== 'object' || typeof p.session_id !== 'string') return null;
  const e = p.hook_event_name;
  const rec = { v: 1, ts: now, e, sid: p.session_id };
  if (p.cwd) rec.cwd = p.cwd;
  if (p.permission_mode) rec.pm = p.permission_mode;
  if (p.agent_type) rec.agent = p.agent_type;
  if (p.agent_id) rec.aid = p.agent_id;
  if (p.session_title) rec.title = clip(p.session_title, CLIP.prompt);

  switch (e) {
    case 'SessionStart':
      rec.source = p.source;
      if (p.model) rec.model = p.model;
      Object.assign(rec, where(p.cwd));
      break;
    case 'UserPromptSubmit':
      rec.prompt = clip(p.prompt, CLIP.prompt);
      Object.assign(rec, where(p.cwd));
      break;
    case 'PreToolUse':
      rec.tool = summarizeTool(p.tool_name, p.tool_input, p.cwd);
      break;
    case 'PostToolUse':
    case 'PostToolUseFailure':
    case 'PermissionRequest':
      rec.tool = summarizeTool(p.tool_name, p.tool_input, p.cwd);
      rec.call = callKey(p.tool_name, p.tool_input);
      break;
    case 'Notification':
      if (!NOTIFICATIONS.has(p.notification_type)) return null;
      rec.ntype = p.notification_type;
      rec.msg = clip(p.message, CLIP.msg);
      break;
    case 'Stop':
      rec.msg = clip(p.last_assistant_message, CLIP.msg);
      Object.assign(rec, where(p.cwd));
      break;
    case 'StopFailure':
      rec.error = p.error;
      rec.msg = clip(p.error_details ?? p.last_assistant_message, CLIP.msg);
      break;
    case 'SubagentStart':
      break;
    case 'SubagentStop':
      rec.msg = clip(p.last_assistant_message, CLIP.msg);
      break;
    case 'SessionEnd':
      rec.reason = p.reason;
      break;
    default:
      return null;
  }
  return rec;
}

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

export function main() {
  try {
    const rec = distill(JSON.parse(readStdin()));
    if (!rec) return;
    fs.mkdirSync(boardDir(), { recursive: true, mode: 0o700 });
    fs.appendFileSync(eventsFile(), `${JSON.stringify(rec)}\n`, { mode: 0o600 });
  } catch {
    // The board is a view; a lost event must never disturb the session.
  }
}

if (isMain(process.argv[1], import.meta.url)) main();
