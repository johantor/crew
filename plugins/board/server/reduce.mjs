// Card state is a fold over the event log: apply() takes one record (from
// capture.mjs, history.mjs or the server's own archive action) and updates the
// session's card. Pure apart from the board it mutates, so a replay rebuilds it.
//
// A card holds two things that change apart: the session's own turn (`turn`:
// working, yourTurn or closed, with `doing` as its activity) and the questions
// still open (`open`, keyed by who asked: SELF for the session, ERROR for a failed
// turn, else a subagent's id; and by the tool call). The card is in Needs me while
// any question is open, so one answer never hides another, and the turn underneath
// stays current.

const RECENT = 5;
const WORKERS = 20;
const SELF = '';
const ERROR = '!error';

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
      turn: 'yourTurn',
      ended: false,
      doing: '',
      open: {},
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

// A question is keyed by who asked and which tool call it gates (none for a
// question such as an MCP elicitation), so parallel calls each keep their own.
const key = (who, call) => `${who}|${call || ''}`;

function ask(c, who, call, text, ts) {
  c.open[key(who, call)] = { text, ts };
}

// A finished call answers its own question, and any call-less one from the same asker.
function answerCall(c, who, call) {
  if (!call) return answerAll(c, who);
  delete c.open[key(who, call)];
  delete c.open[key(who, '')];
}

function answerAll(c, who) {
  for (const k of Object.keys(c.open)) if (k.startsWith(`${who}|`)) delete c.open[k];
}

// `state` and `activity` are what the page shows: the newest open question, else the turn.
function derive(c) {
  const asks = Object.values(c.open);
  if (asks.length) {
    c.state = 'needs';
    c.activity = asks.reduce((a, b) => (b.ts >= a.ts ? b : a)).text;
  } else {
    c.state = c.turn;
    c.activity = c.doing;
  }
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
  c.turn = 'closed';
  c.summary = rec.msg || c.summary;
  c.doing = c.summary;
  if (rec.ts > c.lastTs) c.lastTs = rec.ts;
  derive(c);
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
  // SessionEnd is final until the session starts again: SessionEnd runs in the
  // foreground and the other hooks async, so a late Stop can land after it.
  if (c.ended && rec.e !== 'SessionStart') return;
  if (rec.ts > c.lastTs) c.lastTs = rec.ts;
  // Only the session's own events set where it resumes: a subagent may run in a
  // worktree that is gone once it finishes.
  if (!rec.aid) {
    if (rec.cwd) c.cwd = rec.cwd;
    if (rec.repo) c.repo = rec.repo;
    // An empty branch is news: the session left the repo, or HEAD went unreadable.
    if (typeof rec.branch === 'string') c.branch = rec.branch;
  }
  if (rec.pm) c.mode = rec.pm;
  if (rec.title) setTitle(c, rec.title, RANK.rename);
  if (typeof rec.agent === 'string' && rec.agent.startsWith('crew:')) c.crew = true;
  // `--agent` sessions carry agent_type with no agent_id: the session itself is that agent.
  if (rec.agent && !rec.aid) c.agent = rec.agent;

  if (rec.aid) applyWorker(c, rec);
  else applySelf(c, rec);
  derive(c);
}

// A subagent's events land on its parent's card, in the worker strip. A question
// it asks stays open until that subagent's tool finishes or the subagent stops.
function applyWorker(c, rec) {
  const w = worker(c, rec);
  switch (rec.e) {
    case 'SubagentStart':
      w.state = 'running';
      break;
    case 'PreToolUse':
      w.activity = rec.tool || w.activity;
      break;
    case 'PostToolUse':
    case 'PostToolUseFailure':
      answerCall(c, rec.aid, rec.call);
      break;
    case 'PermissionRequest':
      ask(c, rec.aid, rec.call, `${w.type} asks: allow ${rec.tool}?`, rec.ts);
      break;
    case 'Notification':
      if (rec.ntype !== 'idle_prompt') ask(c, rec.aid, '', `${w.type}: ${rec.msg || 'needs input'}`, rec.ts);
      break;
    case 'SubagentStop':
      w.state = 'done';
      w.msg = rec.msg || '';
      w.endTs = rec.ts;
      answerAll(c, rec.aid);
      break;
  }
}

// Hooks run async, so a PreToolUse can land just after the PermissionRequest of
// the same call: PreToolUse never answers a question. The tool's PostToolUse, a
// new prompt, a Stop or an idle notification does.
function applySelf(c, rec) {
  switch (rec.e) {
    case 'SessionStart':
      if (rec.model) c.model = rec.model;
      if (rec.source === 'compact') break;
      c.ended = false;
      c.turn = 'yourTurn';
      c.open = {};
      c.endReason = '';
      c.error = '';
      if (rec.source === 'resume') c.doing = 'Resumed';
      else if (!c.doing) c.doing = 'Started';
      break;
    case 'UserPromptSubmit':
      setTitle(c, rec.prompt, RANK.prompt);
      c.turn = 'working';
      answerAll(c, SELF);
      answerAll(c, ERROR);
      c.error = '';
      c.doing = rec.prompt || c.doing;
      break;
    case 'PreToolUse':
      c.turn = 'working';
      c.doing = rec.tool || c.doing;
      if (rec.tool) {
        c.recent.push({ ts: rec.ts, tool: rec.tool });
        if (c.recent.length > RECENT) c.recent.shift();
      }
      break;
    case 'PostToolUse':
    case 'PostToolUseFailure':
      c.turn = 'working';
      answerCall(c, SELF, rec.call);
      break;
    case 'PermissionRequest':
      ask(c, SELF, rec.call, `Allow: ${rec.tool}?`, rec.ts);
      break;
    case 'Notification':
      // Claude waits at the prompt: the turn ended, even with no Stop (Esc, a denied prompt).
      if (rec.ntype === 'idle_prompt') {
        if (c.turn !== 'closed') c.turn = 'yourTurn';
        answerAll(c, SELF);
      } else {
        ask(c, SELF, '', rec.msg || 'Needs input', rec.ts);
      }
      break;
    case 'Stop':
      c.turn = 'yourTurn';
      answerAll(c, SELF);
      c.summary = rec.msg || c.summary;
      c.doing = c.summary || 'Done';
      break;
    case 'StopFailure':
      c.turn = 'yourTurn';
      c.error = rec.error || 'error';
      ask(c, ERROR, '', `Error: ${rec.msg || c.error}`, rec.ts);
      break;
    case 'SessionEnd':
      c.ended = true;
      c.turn = 'closed';
      c.open = {};
      c.endReason = rec.reason || '';
      break;
  }
}

// The live card objects, newest first; the server serializes them as they are.
export function snapshot(board) {
  return [...board.cards.values()].sort((a, b) => b.lastTs - a.lastTs);
}
