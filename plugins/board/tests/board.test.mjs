// Node suite for the board: reducer, columns, history backfill, log tail, server.
// Run by capture.test.sh through `node --test`; no network beyond 127.0.0.1.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { apply, createBoard } from '../server/reduce.mjs';
import { columnOf, isGone, isStale, STALE_MS } from '../server/public/columns.mjs';
import { readSession, scanHistory } from '../server/history.mjs';
import { createTail, parseArgs } from '../server/board.mjs';
import { distill, summarizeTool } from '../server/capture.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'board-test-'));

function run(records) {
  const board = createBoard();
  let ts = 1000;
  for (const r of records) apply(board, { v: 1, ts: ts++, sid: 's', ...r });
  return board.cards.get('s');
}

test('a session moves through the columns as its hooks fire', () => {
  const seq = [
    [{ e: 'SessionStart', source: 'startup' }, 'yourTurn'],
    [{ e: 'UserPromptSubmit', prompt: 'fix the cart' }, 'working'],
    [{ e: 'PreToolUse', tool: 'Bash npm test' }, 'working'],
    [{ e: 'PermissionRequest', tool: 'Bash npm test' }, 'needs'],
    [{ e: 'PostToolUse', tool: 'Bash npm test' }, 'working'],
    [{ e: 'Stop', msg: 'Done: 4 files' }, 'yourTurn'],
    [{ e: 'StopFailure', error: 'rate_limit' }, 'needs'],
    [{ e: 'SessionEnd', reason: 'prompt_input_exit' }, 'closed'],
  ];
  const board = createBoard();
  seq.forEach(([r, state], i) => {
    apply(board, { v: 1, ts: i + 1, sid: 's', ...r });
    assert.equal(board.cards.get('s').state, state, `after ${r.e}`);
  });
  const c = board.cards.get('s');
  assert.equal(c.title, 'fix the cart');
  assert.equal(c.summary, 'Done: 4 files');
  assert.equal(c.endReason, 'prompt_input_exit');
  assert.deepEqual(c.recent.map((r) => r.tool), ['Bash npm test']);
});

test('compact keeps the state; resume reopens a closed card', () => {
  const c = run([
    { e: 'UserPromptSubmit', prompt: 'p' },
    { e: 'SessionStart', source: 'compact' },
  ]);
  assert.equal(c.state, 'working');
  const d = run([{ e: 'SessionEnd', reason: 'other' }, { e: 'SessionStart', source: 'resume' }]);
  assert.equal(d.state, 'yourTurn');
  assert.equal(d.endReason, '');
});

test('a /rename title beats the first prompt, and the first prompt sticks', () => {
  const c = run([
    { e: 'UserPromptSubmit', prompt: 'first' },
    { e: 'UserPromptSubmit', prompt: 'second' },
  ]);
  assert.equal(c.title, 'first');
  const d = run([
    { e: 'UserPromptSubmit', prompt: 'first', title: 'checkout-fix' },
    { e: 'UserPromptSubmit', prompt: 'second' },
  ]);
  assert.equal(d.title, 'checkout-fix');
});

test('subagents live on the parent card, not as cards of their own', () => {
  const board = createBoard();
  const recs = [
    { e: 'SessionStart', source: 'startup', agent: 'crew:lead' },
    { e: 'PreToolUse', tool: 'Agent backend: cart totals' },
    { e: 'SubagentStart', aid: 'a1', agent: 'crew:backend' },
    { e: 'PreToolUse', aid: 'a1', agent: 'crew:backend', tool: 'Edit src/cart.ts' },
  ];
  recs.forEach((r, i) => apply(board, { v: 1, ts: i + 1, sid: 's', ...r }));
  assert.equal(board.cards.size, 1);
  let c = board.cards.get('s');
  assert.equal(c.crew, true);
  assert.equal(c.agent, 'crew:lead');
  assert.equal(c.state, 'working');
  assert.equal(c.activity, 'Agent backend: cart totals', 'a worker tool leaves the main activity alone');
  assert.deepEqual(
    c.workers.map((w) => [w.type, w.state, w.activity]),
    [['crew:backend', 'running', 'Edit src/cart.ts']],
  );

  apply(board, { v: 1, ts: 10, sid: 's', e: 'PermissionRequest', aid: 'a1', agent: 'crew:backend', tool: 'Bash dotnet test' });
  c = board.cards.get('s');
  assert.equal(c.state, 'needs');
  assert.match(c.activity, /crew:backend asks: allow Bash dotnet test\?/);

  apply(board, { v: 1, ts: 11, sid: 's', e: 'PostToolUse', aid: 'a1', tool: 'Bash dotnet test' });
  assert.equal(board.cards.get('s').state, 'working');

  apply(board, { v: 1, ts: 12, sid: 's', e: 'SubagentStop', aid: 'a1', agent: 'crew:backend', msg: 'Totals fixed' });
  const w = board.cards.get('s').workers[0];
  assert.equal(w.state, 'done');
  assert.equal(w.msg, 'Totals fixed');
});

test('a subagent tool call does not pull a waiting card back to Working', () => {
  const c = run([
    { e: 'Stop', msg: 'over to you' },
    { e: 'PreToolUse', aid: 'bg', agent: 'Explore', tool: 'Grep foo' },
  ]);
  assert.equal(c.state, 'yourTurn');
});

test('history fills gaps but never overrides a hook', () => {
  const board = createBoard();
  apply(board, { v: 1, ts: 5, sid: 's', e: 'PreToolUse', tool: 'Read a' });
  apply(board, { v: 1, ts: 9, sid: 's', e: 'History', prompt: 'from history', repo: 'shop-web', branch: 'main', msg: 'old' });
  const c = board.cards.get('s');
  assert.equal(c.state, 'working');
  assert.equal(c.title, 'from history');
  assert.equal(c.repo, 'shop-web');
  assert.equal(c.lastTs, 5);

  apply(board, { v: 1, ts: 7, sid: 'h', e: 'History', prompt: 'old work', msg: 'All done' });
  const h = board.cards.get('h');
  assert.equal(h.state, 'closed');
  assert.equal(h.hooks, false);
  assert.equal(h.summary, 'All done');
});

test('archive toggles without touching the state', () => {
  const c = run([{ e: 'Stop' }, { e: 'BoardArchive', on: true }]);
  assert.equal(c.archived, true);
  assert.equal(c.state, 'yourTurn');
  const d = run([{ e: 'BoardArchive', on: true }, { e: 'BoardArchive', on: false }]);
  assert.equal(d.archived, false);
});

test('records without a session id or timestamp are ignored', () => {
  const board = createBoard();
  apply(board, { e: 'Stop', ts: 1 });
  apply(board, { e: 'Stop', sid: 's' });
  apply(board, null);
  assert.equal(board.cards.size, 0);
});

test('columns: stale, gone, closed today and earlier', () => {
  const now = new Date(2026, 9, 21, 15, 0).getTime();
  const card = (state, ago) => ({ state, lastTs: now - ago });
  assert.equal(columnOf(card('needs', 1000), now), 'needs');
  assert.equal(isStale(card('working', STALE_MS - 1), now), false);
  assert.equal(isStale(card('working', STALE_MS), now), true);
  assert.equal(isStale(card('yourTurn', STALE_MS * 3), now), false);
  assert.equal(columnOf(card('closed', 60 * 60 * 1000), now), 'closedToday');
  assert.equal(columnOf(card('closed', 24 * 60 * 60 * 1000), now), 'earlier');
  const gone = card('working', 13 * 60 * 60 * 1000);
  assert.equal(isGone(gone, now), true);
  assert.equal(isStale(gone, now), false);
  assert.equal(columnOf(gone, now), 'closedToday');
});

test('tool summaries stay short and relative', () => {
  assert.equal(summarizeTool('Edit', { file_path: '/r/src/a.ts' }, '/r'), 'Edit src/a.ts');
  assert.equal(summarizeTool('Bash', { command: 'npm test\nnpm run lint' }), 'Bash npm test');
  assert.equal(summarizeTool('mcp__github__create_pull_request', {}), 'github: create_pull_request');
  assert.equal(summarizeTool('Agent', { subagent_type: 'crew:backend', description: 'cart' }), 'Agent crew:backend: cart');
  assert.ok(summarizeTool('Bash', { command: 'x'.repeat(500) }).length <= 120);
});

test('distill keeps the fields the reducer reads, nothing more', () => {
  const rec = distill(
    {
      session_id: 's',
      hook_event_name: 'Stop',
      transcript_path: '/t.jsonl',
      cwd: '/nowhere',
      last_assistant_message: 'line one\n\nline two',
    },
    42,
  );
  assert.deepEqual(rec, { v: 1, ts: 42, e: 'Stop', sid: 's', cwd: '/nowhere', msg: 'line one line two' });
});

function writeTranscript(dir, sid, lines) {
  const pdir = path.join(dir, '-home-me-shop');
  fs.mkdirSync(pdir, { recursive: true });
  const file = path.join(pdir, `${sid}.jsonl`);
  fs.writeFileSync(file, lines.map((l) => (typeof l === 'string' ? l : JSON.stringify(l))).join('\n') + '\n');
  return file;
}

test('history reads title, cwd, branch and the last reply from a transcript', () => {
  const dir = tmp();
  const base = { sessionId: 'abc', cwd: '/home/me/shop', gitBranch: 'feature/x' };
  const file = writeTranscript(dir, 'abc', [
    { type: 'queue-operation', operation: 'enqueue', timestamp: '2026-10-20T08:00:00.000Z' },
    { ...base, type: 'user', isMeta: true, message: { content: 'meta' }, timestamp: '2026-10-20T08:00:01.000Z' },
    { ...base, type: 'user', message: { content: '<command-name>/clear</command-name>' }, timestamp: '2026-10-20T08:00:02.000Z' },
    { ...base, type: 'user', message: { content: [{ type: 'text', text: 'Fix the checkout' }] }, timestamp: '2026-10-20T08:00:03.000Z' },
    'not json at all',
    { ...base, type: 'assistant', message: { content: [{ type: 'tool_use', name: 'Read' }] }, timestamp: '2026-10-20T08:00:04.000Z' },
    { ...base, type: 'user', message: { content: [{ type: 'tool_result', content: 'x' }] }, timestamp: '2026-10-20T08:00:05.000Z' },
    { ...base, type: 'assistant', isSidechain: true, message: { content: [{ type: 'text', text: 'subagent text' }] }, timestamp: '2026-10-20T08:00:06.000Z' },
    { ...base, type: 'assistant', message: { content: [{ type: 'text', text: 'Fixed in cart.ts' }] }, timestamp: '2026-10-20T08:00:07.000Z' },
    { type: 'custom-title', customTitle: 'checkout-fix', sessionId: 'abc' },
  ]);
  const rec = readSession(file);
  assert.equal(rec.e, 'History');
  assert.equal(rec.sid, 'abc');
  assert.equal(rec.prompt, 'Fix the checkout');
  assert.equal(rec.rename, 'checkout-fix');
  assert.equal(rec.msg, 'Fixed in cart.ts');
  assert.equal(rec.cwd, '/home/me/shop');
  assert.equal(rec.branch, 'feature/x');
  assert.equal(rec.repo, 'shop');
  assert.equal(rec.ts, Date.parse('2026-10-20T08:00:07.000Z'));
  assert.equal(rec.firstTs, Date.parse('2026-10-20T08:00:00.000Z'));
});

test('history reads only the head and tail of a large transcript', () => {
  const dir = tmp();
  const filler = { type: 'assistant', message: { content: [{ type: 'text', text: 'y'.repeat(1000) }] }, timestamp: '2026-10-20T09:00:00.000Z' };
  const lines = [{ type: 'user', cwd: '/w', message: { content: 'first prompt' }, timestamp: '2026-10-20T08:00:00.000Z' }];
  for (let i = 0; i < 1000; i++) lines.push(filler);
  lines.push({ type: 'assistant', message: { content: [{ type: 'text', text: 'the end' }] }, timestamp: '2026-10-20T10:00:00.000Z' });
  const file = writeTranscript(dir, 'big', lines);
  assert.ok(fs.statSync(file).size > 600 * 1024);
  const rec = readSession(file);
  assert.equal(rec.prompt, 'first prompt');
  assert.equal(rec.msg, 'the end');
});

test('scanHistory skips old files, other files and a missing directory', () => {
  const dir = tmp();
  const fresh = writeTranscript(dir, 'fresh', [{ type: 'user', message: { content: 'hi' } }]);
  const old = writeTranscript(dir, 'old', [{ type: 'user', message: { content: 'hi' } }]);
  const past = (Date.now() - 40 * 24 * 60 * 60 * 1000) / 1000;
  fs.utimesSync(old, past, past);
  fs.writeFileSync(path.join(path.dirname(fresh), 'notes.txt'), 'x');
  const recs = scanHistory(dir, Date.now() - 7 * 24 * 60 * 60 * 1000);
  assert.deepEqual(recs.map((r) => r.sid), ['fresh']);
  assert.deepEqual(scanHistory(path.join(dir, 'missing'), 0), []);
});

test('the tail returns whole lines and holds a partial one', () => {
  const file = path.join(tmp(), 'events.jsonl');
  const tail = createTail(file);
  assert.deepEqual(tail.read().records, [], 'a missing file reads as empty');
  fs.writeFileSync(file, '{"a":1}\n{"b":');
  assert.deepEqual(tail.read().records, [{ a: 1 }]);
  fs.appendFileSync(file, '2}\nbroken\n{"c":"é"}\n');
  assert.deepEqual(tail.read().records, [{ b: 2 }, { c: 'é' }]);
  fs.writeFileSync(file, '');
  assert.equal(tail.read().truncated, true);
});

test('parseArgs rejects what it does not know', () => {
  assert.equal(parseArgs(['--port', '9000']).port, 9000);
  assert.throws(() => parseArgs(['--port', 'x']));
  assert.throws(() => parseArgs(['--days', '0']));
  assert.throws(() => parseArgs(['--serve']));
});

async function waitFor(fn, ms = 5000) {
  const end = Date.now() + ms;
  for (;;) {
    try {
      const v = await fn();
      if (v) return v;
    } catch {
      // Not up yet.
    }
    if (Date.now() > end) throw new Error('timed out');
    await new Promise((r) => setTimeout(r, 100));
  }
}

test('the server serves state, refuses foreign hosts, and archives', async (t) => {
  const boardDir = tmp();
  const configDir = tmp();
  writeTranscript(path.join(configDir, 'projects'), 'hist', [
    { type: 'user', cwd: '/w/api', message: { content: 'old question' }, timestamp: new Date().toISOString() },
  ]);
  fs.writeFileSync(
    path.join(boardDir, 'events.jsonl'),
    `${JSON.stringify({ v: 1, ts: Date.now(), e: 'UserPromptSubmit', sid: 'live', prompt: 'live work' })}\n`,
  );
  const port = 20000 + Math.floor(Math.random() * 20000);
  const child = spawn(process.execPath, [path.join(HERE, '../server/board.mjs'), '--port', String(port)], {
    env: { ...process.env, CLAUDE_BOARD_DIR: boardDir, CLAUDE_CONFIG_DIR: configDir },
    stdio: 'ignore',
  });
  t.after(() => child.kill());
  const base = `http://127.0.0.1:${port}`;
  await waitFor(async () => (await fetch(`${base}/api/health`)).ok);

  const state = await (await fetch(`${base}/api/state`)).json();
  const byId = Object.fromEntries(state.cards.map((c) => [c.id, c]));
  assert.equal(byId.live.state, 'working');
  assert.equal(byId.hist.state, 'closed');
  assert.equal(byId.hist.title, 'old question');

  const page = await fetch(`${base}/`);
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-security-policy'), /default-src 'self'/);

  // DNS rebinding: a request naming another host is refused.
  const http = await import('node:http');
  const foreign = await new Promise((resolve) => {
    http.get({ host: '127.0.0.1', port, path: '/api/state', headers: { Host: 'evil.example:80' } }, (res) => resolve(res.statusCode));
  });
  assert.equal(foreign, 403);

  const formPost = await fetch(`${base}/api/archive`, { method: 'POST', body: 'sid=live' });
  assert.equal(formPost.status, 403, 'a non-JSON post is refused');
  const crossSite = await fetch(`${base}/api/archive`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://evil.example' },
    body: JSON.stringify({ sid: 'live' }),
  });
  assert.equal(crossSite.status, 403, 'another origin is refused');

  const ok = await fetch(`${base}/api/archive`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sid: 'live', on: true }),
  });
  assert.equal(ok.status, 200);
  const after = await (await fetch(`${base}/api/state`)).json();
  assert.equal(after.cards.find((c) => c.id === 'live').archived, true);

  // A new hook line shows up without a restart.
  fs.appendFileSync(path.join(boardDir, 'events.jsonl'), `${JSON.stringify({ v: 1, ts: Date.now(), e: 'Stop', sid: 'live', msg: 'done' })}\n`);
  await waitFor(async () => {
    const s = await (await fetch(`${base}/api/state`)).json();
    return s.cards.find((c) => c.id === 'live').state === 'yourTurn';
  });
});
