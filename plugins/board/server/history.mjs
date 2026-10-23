// Backfill from Claude Code's own transcripts (<config>/projects/<project>/<session>.jsonl)
// for sessions that ran before the board, or while its hooks were off. The line
// format is undocumented, so every field is optional and a line that does not
// parse is skipped. Only a head and a tail chunk of each file are read.
import fs from 'node:fs';
import path from 'node:path';
import { clip, gitInfo } from './capture.mjs';

const CHUNK = 256 * 1024;

function readChunks(file, size) {
  const fd = fs.openSync(file, 'r');
  try {
    const read = (start, len) => {
      const buf = Buffer.alloc(len);
      const n = fs.readSync(fd, buf, 0, len, start);
      return buf.subarray(0, n).toString('utf8');
    };
    if (size <= 2 * CHUNK) return { head: read(0, size), tail: '' };
    return { head: read(0, CHUNK), tail: read(size - CHUNK, CHUNK) };
  } finally {
    fs.closeSync(fd);
  }
}

function parseLines(text, dropFirst, dropLast) {
  const lines = text.split('\n');
  // A chunk cut mid-line leaves a fragment at its edge.
  if (dropFirst) lines.shift();
  if (dropLast) lines.pop();
  const out = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line));
    } catch {
      // Tolerate a format change: skip what does not parse.
    }
  }
  return out;
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .filter((b) => b && b.type === 'text' && typeof b.text === 'string')
    .map((b) => b.text)
    .join(' ');
}

// A prompt a person typed: not a tool result, not meta, not a wrapped command.
function humanPrompt(line) {
  if (line.type !== 'user' || line.isMeta || line.isSidechain) return '';
  const text = textOf(line.message?.content).trim();
  if (!text || text.startsWith('<')) return '';
  return text;
}

export function readSession(file, stat = fs.statSync(file)) {
  const { head, tail } = readChunks(file, stat.size);
  const lines = [...parseLines(head, false, tail !== ''), ...parseLines(tail, true, false)];
  const rec = { v: 1, e: 'History', sid: path.basename(file, '.jsonl'), ts: stat.mtimeMs };
  let firstTs = 0;
  let lastTs = 0;
  for (const line of lines) {
    if (!line || typeof line !== 'object' || line.isSidechain) continue;
    const t = Date.parse(line.timestamp);
    if (t) {
      if (!firstTs || t < firstTs) firstTs = t;
      if (t > lastTs) lastTs = t;
    }
    if (typeof line.cwd === 'string' && line.cwd) rec.cwd = line.cwd;
    if (typeof line.gitBranch === 'string' && line.gitBranch) rec.branch = line.gitBranch;
    if (line.type === 'custom-title' && line.customTitle) rec.rename = clip(line.customTitle, 200);
    if (!rec.prompt) {
      const p = humanPrompt(line);
      if (p) rec.prompt = clip(p, 200);
    }
    if (line.type === 'assistant') {
      const text = textOf(line.message?.content);
      if (text.trim()) rec.msg = clip(text, 300);
    }
  }
  if (lastTs) rec.ts = lastTs;
  if (firstTs) rec.firstTs = firstTs;
  if (rec.cwd) {
    const g = gitInfo(rec.cwd);
    rec.repo = g.repo || path.basename(rec.cwd);
  }
  return rec;
}

// Every session file touched since `sinceMs`, as History records. `seen` maps a
// file to the mtime and size it was read at, so a rescan reads only what changed.
export function scanHistory(dir, sinceMs, seen = new Map()) {
  const out = [];
  let projects;
  try {
    projects = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const p of projects) {
    if (!p.isDirectory()) continue;
    const pdir = path.join(dir, p.name);
    let files;
    try {
      files = fs.readdirSync(pdir);
    } catch {
      continue;
    }
    for (const f of files) {
      if (!f.endsWith('.jsonl')) continue;
      const file = path.join(pdir, f);
      try {
        const stat = fs.statSync(file);
        if (!stat.isFile() || stat.mtimeMs < sinceMs) continue;
        const key = `${stat.mtimeMs}:${stat.size}`;
        if (seen.get(file) === key) continue;
        seen.set(file, key);
        out.push(readSession(file, stat));
      } catch {
        // One unreadable transcript must not hide the rest.
      }
    }
  }
  return out;
}
