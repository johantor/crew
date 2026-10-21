// Card state is a fold over the event log: apply() takes one record (from
// capture.mjs, history.mjs or the server's own archive action) and updates the
// session's card. Pure apart from the board it mutates, so a replay rebuilds it.

const RECENT = 5;
const WORKERS = 20;

// A /rename title beats a first prompt; history and hooks rank the same way.
const RANK = { prompt: 1, rename: 3 };

export function createBoard() {
  return { cards: new Map() };
}

function cardFor(board, sid, ts) {
  let c = board.cards.get(sid);
  if (!c) {
    c = {
      id: sid,
      title: '',
      titleRank: 0,
      cwd: '',
      repo: '',
      branch: '',
      state: 'yourTurn',
      activity: '',
      summary: '',
      error: '',
      endReason: '',
      mode: '',
      model: '',
      agent: '',
      crew: false,
      archived: false,
      hooks: false,
      firstTs: ts,
      lastTs: ts,
      recent: [],
      workers: [],
    };
    board.cards.set(sid, c);
  }
  return c;
}

// The first prompt sticks; a newer /rename replaces an older one.
function setTitle(c, title, rank) {
  if (title && (rank > c.titleRank || rank === RANK.rename)) {
    c.title = title;
    c.titleRank = rank;
  }
}

function worker(c, rec) {
  let w = c.workers.find((x) => x.id === rec.aid);
  if (!w) {
    w = { id: rec.aid, type: rec.agent || 'agent', state: 'running', activity: '', msg: '', startTs: rec.ts, endTs: 0 };
    c.workers.push(w);
    if (c.workers.length > WORKERS) c.workers.shift();
  }
  return w;
}

function applyHistory(c, rec) {
  // History fills gaps; it never overrides what a hook reported.
  if (!c.cwd && rec.cwd) c.cwd = rec.cwd;
  if (!c.repo && rec.repo) c.repo = rec.repo;
  if (!c.branch && rec.branch) c.branch = rec.branch;
  if (rec.rename) setTitle(c, rec.rename, RANK.rename);
  if (rec.prompt) setTitle(c, rec.prompt, RANK.prompt);
  if (rec.firstTs && rec.firstTs < c.firstTs) c.firstTs = rec.firstTs;
  if (c.hooks) return;
  c.state = 'closed';
  c.summary = rec.msg || c.summary;
  c.activity = c.summary;
  if (rec.ts > c.lastTs) c.lastTs = rec.ts;
}

export function apply(board, rec) {
  if (!rec || typeof rec.sid !== 'string' || typeof rec.ts !== 'number') return;
  const c = cardFor(board, rec.sid, rec.ts);

  if (rec.e === 'History') return applyHistory(c, rec);
  if (rec.e === 'BoardArchive') {
    c.archived = rec.on !== false;
    return;
  }

  c.hooks = true;
  if (rec.ts > c.lastTs) c.lastTs = rec.ts;
  if (rec.cwd) c.cwd = rec.cwd;
  if (rec.repo) c.repo = rec.repo;
  if (rec.branch) c.branch = rec.branch;
  if (rec.pm) c.mode = rec.pm;
  if (rec.title) setTitle(c, rec.title, RANK.rename);
  if (typeof rec.agent === 'string' && rec.agent.startsWith('crew:')) c.crew = true;
  // `--agent` sessions carry agent_type with no agent_id: the session itself is that agent.
  if (rec.agent && !rec.aid) c.agent = rec.agent;

  // A subagent's events land on its parent's card, in the worker strip. They move
  // the card only to and from Needs me: the parent's own events own the rest.
  if (rec.aid) {
    const w = worker(c, rec);
    switch (rec.e) {
      case 'SubagentStart':
        w.state = 'running';
        break;
      case 'PreToolUse':
        w.activity = rec.tool || w.activity;
        if (c.state === 'needs') c.state = 'working';
        break;
      case 'PostToolUse':
        if (c.state === 'needs') c.state = 'working';
        break;
      case 'PermissionRequest':
        c.state = 'needs';
        c.activity = `${w.type} asks: allow ${rec.tool}?`;
        break;
      case 'Notification':
        c.state = 'needs';
        c.activity = `${w.type}: ${rec.msg || 'needs input'}`;
        break;
      case 'SubagentStop':
        w.state = 'done';
        w.msg = rec.msg || '';
        w.endTs = rec.ts;
        break;
    }
    return;
  }

  switch (rec.e) {
    case 'SessionStart':
      if (rec.model) c.model = rec.model;
      if (rec.source === 'compact') break;
      c.state = 'yourTurn';
      c.endReason = '';
      c.error = '';
      if (rec.source === 'resume') c.activity = 'Resumed';
      else if (!c.activity) c.activity = 'Started';
      break;
    case 'UserPromptSubmit':
      setTitle(c, rec.prompt, RANK.prompt);
      c.state = 'working';
      c.error = '';
      c.activity = rec.prompt || c.activity;
      break;
    case 'PreToolUse':
      c.state = 'working';
      c.activity = rec.tool || c.activity;
      if (rec.tool) {
        c.recent.push({ ts: rec.ts, tool: rec.tool });
        if (c.recent.length > RECENT) c.recent.shift();
      }
      break;
    case 'PostToolUse':
      c.state = 'working';
      break;
    case 'PermissionRequest':
      c.state = 'needs';
      c.activity = `Allow: ${rec.tool}?`;
      break;
    case 'Notification':
      c.state = 'needs';
      c.activity = rec.msg || 'Needs input';
      break;
    case 'Stop':
      c.state = 'yourTurn';
      c.summary = rec.msg || c.summary;
      c.activity = c.summary || 'Done';
      break;
    case 'StopFailure':
      c.state = 'needs';
      c.error = rec.error || 'error';
      c.activity = `Error: ${rec.msg || c.error}`;
      break;
    case 'SessionEnd':
      c.state = 'closed';
      c.endReason = rec.reason || '';
      break;
  }
}

// Cards as plain objects for the API, newest first.
export function snapshot(board) {
  return [...board.cards.values()].sort((a, b) => b.lastTs - a.lastTs);
}
