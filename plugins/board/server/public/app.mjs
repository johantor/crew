import { COLUMNS, columnOf, isGone, isStale } from './columns.mjs';

// Earlier shows a week; the server holds more, which search reaches.
const EARLIER_DAYS = 7;
const DAY_MS = 24 * 60 * 60 * 1000;

const cards = new Map();
const expanded = new Set();
let skew = 0; // server clock minus browser clock

const $ = (id) => document.getElementById(id);
const now = () => Date.now() + skew;

function el(tag, cls, text) {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
}

function ago(ts) {
  const s = Math.max(0, Math.round((now() - ts) / 1000));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  return new Date(ts).toLocaleString(undefined, { weekday: 'short', hour: '2-digit', minute: '2-digit' });
}

// bash, zsh and PowerShell all run `cd "<dir>"; claude --resume <id>`.
function resumeCommand(c) {
  const cd = c.cwd ? `cd "${c.cwd}"; ` : '';
  return `${cd}claude --resume ${c.id}`;
}

function toast(text) {
  const t = $('toast');
  t.textContent = text;
  t.classList.add('show');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => t.classList.remove('show'), 2500);
}

async function copyResume(c) {
  const cmd = resumeCommand(c);
  try {
    await navigator.clipboard.writeText(cmd);
    toast(`Copied: ${cmd}`);
  } catch {
    window.prompt('Copy this command:', cmd);
  }
}

async function setArchived(c, on) {
  const res = await fetch('/api/archive', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sid: c.id, on }),
  });
  if (!res.ok) toast('Could not archive the card.');
}

function matches(c, f) {
  if (!f.archived && c.archived) return false;
  if (f.repo && c.repo !== f.repo) return false;
  if (f.kind === 'crew' && !c.crew) return false;
  if (f.kind === 'manual' && c.crew) return false;
  if (f.q) {
    const hay = `${c.title} ${c.repo} ${c.branch} ${c.cwd} ${c.summary} ${c.id}`.toLowerCase();
    if (!hay.includes(f.q)) return false;
  }
  return true;
}

function renderCard(c, t) {
  const node = el('article', 'card');
  node.dataset.state = c.state === 'closed' || isGone(c, t) ? 'closed' : c.state;
  if (c.archived) node.classList.add('archived');
  node.title = 'Click to copy the resume command';
  node.addEventListener('click', () => copyResume(c));

  node.append(el('div', 'title', c.title || c.id.slice(0, 8)));
  const where = [c.repo, c.branch].filter(Boolean).join(' · ');
  if (where) node.append(el('div', 'where', where));
  if (c.activity) node.append(el('div', 'activity', c.activity));

  const badges = el('div', 'badges');
  if (c.crew) badges.append(el('span', 'badge crew', c.agent || 'Crew'));
  else if (c.agent) badges.append(el('span', 'badge', c.agent));
  if (c.mode && c.mode !== 'default') badges.append(el('span', 'badge', c.mode));
  if (isStale(c, t)) badges.append(el('span', 'badge warn', 'stale?'));
  if (isGone(c, t)) badges.append(el('span', 'badge', 'no end event'));
  if (c.endReason && c.endReason !== 'other') badges.append(el('span', 'badge', `ended: ${c.endReason}`));
  if (!c.hooks) badges.append(el('span', 'badge', 'history'));
  if (badges.childElementCount) node.append(badges);

  // Subagents are part of this session: running ones show here, finished ones count.
  const running = c.workers.filter((w) => w.state === 'running');
  const done = c.workers.length - running.length;
  if (c.workers.length) {
    const strip = el('div', 'workers');
    for (const w of running) {
      const row = el('div', 'worker');
      row.append(el('span', 'type', w.type));
      if (w.activity) row.append(document.createTextNode(` · ${w.activity}`));
      strip.append(row);
    }
    if (done) strip.append(el('div', 'done', `${done} subagent${done === 1 ? '' : 's'} finished`));
    node.append(strip);
  }

  const row = el('div', 'row');
  row.append(el('span', 'meta', ago(c.lastTs)));
  const actions = el('span');
  const more = el('button', '', expanded.has(c.id) ? 'Less' : 'More');
  more.type = 'button';
  more.addEventListener('click', (ev) => {
    ev.stopPropagation();
    if (expanded.has(c.id)) expanded.delete(c.id);
    else expanded.add(c.id);
    render();
  });
  const arch = el('button', '', c.archived ? 'Restore' : 'Archive');
  arch.type = 'button';
  arch.addEventListener('click', (ev) => {
    ev.stopPropagation();
    setArchived(c, !c.archived);
  });
  actions.append(more, ' ', arch);
  row.append(actions);
  node.append(row);

  if (expanded.has(c.id)) node.append(renderDetail(c));
  return node;
}

function renderDetail(c) {
  const d = el('div', 'detail');
  d.addEventListener('click', (ev) => ev.stopPropagation());
  if (c.summary) {
    d.append(el('h3', '', 'Last reply'), el('p', '', c.summary));
  }
  if (c.error) d.append(el('h3', '', 'Error'), el('p', '', c.error));
  if (c.recent.length) {
    d.append(el('h3', '', 'Recent tools'));
    const ul = el('ul');
    for (const r of [...c.recent].reverse()) ul.append(el('li', '', `${r.tool} (${ago(r.ts)})`));
    d.append(ul);
  }
  if (c.workers.length) {
    d.append(el('h3', '', 'Subagents'));
    const ul = el('ul');
    for (const w of [...c.workers].reverse()) {
      const text = w.state === 'running' ? `${w.type}: running${w.activity ? `, ${w.activity}` : ''}` : `${w.type}: ${w.msg || 'done'}`;
      ul.append(el('li', '', text));
    }
    d.append(ul);
  }
  d.append(el('h3', '', 'Resume'), el('p', '', resumeCommand(c)));
  return d;
}

function filters() {
  return {
    q: $('search').value.trim().toLowerCase(),
    repo: $('repo').value,
    kind: $('kind').value,
    archived: $('archived').checked,
  };
}

function renderRepoOptions() {
  const select = $('repo');
  const current = select.value;
  const repos = [...new Set([...cards.values()].map((c) => c.repo).filter(Boolean))].sort();
  select.replaceChildren(el('option', '', 'All repos'), ...repos.map((r) => el('option', '', r)));
  select.firstChild.value = '';
  select.value = repos.includes(current) ? current : '';
}

function render() {
  const t = now();
  const f = filters();
  const groups = Object.fromEntries(COLUMNS.map((col) => [col.id, []]));
  const earliest = t - EARLIER_DAYS * DAY_MS;
  for (const c of cards.values()) {
    if (!matches(c, f)) continue;
    const col = columnOf(c, t);
    if (col === 'earlier' && !f.q && c.lastTs < earliest) continue;
    groups[col]?.push(c);
  }
  const board = $('board');
  board.replaceChildren(
    ...COLUMNS.map((col) => {
      const list = groups[col.id].sort((a, b) => b.lastTs - a.lastTs);
      const section = el('section', 'column');
      section.dataset.col = col.id;
      const h = el('h2');
      h.append(el('span', '', col.label), el('span', '', String(list.length)));
      section.append(h);
      if (!list.length) section.append(el('div', 'empty', 'Nothing here'));
      for (const c of list) section.append(renderCard(c, t));
      return section;
    }),
  );
}

async function load() {
  const res = await fetch('/api/state');
  const data = await res.json();
  skew = data.now - Date.now();
  cards.clear();
  for (const c of data.cards) cards.set(c.id, c);
  renderRepoOptions();
  render();
}

function connect() {
  const live = $('live');
  const es = new EventSource('/api/stream');
  let opened = false;
  es.onopen = () => {
    live.textContent = 'live';
    live.classList.add('on');
    // A reconnect may have missed pushes: reload the whole board.
    if (opened) load();
    opened = true;
  };
  es.onerror = () => {
    live.textContent = 'offline';
    live.classList.remove('on');
  };
  es.addEventListener('cards', (ev) => {
    const data = JSON.parse(ev.data);
    skew = data.now - Date.now();
    for (const c of data.cards) cards.set(c.id, c);
    renderRepoOptions();
    render();
  });
  es.addEventListener('reset', () => load());
}

function initTheme() {
  const media = window.matchMedia('(prefers-color-scheme: dark)');
  let choice = 'auto';
  try {
    choice = localStorage.getItem('board-theme') || 'auto';
  } catch {
    // Storage blocked: the choice lasts for this page only.
  }
  const buttons = document.querySelectorAll('[data-theme-choice]');
  const applyChoice = () => {
    if (choice === 'auto') delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = choice;
    for (const b of buttons) b.setAttribute('aria-pressed', String(b.dataset.themeChoice === choice));
  };
  for (const b of buttons) {
    b.addEventListener('click', () => {
      choice = b.dataset.themeChoice;
      try {
        if (choice === 'auto') localStorage.removeItem('board-theme');
        else localStorage.setItem('board-theme', choice);
      } catch {
        // Not saved; still applied.
      }
      applyChoice();
    });
  }
  media.addEventListener('change', applyChoice);
  applyChoice();
}

initTheme();
for (const id of ['search', 'repo', 'kind', 'archived']) $(id).addEventListener('input', render);
setInterval(render, 30000);
load().catch(() => toast('Cannot reach the board server.'));
connect();
