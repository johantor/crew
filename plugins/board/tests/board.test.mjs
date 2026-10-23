// Node suite for the board: reducer, columns, history backfill, log tail, server.
// Run by capture.test.sh through `node --test`; no network beyond 127.0.0.1.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { apply, createBoard } from '../server/reduce.mjs';
import { columnOf, isGone, isStale, STALE_MS } from '../server/public/columns.mjs';
import { readSession, scanHistory } from '../server/history.mjs';
import { createTail, parseArgs, proof } from '../server/board.mjs';
import { distill, summarizeTool, where } from '../server/capture.mjs';
import { resumeCommand } from '../server/public/resume.mjs';

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

test('a late async event does not reopen an ended session', () => {
  const c = run([
    { e: 'SessionStart', source: 'startup' },
    { e: 'SessionEnd', reason: 'prompt_input_exit' },
    { e: 'Stop', msg: 'late' },
    { e: 'PermissionRequest', aid: 'w', tool: 'Bash x' },
  ]);
  assert.equal(c.state, 'closed');
  assert.equal(c.summary, '');
  const resumed = run([{ e: 'SessionEnd' }, { e: 'SessionStart', source: 'resume' }, { e: 'UserPromptSubmit', prompt: 'p' }]);
  assert.equal(resumed.state, 'working');
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
  assert.deepEqual(rec, { v: 1, ts: 42, e: 'Stop', sid: 's', cwd: '/nowhere', msg: 'line one line two', repo: 'nowhere', branch: '' });
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
  // Port 0: the OS picks a free port, which the server prints.
  const child = spawn(process.execPath, [path.join(HERE, '../server/board.mjs'), '--port', '0'], {
    env: { ...process.env, CLAUDE_BOARD_DIR: boardDir, CLAUDE_CONFIG_DIR: configDir },
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  t.after(() => child.kill());
  let out = '';
  child.stdout.on('data', (d) => (out += d));
  const port = Number(await waitFor(() => /Board: http:\/\/127\.0\.0\.1:(\d+)\//.exec(out)?.[1]));
  const base = `http://127.0.0.1:${port}`;
  await waitFor(async () => (await fetch(`${base}/api/health`)).ok);

  // Without the token, other local users get nothing.
  const token = fs.readFileSync(path.join(boardDir, 'token'), 'utf8').trim();
  assert.equal((fs.statSync(path.join(boardDir, 'token')).mode & 0o777).toString(8), '600');
  assert.equal((await fetch(`${base}/api/state`)).status, 401);
  assert.equal((await fetch(`${base}/api/state?t=${token}`)).status, 401, 'only the stream takes the token in the URL');
  assert.equal((await fetch(`${base}/api/stream`)).status, 401);
  const page = await fetch(`${base}/?t=${token}`);
  assert.equal(page.status, 200, 'the page holds no data and needs no token');
  assert.equal(page.headers.get('set-cookie'), null, 'no cookie: it would reach every port on 127.0.0.1');

  // The health probe proves the token by signing a nonce; the token itself never crosses.
  const health = await (await fetch(`${base}/api/health?n=00112233445566778899aabbccddeeff`)).json();
  assert.equal(health.proof, proof(token, '00112233445566778899aabbccddeeff'));
  assert.ok(!JSON.stringify(health).includes(token));
  assert.equal((await (await fetch(`${base}/api/health?n=not-hex`)).json()).proof, undefined);

  const realFetch = fetch;
  const fetch2 = (url, init = {}) => realFetch(url, { ...init, headers: { 'X-Board-Token': token, ...init.headers } });

  const state = await (await fetch2(`${base}/api/state`)).json();
  const byId = Object.fromEntries(state.cards.map((c) => [c.id, c]));
  assert.equal(byId.live.state, 'working');
  assert.equal(byId.hist.state, 'closed');
  assert.equal(byId.hist.title, 'old question');

  assert.match(page.headers.get('content-security-policy'), /default-src 'self'/);

  // DNS rebinding: a request naming another host is refused.
  const http = await import('node:http');
  const foreign = await new Promise((resolve) => {
    http.get({ host: '127.0.0.1', port, path: '/api/state', headers: { Host: 'evil.example:80', 'X-Board-Token': token } }, (res) =>
      resolve(res.statusCode),
    );
  });
  assert.equal(foreign, 403);

  const formPost = await fetch2(`${base}/api/archive`, { method: 'POST', body: 'sid=live' });
  assert.equal(formPost.status, 403, 'a non-JSON post is refused');
  const crossSite = await fetch2(`${base}/api/archive`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://evil.example' },
    body: JSON.stringify({ sid: 'live' }),
  });
  assert.equal(crossSite.status, 403, 'another origin is refused');
  const nullBody = await fetch2(`${base}/api/archive`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: 'null' });
  assert.equal(nullBody.status, 404, 'a null body is refused, and the server lives on');

  const ok = await fetch2(`${base}/api/archive`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sid: 'live', on: true }),
  });
  assert.equal(ok.status, 200);
  const after = await (await fetch2(`${base}/api/state`)).json();
  assert.equal(after.cards.find((c) => c.id === 'live').archived, true);

  // The stream opens with the full snapshot, so no push falls between a fetch and the subscribe.
  const first = await new Promise((resolve, reject) => {
    http
      .get({ host: '127.0.0.1', port, path: `/api/stream?t=${token}` }, (res) => {
        res.once('data', (chunk) => {
          resolve(String(chunk));
          res.destroy();
        });
      })
      .on('error', reject);
  });
  assert.match(first, /^event: state\ndata: \{"now":\d+,"days":30,"cards":\[/);

  // A new hook line shows up without a restart.
  const log = path.join(boardDir, 'events.jsonl');
  fs.appendFileSync(log, `${JSON.stringify({ v: 1, ts: Date.now(), e: 'Stop', sid: 'live', msg: 'done' })}\n`);
  await waitFor(async () => {
    const s = await (await fetch2(`${base}/api/state`)).json();
    return s.cards.find((c) => c.id === 'live').state === 'yourTurn';
  });

  // A log that cannot be written fails the archive with 500, and the server stays up.
  fs.renameSync(log, `${log}.bak`);
  fs.mkdirSync(log);
  const broken = await fetch2(`${base}/api/archive`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sid: 'live', on: false }),
  });
  assert.equal(broken.status, 500);
  await new Promise((r) => setTimeout(r, 1200));
  assert.equal((await fetch(`${base}/api/health`)).status, 200);
});

test('a squatter on the port reads as busy and never sees the token', async (t) => {
  const http = await import('node:http');
  const seen = [];
  const fake = http.createServer((req, res) => {
    seen.push(`${req.url} ${JSON.stringify(req.headers)}`);
    res.end(JSON.stringify({ app: 'claude-board', auth: true, proof: 'f'.repeat(64) }));
  });
  await new Promise((r) => fake.listen(0, '127.0.0.1', r));
  t.after(() => fake.close());
  const boardDir = tmp();
  const res = await new Promise((resolve) => {
    const child = spawn(process.execPath, [path.join(HERE, '../server/board.mjs'), '--detach', '--port', String(fake.address().port)], {
      env: { ...process.env, CLAUDE_BOARD_DIR: boardDir },
    });
    let err = '';
    child.stderr.on('data', (d) => (err += d));
    child.on('close', (code) => resolve({ code, err }));
  });
  assert.equal(res.code, 1);
  assert.match(res.err, /is in use/);
  const token = fs.readFileSync(path.join(boardDir, 'token'), 'utf8').trim();
  assert.ok(seen.length > 0, 'the probe reached the squatter');
  assert.ok(seen.every((s) => !s.includes(token)), 'the token crossed to the squatter');
});

test('the resume command never lets a folder name run code', () => {
  const id = '0f5a2c1e-1111-4abc-9def-123456789abc';
  assert.deepEqual(resumeCommand({ id, cwd: '/w/shop web' }), { command: `cd '/w/shop web'; claude --resume ${id}`, cdOmitted: false });
  assert.equal(resumeCommand({ id, cwd: '/w/$(touch PWNED)' }).command, `cd '/w/$(touch PWNED)'; claude --resume ${id}`);
  assert.deepEqual(resumeCommand({ id, cwd: "/w/it's" }), { command: `claude --resume ${id}`, cdOmitted: true });
  assert.deepEqual(resumeCommand({ id, cwd: '/w/a\nb' }), { command: `claude --resume ${id}`, cdOmitted: true });
  assert.equal(resumeCommand({ id: 'x; rm -rf ~', cwd: '/w' }).command, '');
  // PowerShell ends a single-quoted string on smart quotes too: the allowlist leaves them out.
  for (const q of ['\u2018', '\u2019', '\u201a', '\u201b']) {
    assert.equal(resumeCommand({ id, cwd: `C:\\work\\${q}; Write-Output INJECTED; #` }).cdOmitted, true, `U+${q.codePointAt(0).toString(16)}`);
  }
  assert.equal(resumeCommand({ id, cwd: '/w/a\tb' }).cdOmitted, true, 'a control character');
  // Real paths keep their cd: Windows, non-English letters, and macOS's decomposed form.
  for (const cwd of ['C:\\Users\\Jöhan\\källa (2)', '/Users/me/Projekt/la\u0308sa', '/w/日本語/x_y-z.v2']) {
    assert.equal(resumeCommand({ id, cwd }).command, `cd '${cwd}'; claude --resume ${id}`);
  }
  assert.equal(resumeCommand({ id, cwd: '' }).command, `claude --resume ${id}`);
});

test('a worker event leaves the parent session waiting in Needs me', () => {
  for (const ask of [
    { e: 'PermissionRequest', tool: 'Bash git commit' },
    { e: 'StopFailure', error: 'rate_limit' },
  ]) {
    const c = run([
      { e: 'SubagentStart', aid: 'w1', agent: 'crew:backend' },
      ask,
      { e: 'PreToolUse', aid: 'w1', tool: 'Edit a.ts' },
      { e: 'PostToolUse', aid: 'w1', tool: 'Edit a.ts' },
      { e: 'SubagentStop', aid: 'w1', msg: 'done' },
    ]);
    assert.equal(c.state, 'needs', `after ${ask.e}`);
  }
});

test('the session own turn leaves a worker prompt in Needs me until that worker moves', () => {
  const c = run([
    { e: 'SubagentStart', aid: 'w1', agent: 'crew:backend' },
    { e: 'PermissionRequest', aid: 'w1', tool: 'Bash dotnet test' },
    { e: 'PreToolUse', tool: 'Read plan.md' },
    { e: 'Stop', msg: 'waiting on the worker' },
  ]);
  assert.equal(c.state, 'needs');
  assert.match(c.activity, /crew:backend asks/);
  assert.equal(c.summary, 'waiting on the worker');
  const d = run([
    { e: 'UserPromptSubmit', prompt: 'build it' },
    { e: 'SubagentStart', aid: 'w1', agent: 'crew:backend' },
    { e: 'PermissionRequest', aid: 'w1', tool: 'Bash dotnet test' },
    { e: 'SubagentStop', aid: 'w1', msg: 'denied, stopped' },
  ]);
  assert.equal(d.state, 'working', 'the worker stopping answers its own prompt');
});

test('a planted .git/HEAD cannot hang the hook', { skip: process.platform === 'win32' }, () => {
  const dir = tmp();
  fs.mkdirSync(path.join(dir, '.git'));
  const fifo = spawnSync('mkfifo', [path.join(dir, '.git', 'HEAD')]);
  assert.equal(fifo.status, 0, 'mkfifo is needed for this case');
  const probe = `import { gitInfo } from ${JSON.stringify(path.join(HERE, '../server/capture.mjs'))}; console.log(JSON.stringify(gitInfo(${JSON.stringify(dir)})));`;
  const res = spawnSync(process.execPath, ['--input-type=module', '-e', probe], { timeout: 5000, encoding: 'utf8' });
  assert.equal(res.signal, null, 'gitInfo hung on a FIFO');
  assert.deepEqual(JSON.parse(res.stdout), { repo: path.basename(dir) });

  const link = tmp();
  fs.mkdirSync(path.join(link, '.git'));
  fs.symlinkSync('/dev/zero', path.join(link, '.git', 'HEAD'));
  const res2 = spawnSync(process.execPath, ['--input-type=module', '-e', probe.replace(JSON.stringify(dir), JSON.stringify(link))], {
    timeout: 5000,
    encoding: 'utf8',
  });
  assert.equal(res2.signal, null, 'gitInfo hung on a symlink to /dev/zero');
});

test('a PreToolUse appended after its PermissionRequest keeps the card in Needs me', () => {
  const c = run([
    { e: 'UserPromptSubmit', prompt: 'p' },
    { e: 'PermissionRequest', tool: 'Bash rm x' },
    { e: 'PreToolUse', tool: 'Bash rm x' },
  ]);
  assert.equal(c.state, 'needs');
  assert.equal(c.activity, 'Allow: Bash rm x?');
  const d = run([{ e: 'PermissionRequest', tool: 'Bash x' }, { e: 'PostToolUseFailure', tool: 'Bash x' }]);
  assert.equal(d.state, 'working', 'an approved tool that failed also leaves Needs me');
});

test('an idle notification ends a turn that had no Stop', () => {
  assert.equal(run([{ e: 'UserPromptSubmit', prompt: 'p' }, { e: 'Notification', ntype: 'idle_prompt' }]).state, 'yourTurn');
  assert.equal(run([{ e: 'PermissionRequest', tool: 'Bash x' }, { e: 'Notification', ntype: 'idle_prompt' }]).state, 'yourTurn');
  assert.equal(run([{ e: 'StopFailure', error: 'rate_limit' }, { e: 'Notification', ntype: 'idle_prompt' }]).state, 'needs');
  assert.equal(run([{ e: 'SessionEnd' }, { e: 'Notification', ntype: 'idle_prompt' }]).state, 'closed');
});

test('answering a background subagent returns an idle card to Your turn', () => {
  const c = run([
    { e: 'Stop', msg: 'over to you' },
    { e: 'PreToolUse', aid: 'bg', agent: 'Explore', tool: 'Bash ls' },
    { e: 'PermissionRequest', aid: 'bg', agent: 'Explore', tool: 'Bash ls' },
    { e: 'PostToolUse', aid: 'bg', agent: 'Explore', tool: 'Bash ls' },
  ]);
  assert.equal(c.state, 'yourTurn');
  assert.equal(c.activity, 'over to you');
});

test('overlapping questions each stay open until their own answer', () => {
  // Two subagents ask at once: answering b leaves a open.
  const two = run([
    { e: 'UserPromptSubmit', prompt: 'p' },
    { e: 'PermissionRequest', aid: 'a', agent: 'crew:backend', tool: 'Bash a' },
    { e: 'PermissionRequest', aid: 'b', agent: 'crew:frontend', tool: 'Bash b' },
    { e: 'PostToolUse', aid: 'b', tool: 'Bash b' },
  ]);
  assert.equal(two.state, 'needs');
  assert.equal(two.activity, 'crew:backend asks: allow Bash a?');

  // A subagent asks over the session's own prompt: answering it leaves the session's prompt.
  const over = run([
    { e: 'PermissionRequest', tool: 'Bash git push' },
    { e: 'PermissionRequest', aid: 'a', agent: 'crew:backend', tool: 'Bash a' },
    { e: 'SubagentStop', aid: 'a' },
  ]);
  assert.equal(over.state, 'needs');
  assert.equal(over.activity, 'Allow: Bash git push?');

  // An error stays open under a subagent's question and after it.
  const err = run([
    { e: 'StopFailure', error: 'rate_limit', msg: '429' },
    { e: 'PermissionRequest', aid: 'a', tool: 'Bash a' },
    { e: 'PostToolUse', aid: 'a', tool: 'Bash a' },
  ]);
  assert.equal(err.activity, 'Error: 429');
});

test('one parallel call finishing does not answer another call prompt', () => {
  for (const aid of [undefined, 'w1']) {
    const who = aid ? { aid, agent: 'crew:backend' } : {};
    const c = run([
      { e: 'UserPromptSubmit', prompt: 'p' },
      { ...who, e: 'PreToolUse', tool: 'Bash npm test' },
      { ...who, e: 'PermissionRequest', tool: 'Bash rm important-file', call: 'B' },
      { ...who, e: 'PostToolUse', tool: 'Bash npm test', call: 'A' },
    ]);
    assert.equal(c.state, 'needs', aid ? 'subagent' : 'session');
    assert.match(c.activity, /rm important-file/);
    const done = run([
      { ...who, e: 'PermissionRequest', tool: 'Bash rm important-file', call: 'B' },
      { ...who, e: 'PostToolUse', tool: 'Bash rm important-file', call: 'B' },
    ]);
    assert.notEqual(done.state, 'needs', 'the matching call answers it');
  }
});

test('the call key matches between a PermissionRequest and its PostToolUse', () => {
  const input = { command: 'rm x', description: 'remove' };
  const perm = distill({ session_id: 's', hook_event_name: 'PermissionRequest', tool_name: 'Bash', tool_input: input });
  const post = distill({ session_id: 's', hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_input: input, tool_response: {} });
  const other = distill({ session_id: 's', hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_input: { command: 'ls' } });
  assert.equal(perm.call, post.call);
  assert.notEqual(perm.call, other.call);
});

test('the turn underneath a subagent question stays current', () => {
  const c = run([
    { e: 'UserPromptSubmit', prompt: 'p' },
    { e: 'PermissionRequest', aid: 'a', tool: 'Bash a' },
    { e: 'Stop', msg: 'done for now' },
    { e: 'PostToolUse', aid: 'a', tool: 'Bash a' },
  ]);
  assert.equal(c.state, 'yourTurn', 'the parent stopped while the subagent waited');
  assert.equal(c.activity, 'done for now');
  const idle = run([
    { e: 'UserPromptSubmit', prompt: 'p' },
    { e: 'PermissionRequest', aid: 'a', tool: 'Bash a' },
    { e: 'Notification', ntype: 'idle_prompt' },
    { e: 'SubagentStop', aid: 'a' },
  ]);
  assert.equal(idle.state, 'yourTurn');
});

test('a subagent in a worktree does not move the session resume folder', () => {
  const c = run([
    { e: 'SessionStart', source: 'startup', cwd: '/w/shop', repo: 'shop', branch: 'main' },
    { e: 'SubagentStart', aid: 'a', cwd: '/w/shop/.claude/worktrees/a' },
    { e: 'PreToolUse', aid: 'a', cwd: '/w/shop/.claude/worktrees/a', tool: 'Edit x' },
  ]);
  assert.equal(c.cwd, '/w/shop');
  assert.equal(c.branch, 'main');
});

test('a session that leaves the repo drops its branch', () => {
  const c = run([
    { e: 'SessionStart', source: 'startup', repo: 'shop', branch: 'main' },
    { e: 'UserPromptSubmit', prompt: 'p', repo: 'tmp', branch: '' },
  ]);
  assert.equal(c.repo, 'tmp');
  assert.equal(c.branch, '');
  assert.deepEqual(where('/no/such/dir/notes'), { repo: 'notes', branch: '' });
});

test('a sibling folder with a shared prefix is not inside the cwd', () => {
  assert.equal(summarizeTool('Edit', { file_path: '/w/shop-api/src/a.ts' }, '/w/shop'), 'Edit /w/shop-api/src/a.ts');
});

test('the hook and the server run through a symlinked install', { skip: process.platform === 'win32' }, () => {
  const dir = tmp();
  const link = path.join(dir, 'plugin');
  fs.symlinkSync(path.join(HERE, '..'), link);
  const boardDir = path.join(dir, 'board');
  const res = spawnSync(process.execPath, [path.join(link, 'server/capture.mjs')], {
    input: JSON.stringify({ session_id: 's', hook_event_name: 'Stop', last_assistant_message: 'hi' }),
    env: { ...process.env, CLAUDE_BOARD_DIR: boardDir },
    encoding: 'utf8',
    timeout: 5000,
  });
  assert.equal(res.status, 0);
  assert.equal(fs.readFileSync(path.join(boardDir, 'events.jsonl'), 'utf8').split('\n').filter(Boolean).length, 1);
  const bad = spawnSync(process.execPath, [path.join(link, 'server/board.mjs'), '--serve'], { encoding: 'utf8', timeout: 5000 });
  assert.match(bad.stderr, /unknown option/, 'board.mjs ran its main through the symlink');
});

test('the tail replays a log replaced by a longer one', () => {
  const file = path.join(tmp(), 'events.jsonl');
  const tail = createTail(file);
  fs.writeFileSync(file, '{"a":1}\n');
  tail.read();
  fs.writeFileSync(`${file}.new`, '{"b":1}\n{"b":2}\n{"b":3}\n');
  fs.renameSync(`${file}.new`, file);
  assert.equal(tail.read().truncated, true);
  tail.reset();
  assert.equal(tail.read().records.length, 3);
});

test('a history rescan skips transcripts that did not change', () => {
  const dir = tmp();
  writeTranscript(dir, 'one', [{ type: 'user', message: { content: 'hi' } }]);
  const seen = new Map();
  assert.equal(scanHistory(dir, 0, seen).length, 1);
  assert.equal(scanHistory(dir, 0, seen).length, 0);
});
