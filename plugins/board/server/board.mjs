// The board server: folds history and the hook log into cards, serves the page,
// and pushes changed cards over SSE. Binds 127.0.0.1 only: transcripts hold
// client code. Usage: node board.mjs [--port N] [--days N] [--detach] [--open]
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { boardDir, eventsFile, projectsDir } from './paths.mjs';
import { apply, createBoard, snapshot } from './reduce.mjs';
import { scanHistory } from './history.mjs';

const HOST = '127.0.0.1';
const APP = 'claude-board';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(HERE, 'public');
const DAY_MS = 24 * 60 * 60 * 1000;

export function parseArgs(argv) {
  const opts = { port: Number(process.env.CLAUDE_BOARD_PORT) || 7428, days: 30, detach: false, open: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--detach') opts.detach = true;
    else if (a === '--open') opts.open = true;
    else if (a === '--port') opts.port = Number(argv[++i]);
    else if (a === '--days') opts.days = Number(argv[++i]);
    else throw new Error(`unknown option: ${a}`);
  }
  if (!Number.isInteger(opts.port) || opts.port < 1 || opts.port > 65535) throw new Error('--port takes 1-65535');
  if (!(opts.days > 0)) throw new Error('--days takes a positive number');
  return opts;
}

async function isBoard(port) {
  try {
    const res = await fetch(`http://${HOST}:${port}/api/health`, { signal: AbortSignal.timeout(500) });
    return (await res.json()).app === APP;
  } catch {
    return false;
  }
}

function openBrowser(url) {
  const [cmd, args] =
    process.platform === 'win32'
      ? ['cmd', ['/c', 'start', '', url]]
      : [process.platform === 'darwin' ? 'open' : 'xdg-open', [url]];
  try {
    spawn(cmd, args, { detached: true, stdio: 'ignore', windowsHide: true }).unref();
  } catch {
    // The URL is printed either way.
  }
}

// Reads the log from a byte offset and returns whole records; a line still being
// written stays in `rest` until its newline arrives.
export function createTail(file) {
  let offset = 0;
  let rest = Buffer.alloc(0);
  return {
    reset() {
      offset = 0;
      rest = Buffer.alloc(0);
    },
    read() {
      let size;
      try {
        size = fs.statSync(file).size;
      } catch {
        return { records: [], truncated: false };
      }
      if (size < offset) return { records: [], truncated: true };
      if (size === offset) return { records: [], truncated: false };
      const buf = Buffer.alloc(size - offset);
      const fd = fs.openSync(file, 'r');
      try {
        fs.readSync(fd, buf, 0, buf.length, offset);
      } finally {
        fs.closeSync(fd);
      }
      offset = size;
      const data = Buffer.concat([rest, buf]);
      const end = data.lastIndexOf(0x0a);
      rest = data.subarray(end + 1);
      const records = [];
      if (end >= 0) {
        for (const line of data.subarray(0, end).toString('utf8').split('\n')) {
          if (!line.trim()) continue;
          try {
            records.push(JSON.parse(line));
          } catch {
            // A torn or foreign line: skip it, keep the rest.
          }
        }
      }
      return { records, truncated: false };
    },
  };
}

function startServer(opts) {
  const file = eventsFile();
  const tail = createTail(file);
  const history = new Map(); // transcript sid -> History record
  const clients = new Set();
  const dirty = new Set();
  let board = createBoard();
  let flushTimer = null;

  const windowStart = () => Date.now() - opts.days * DAY_MS;

  function record(rec) {
    apply(board, rec);
    if (rec && typeof rec.sid === 'string') dirty.add(rec.sid);
  }

  function rebuild() {
    board = createBoard();
    tail.reset();
    for (const rec of history.values()) record(rec);
    for (const rec of tail.read().records) record(rec);
    dirty.clear();
    broadcast('reset', {});
  }

  function rescanHistory() {
    for (const rec of scanHistory(projectsDir(), windowStart())) {
      const prev = history.get(rec.sid);
      if (prev && prev.ts === rec.ts) continue;
      history.set(rec.sid, rec);
      record(rec);
    }
    scheduleFlush();
  }

  function pump() {
    const { records, truncated } = tail.read();
    if (truncated) return rebuild();
    for (const rec of records) record(rec);
    if (records.length) scheduleFlush();
  }

  function cardsInWindow() {
    const since = windowStart();
    return snapshot(board).filter((c) => c.lastTs >= since);
  }

  function broadcast(event, payload) {
    const msg = `event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`;
    for (const res of clients) res.write(msg);
  }

  function scheduleFlush() {
    if (flushTimer) return;
    flushTimer = setTimeout(() => {
      flushTimer = null;
      const cards = [...dirty].map((sid) => board.cards.get(sid)).filter(Boolean);
      dirty.clear();
      if (cards.length) broadcast('cards', { now: Date.now(), cards });
    }, 300);
  }

  function archive(sid, on) {
    fs.mkdirSync(boardDir(), { recursive: true, mode: 0o700 });
    fs.appendFileSync(file, `${JSON.stringify({ v: 1, ts: Date.now(), e: 'BoardArchive', sid, on })}\n`, { mode: 0o600 });
    pump();
  }

  const allowedHosts = new Set([`${HOST}:${opts.port}`, `localhost:${opts.port}`]);
  const allowedOrigins = new Set([...allowedHosts].map((h) => `http://${h}`));
  const types = { '.html': 'text/html; charset=utf-8', '.mjs': 'text/javascript', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' };
  const statics = new Map([
    ['/', 'index.html'],
    ['/app.mjs', 'app.mjs'],
    ['/columns.mjs', 'columns.mjs'],
    ['/theme.js', 'theme.js'],
    ['/board.css', 'board.css'],
  ]);

  function send(res, status, body, type = 'application/json') {
    res.writeHead(status, {
      'Content-Type': type,
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
      'Content-Security-Policy': "default-src 'self'; frame-ancestors 'none'",
    });
    res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body));
  }

  const server = http.createServer((req, res) => {
    // A Host check stops DNS rebinding: another site's page cannot read the board.
    if (!allowedHosts.has(req.headers.host ?? '')) return send(res, 403, { error: 'forbidden host' });
    const url = new URL(req.url ?? '/', `http://${req.headers.host}`);

    if (req.method === 'GET' && statics.has(url.pathname)) {
      const name = statics.get(url.pathname);
      return send(res, 200, fs.readFileSync(path.join(PUBLIC, name)), types[path.extname(name)]);
    }
    if (req.method === 'GET' && url.pathname === '/favicon.ico') return send(res, 204, '');
    if (req.method === 'GET' && url.pathname === '/api/health') return send(res, 200, { app: APP });
    if (req.method === 'GET' && url.pathname === '/api/state') {
      return send(res, 200, { now: Date.now(), days: opts.days, cards: cardsInWindow() });
    }
    if (req.method === 'GET' && url.pathname === '/api/stream') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
      res.write(': connected\n\n');
      clients.add(res);
      req.on('close', () => clients.delete(res));
      return;
    }
    if (req.method === 'POST' && url.pathname === '/api/archive') {
      // JSON only, from this origin: a cross-site form cannot send it without a preflight we never answer.
      const origin = req.headers.origin;
      if ((origin && !allowedOrigins.has(origin)) || !String(req.headers['content-type']).startsWith('application/json')) {
        return send(res, 403, { error: 'forbidden' });
      }
      let body = '';
      req.on('data', (chunk) => {
        body += chunk;
        if (body.length > 4096) req.destroy();
      });
      req.on('end', () => {
        let msg;
        try {
          msg = JSON.parse(body);
        } catch {
          return send(res, 400, { error: 'bad json' });
        }
        if (typeof msg.sid !== 'string' || !board.cards.has(msg.sid)) return send(res, 404, { error: 'no such session' });
        archive(msg.sid, msg.on !== false);
        send(res, 200, { ok: true });
      });
      return;
    }
    send(res, 404, { error: 'not found' });
  });

  server.on('error', (err) => {
    console.error(err.code === 'EADDRINUSE' ? `Port ${opts.port} is in use. Pass --port or set CLAUDE_BOARD_PORT.` : err.message);
    process.exit(1);
  });

  server.listen(opts.port, HOST, () => {
    rescanHistory();
    pump();
    dirty.clear();
    setInterval(pump, 1000).unref();
    setInterval(rescanHistory, 5 * 60 * 1000).unref();
    setInterval(() => {
      for (const c of clients) c.write(': ping\n\n');
    }, 25000).unref();
    const url = `http://${HOST}:${opts.port}/`;
    console.log(`Board: ${url}`);
    if (opts.open) openBrowser(url);
  });
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error(err.message);
    process.exit(2);
  }
  const url = `http://${HOST}:${opts.port}/`;
  if (await isBoard(opts.port)) {
    console.log(`Board already running: ${url}`);
    if (opts.open) openBrowser(url);
    return;
  }
  if (!opts.detach) return startServer(opts);

  const args = [fileURLToPath(import.meta.url), '--port', String(opts.port), '--days', String(opts.days)];
  spawn(process.execPath, args, { detached: true, stdio: 'ignore', windowsHide: true }).unref();
  for (let i = 0; i < 50; i++) {
    if (await isBoard(opts.port)) {
      console.log(`Board started: ${url}`);
      if (opts.open) openBrowser(url);
      return;
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  console.error(`The board did not start on port ${opts.port}. Run it in the foreground to see why: node "${fileURLToPath(import.meta.url)}"`);
  process.exit(1);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
