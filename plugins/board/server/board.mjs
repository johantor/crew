// The board server: folds history and the hook log into cards, serves the page,
// and pushes changed cards over SSE. Binds 127.0.0.1 only: transcripts hold
// client code. Usage: node board.mjs [--port N] [--days N] [--detach] [--open]
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { boardDir, eventsFile, isMain, projectsDir } from './paths.mjs';
import { apply, createBoard, snapshot } from './reduce.mjs';
import { scanHistory } from './history.mjs';

const HOST = '127.0.0.1';
const APP = 'claude-board';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(HERE, 'public');
const DAY_MS = 24 * 60 * 60 * 1000;
const TAIL_CHUNK = 4 * 1024 * 1024;

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
  // Port 0 asks the OS for a free port (the tests use it); a detached board needs a known one.
  if (!Number.isInteger(opts.port) || opts.port < 0 || opts.port > 65535) throw new Error('--port takes 0-65535');
  if (opts.detach && opts.port === 0) throw new Error('--detach needs a fixed --port');
  if (!(opts.days > 0)) throw new Error('--days takes a positive number');
  return opts;
}

// 127.0.0.1 is shared by every user on the machine, so the board asks for a
// token kept in the user's own 0600 file. It persists, so a bookmark keeps working.
export function loadToken() {
  const file = path.join(boardDir(), 'token');
  fs.mkdirSync(boardDir(), { recursive: true, mode: 0o700 });
  try {
    fs.writeFileSync(file, crypto.randomBytes(24).toString('hex'), { mode: 0o600, flag: 'wx' });
  } catch (err) {
    if (err.code !== 'EEXIST') throw err;
  }
  const token = fs.readFileSync(file, 'utf8').trim();
  if (!/^[0-9a-f]{48}$/.test(token)) throw new Error(`${file} is not a board token; delete it and start again`);
  return token;
}

function sameToken(given, token) {
  const a = Buffer.from(String(given ?? ''));
  const b = Buffer.from(token);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export function proof(token, nonce) {
  return crypto.createHmac('sha256', token).update(nonce).digest('hex');
}

// Our board, not whatever else answers on the port: only ours can sign a fresh
// nonce with the token. The token itself never goes to the port.
async function isBoard(port, token) {
  try {
    const nonce = crypto.randomBytes(16).toString('hex');
    const res = await fetch(`http://${HOST}:${port}/api/health?n=${nonce}`, { signal: AbortSignal.timeout(500) });
    const body = await res.json();
    return body.app === APP && sameToken(body.proof, proof(token, nonce));
  } catch {
    return false;
  }
}

function portFree(port) {
  return new Promise((resolve) => {
    const probe = net.createServer();
    probe.once('error', () => resolve(false));
    probe.listen(port, HOST, () => probe.close(() => resolve(true)));
  });
}

function openBrowser(url) {
  const [cmd, args] =
    process.platform === 'win32'
      ? ['cmd', ['/c', 'start', '', url]]
      : [process.platform === 'darwin' ? 'open' : 'xdg-open', [url]];
  // A missing opener fails asynchronously; the URL is printed either way.
  const child = spawn(cmd, args, { detached: true, stdio: 'ignore', windowsHide: true });
  child.on('error', () => {});
  child.unref();
}

// Reads the log from a byte offset and returns whole records; a line still being
// written stays in `rest` until its newline arrives.
export function createTail(file) {
  let offset = 0;
  let rest = Buffer.alloc(0);
  let ino = null;
  return {
    reset() {
      offset = 0;
      rest = Buffer.alloc(0);
      ino = null;
    },
    read() {
      let st;
      try {
        st = fs.statSync(file);
      } catch {
        return { records: [], truncated: false };
      }
      // A shorter file, or another file at the same path: replay from the start.
      if (st.size < offset || (ino !== null && st.ino !== ino)) return { records: [], truncated: true };
      ino = st.ino;
      const records = [];
      if (st.size === offset) return { records, truncated: false };
      // Bounded chunks: one string of a large log would pass V8's string limit.
      const fd = fs.openSync(file, 'r');
      try {
        while (offset < st.size) {
          const buf = Buffer.alloc(Math.min(TAIL_CHUNK, st.size - offset));
          const n = fs.readSync(fd, buf, 0, buf.length, offset);
          if (n === 0) break;
          offset += n;
          const data = Buffer.concat([rest, buf.subarray(0, n)]);
          const end = data.lastIndexOf(0x0a);
          rest = data.subarray(end + 1);
          if (end < 0) continue;
          for (const line of data.subarray(0, end).toString('utf8').split('\n')) {
            if (!line.trim()) continue;
            try {
              records.push(JSON.parse(line));
            } catch {
              // A torn or foreign line: skip it, keep the rest.
            }
          }
        }
      } finally {
        fs.closeSync(fd);
      }
      return { records, truncated: false };
    },
  };
}

function startServer(opts) {
  const file = eventsFile();
  const tail = createTail(file);
  const history = new Map(); // transcript sid -> History record
  const seen = new Map(); // transcript file -> mtime:size it was read at
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
    broadcast('state', stateNow());
  }

  function rescanHistory() {
    for (const rec of scanHistory(projectsDir(), windowStart(), seen)) {
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

  function stateNow() {
    const since = windowStart();
    return { now: Date.now(), days: opts.days, cards: snapshot(board).filter((c) => c.lastTs >= since) };
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

  // Filled once the port is bound: with --port 0 it is known only then.
  const allowedHosts = new Set();
  const allowedOrigins = new Set();
  const types = { '.html': 'text/html; charset=utf-8', '.mjs': 'text/javascript', '.js': 'text/javascript', '.css': 'text/css' };
  // The page, code and style hold no session data, so they need no token.
  const statics = new Map([
    ['/', 'index.html'],
    ['/app.mjs', 'app.mjs'],
    ['/columns.mjs', 'columns.mjs'],
    ['/resume.mjs', 'resume.mjs'],
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

  // The token travels only as a header, never as a cookie: a cookie for 127.0.0.1
  // also goes to every other port there. EventSource cannot set a header, so the
  // stream alone takes it as `?t=`.
  function authorized(req, url) {
    if (sameToken(req.headers['x-board-token'], opts.token)) return true;
    return url.pathname === '/api/stream' && sameToken(url.searchParams.get('t'), opts.token);
  }

  function handle(req, res) {
    // A Host check stops DNS rebinding: another site's page cannot read the board.
    if (!allowedHosts.has(req.headers.host ?? '')) return send(res, 403, { error: 'forbidden host' });
    const url = new URL(req.url ?? '/', `http://${req.headers.host}`);

    if (req.method === 'GET' && statics.has(url.pathname)) {
      const name = statics.get(url.pathname);
      return send(res, 200, fs.readFileSync(path.join(PUBLIC, name)), types[path.extname(name)]);
    }
    if (req.method === 'GET' && url.pathname === '/favicon.ico') return send(res, 204, '');
    if (req.method === 'GET' && url.pathname === '/api/health') {
      // Signing a caller's nonce proves the token without sending it.
      const nonce = url.searchParams.get('n');
      return send(res, 200, /^[0-9a-f]{16,64}$/.test(nonce ?? '') ? { app: APP, proof: proof(opts.token, nonce) } : { app: APP });
    }
    if (!authorized(req, url)) return send(res, 401, { error: 'token required' });
    if (req.method === 'GET' && url.pathname === '/api/state') {
      return send(res, 200, stateNow());
    }
    if (req.method === 'GET' && url.pathname === '/api/stream') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
      // The snapshot rides the stream, so no push can fall between a separate fetch and the subscribe.
      res.write(`event: state\ndata: ${JSON.stringify(stateNow())}\n\n`);
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
        if (!msg || typeof msg !== 'object' || typeof msg.sid !== 'string' || !board.cards.has(msg.sid)) {
          return send(res, 404, { error: 'no such session' });
        }
        // This callback runs after handle() returned: its try/catch does not cover a full disk here.
        try {
          archive(msg.sid, msg.on !== false);
        } catch (err) {
          return send(res, 500, { error: err.message });
        }
        send(res, 200, { ok: true });
      });
      return;
    }
    send(res, 404, { error: 'not found' });
  }

  const server = http.createServer((req, res) => {
    // One bad request must not stop the board.
    try {
      handle(req, res);
    } catch (err) {
      if (!res.headersSent) send(res, 500, { error: err.message });
      else res.end();
    }
  });

  server.on('error', (err) => {
    console.error(err.code === 'EADDRINUSE' ? PORT_IN_USE(opts.port) : err.message);
    process.exit(1);
  });

  server.listen(opts.port, HOST, () => {
    opts.port = server.address().port;
    for (const h of [`${HOST}:${opts.port}`, `localhost:${opts.port}`]) {
      allowedHosts.add(h);
      allowedOrigins.add(`http://${h}`);
    }
    rescanHistory();
    pump();
    dirty.clear();
    // A timer's throw would stop the server; a log that cannot be read waits for the next tick.
    const guarded = (fn) => () => {
      try {
        fn();
      } catch (err) {
        console.error(`board: ${err.message}`);
      }
    };
    setInterval(guarded(pump), 1000).unref();
    setInterval(guarded(rescanHistory), 5 * 60 * 1000).unref();
    setInterval(() => {
      for (const c of clients) c.write(': ping\n\n');
    }, 25000).unref();
    const url = boardUrl(opts);
    console.log(`Board: ${url}`);
    if (opts.open) openBrowser(url);
  });
}

const boardUrl = (opts) => `http://${HOST}:${opts.port}/?t=${opts.token}`;

const PORT_IN_USE = (port) => `Port ${port} is in use. Pass --port or set CLAUDE_BOARD_PORT.`;

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
    opts.token = loadToken();
  } catch (err) {
    console.error(err.message);
    process.exit(2);
  }
  const url = boardUrl(opts);
  if (await isBoard(opts.port, opts.token)) {
    console.log(`Board already running: ${url}`);
    if (opts.open) openBrowser(url);
    return;
  }
  if (!opts.detach) return startServer(opts);

  // The detached child's stderr goes nowhere, so the parent reports a busy port.
  if (!(await portFree(opts.port))) {
    console.error(PORT_IN_USE(opts.port));
    process.exit(1);
  }
  const script = fileURLToPath(import.meta.url);
  const args = [script, '--port', String(opts.port), '--days', String(opts.days)];
  spawn(process.execPath, args, { detached: true, stdio: 'ignore', windowsHide: true }).unref();
  for (let i = 0; i < 50; i++) {
    if (await isBoard(opts.port, opts.token)) {
      console.log(`Board started: ${url}`);
      if (opts.open) openBrowser(url);
      return;
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  console.error(`The board did not start on port ${opts.port}. Run it in the foreground to see why: node "${script}" --port ${opts.port}`);
  process.exit(1);
}

if (isMain(process.argv[1], import.meta.url)) {
  main();
}
