import { byRecency, COLUMNS, columnOf, isGone, isStale } from './columns.mjs';
import { resumeCommand } from './resume.mjs';

// Earlier shows a week; the server holds more, which search reaches.
const EARLIER_DAYS = 7;
const DAY_MS = 24 * 60 * 60 * 1000;

const cards = new Map();
const expanded = new Set();
let skew = 0; // server clock minus browser clock

const $ = (id) => document.getElementById(id);
const now = () => Date.now() + skew;

// The printed URL carries the token once. localStorage is scoped to this port's
// origin, unlike a cookie, so a bookmark of the bare URL keeps working and no
// other service on 127.0.0.1 ever sees the token.
const token = (() => {
  const url = new URL(location.href);
  const given = url.searchParams.get('t');
  if (given) {
    url.searchParams.delete('t');
    history.replaceState(null, '', url);
  }
  try {
    if (given) localStorage.setItem('board-token', given);
    return given || localStorage.getItem('board-token') || '';
  } catch {
    return given || '';
  }
})();

function el(tag, cls, text) {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
}

// The sprite in index.html holds the icons: the CSP loads no image files.
function icon(name) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('class', 'icon');
  svg.setAttribute('aria-hidden', 'true');
  const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
  use.setAttribute('href', `#i-${name}`);
  svg.append(use);
  return svg;
}

function ago(ts) {
  const s = Math.max(0, Math.floor((now() - ts) / 1000));
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return new Date(ts).toLocaleString(undefined, { weekday: 'short', hour: '2-digit', minute: '2-digit' });
}

function toast(text) {
  const t = $('toast');
  t.textContent = text;
  t.classList.add('show');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => t.classList.remove('show'), 2500);
}

async function copyResume(c) {
  const { command, cdOmitted } = resumeCommand(c);
  if (!command) return toast('This session id cannot be resumed from here.');
  const note = cdOmitted ? ` (no cd: the folder name holds a quote; cd to ${c.cwd} first)` : '';
  try {
    await navigator.clipboard.writeText(command);
    toast(`Copied: ${command}${note}`);
  } catch {
    window.prompt(`Copy this command${note}:`, command);
  }
}

async function setArchived(c, on) {
  const res = await fetch('/api/archive', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Board-Token': token },
    body: JSON.stringify({ sid: c.id, on }),
  });
  if (!res.ok) toast('Could not hide the card.');
}

function matches(c, f) {
  if (!f.archived && c.archived) return false;
  if (f.repo && c.repo !== f.repo) return false;
  if (f.q) {
    const hay = `${c.title} ${c.repo} ${c.branch} ${c.cwd} ${c.summary} ${c.id}`.toLowerCase();
    if (!hay.includes(f.q)) return false;
  }
  return true;
}

const STATE_LABEL = { needs: 'Needs me', working: 'Working', yourTurn: 'Your turn', closed: 'Closed' };

// `action` names the button so focus can return to it after the card is rebuilt.
// An icon-only button carries its label as aria-label and tooltip.
function button(label, cls, action, onClick, iconName, iconOnly = false) {
  const b = el('button', cls);
  b.type = 'button';
  b.dataset.action = action;
  if (iconName) b.append(icon(iconName));
  if (iconOnly) {
    b.setAttribute('aria-label', label);
    b.title = label;
  } else {
    b.append(label);
  }
  b.addEventListener('click', (ev) => {
    ev.stopPropagation();
    onClick();
  });
  return b;
}

function chip(cls, iconName, text) {
  const node = el('span', `chip ${cls}`);
  node.append(icon(iconName), el('span', '', text));
  node.title = text;
  return node;
}

function renderCard(c, t) {
  const node = el('article', 'card');
  const state = c.state === 'closed' || isGone(c, t) ? 'closed' : c.state;
  node.dataset.state = state;
  node.dataset.sid = c.id;
  if (c.archived) node.classList.add('archived');
  // A click anywhere is a mouse shortcut; the Copy resume button is the keyboard path.
  node.addEventListener('click', () => copyResume(c));
  const titleId = `t-${c.id}`;
  node.setAttribute('aria-labelledby', titleId);

  const head = el('div', 'card-head');
  // The dot and the quote bar show the state; the label stays for screen readers.
  const time = el('time', 'time', ago(c.lastTs));
  time.dateTime = new Date(c.lastTs).toISOString();
  time.title = new Date(c.lastTs).toLocaleString();
  head.append(el('span', 'dot'), el('span', 'sr-only', STATE_LABEL[state]), time);
  const title = el('h3', 'title', c.title || c.id.slice(0, 8));
  title.id = titleId;
  node.append(head, title);
  if (c.repo || c.branch) {
    const chips = el('div', 'chips');
    if (c.repo) chips.append(chip('repo', 'folder', c.repo));
    if (c.branch) chips.append(chip('mono', 'branch', c.branch));
    node.append(chips);
  }
  if (c.activity) node.append(el('div', 'activity', c.activity));

  const badges = el('div', 'badges');
  if (c.crew) badges.append(el('span', 'badge crew', c.agent || 'Crew'));
  else if (c.agent) badges.append(el('span', 'badge', c.agent));
  // Only a risky mode stays on the card; the rest of the session facts are under More.
  if (c.mode === 'bypassPermissions') badges.append(el('span', 'badge warn', c.mode));
  if (isStale(c, t)) badges.append(el('span', 'badge warn', 'stale?'));
  if (isGone(c, t)) badges.append(el('span', 'badge', 'no end event'));
  if (c.archived) badges.append(el('span', 'badge', 'hidden'));
  if (badges.childElementCount) node.append(badges);

  // Subagents are part of this session: running ones show here, finished ones count.
  const running = c.workers.filter((w) => w.state === 'running');
  const done = c.workers.length - running.length;
  if (c.workers.length) {
    const strip = el('div', 'workers');
    for (const w of running) {
      const row = el('div', 'worker');
      row.append(el('span', 'dot'), el('span', 'type', w.type));
      if (w.activity) {
        row.append(el('span', 'mono', w.activity));
        row.title = `${w.type}: ${w.activity}`;
      }
      strip.append(row);
    }
    if (done) strip.append(el('div', 'done', `✓ ${done} subagent${done === 1 ? '' : 's'} finished`));
    node.append(strip);
  }

  const open = expanded.has(c.id);
  const more = button(open ? 'Less' : 'More', '', 'more', () => {
    if (expanded.has(c.id)) expanded.delete(c.id);
    else expanded.add(c.id);
    render();
  }, 'chevron', true);
  more.setAttribute('aria-expanded', String(open));
  more.setAttribute('aria-controls', `d-${c.id}`);
  const actions = el('div', 'actions');
  actions.append(
    button('Copy resume', 'primary', 'copy', () => copyResume(c), 'copy'),
    more,
    button(c.archived ? 'Unhide' : 'Hide', '', 'archive', () => setArchived(c, !c.archived), c.archived ? 'eye' : 'eye-off', true),
  );
  node.append(actions);

  if (open) node.append(renderDetail(c));
  return node;
}

function renderDetail(c) {
  const d = el('div', 'detail');
  d.id = `d-${c.id}`;
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
  const facts = [];
  if (c.mode && c.mode !== 'default') facts.push(`mode: ${c.mode}`);
  if (c.endReason && c.endReason !== 'other') facts.push(`ended: ${c.endReason}`);
  if (!c.hooks) facts.push('from history, no hooks');
  if (facts.length) d.append(el('h3', '', 'Session'), el('p', '', facts.join(' · ')));
  const { command } = resumeCommand(c);
  if (command) d.append(el('h3', '', 'Resume'), el('p', 'mono', command));
  return d;
}

function filters() {
  return {
    q: $('search').value.trim().toLowerCase(),
    repo: $('repo').value,
    archived: $('archived').checked,
  };
}

let repoList = '';
function renderRepoOptions() {
  const repos = [...new Set([...cards.values()].map((c) => c.repo).filter(Boolean))].sort();
  if (repos.join('\n') === repoList) return;
  repoList = repos.join('\n');
  const select = $('repo');
  const current = select.value;
  select.replaceChildren(el('option', '', 'All repos'), ...repos.map((r) => el('option', '', r)));
  select.firstChild.value = '';
  select.value = repos.includes(current) ? current : '';
}

// Columns are built once; a card's node is rebuilt only when what it shows changes,
// so a push every second neither costs a full layout nor drops keyboard focus.
const columnEls = new Map();
const cardEls = new Map(); // sid -> { key, node }
// Sessions that appeared after the first load fade in once; a rebuild never animates.
const seen = new Set();
const fresh = new Set();

function columnEl(col) {
  let entry = columnEls.get(col.id);
  if (!entry) {
    const section = el('section', 'column');
    section.dataset.col = col.id;
    const count = el('span', 'count', '0');
    const h = el('h2');
    h.append(el('span', '', col.label), count);
    const list = el('div', 'list');
    section.append(h, list);
    const empty = el('div', 'empty');
    if (col.id === 'needs') empty.append(icon('check'));
    empty.append(col.empty);
    entry = { section, count, list, empty };
    columnEls.set(col.id, entry);
    $('board').append(section);
  }
  return entry;
}

function cardEl(c, t) {
  // Everything the card shows except the relative time, which is patched in place.
  const key = JSON.stringify([c, expanded.has(c.id), isStale(c, t), isGone(c, t)]);
  let entry = cardEls.get(c.id);
  if (!entry || entry.key !== key) {
    entry = { key, node: renderCard(c, t) };
    if (fresh.delete(c.id)) entry.node.classList.add('is-new');
    cardEls.set(c.id, entry);
  } else {
    entry.node.querySelector('.time').textContent = ago(c.lastTs);
  }
  return entry.node;
}

// Touch only the nodes that changed: `replaceChildren` empties the list first, and the
// browser drops the page scroll to the top (Hide or More on a card far down).
function syncChildren(list, want) {
  const keep = new Set(want);
  for (const n of [...list.children]) if (!keep.has(n)) n.remove();
  want.forEach((n, i) => {
    if (list.children[i] !== n) list.insertBefore(n, list.children[i] ?? null);
  });
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

  const active = document.activeElement;
  const focusSid = active?.closest?.('.card')?.dataset.sid;
  const focusAction = active?.dataset?.action;

  for (const col of COLUMNS) {
    const entry = columnEl(col);
    const nodes = groups[col.id].sort(byRecency(t)).map((c) => cardEl(c, t));
    entry.count.textContent = String(nodes.length);
    syncChildren(entry.list, nodes.length ? nodes : [entry.empty]);
  }
  for (const sid of cardEls.keys()) if (!cards.has(sid)) cardEls.delete(sid);
  fresh.clear();
  // The board usually sits in a background tab: the title carries what needs you.
  const needs = groups.needs.length;
  document.title = needs ? `(${needs}) Session Board` : 'Session Board';

  // A rebuilt card, or a reordered column, took focus off the button: put it back.
  // Compare with the active element, not presence: a moved node is back in the document but blurred.
  if (focusSid && focusAction && document.activeElement !== active) {
    cardEls.get(focusSid)?.node.querySelector(`[data-action="${focusAction}"]`)?.focus({ preventScroll: true });
  }
}

function connect() {
  const live = $('live');
  // Every (re)connect starts with a full `state` event, so nothing between snapshot and stream is lost.
  if (!token) {
    live.textContent = 'no token: open the board with /board:open';
    return;
  }
  const es = new EventSource(`/api/stream?t=${encodeURIComponent(token)}`);
  es.onopen = () => {
    live.textContent = 'live';
    live.classList.add('on');
  };
  es.onerror = () => {
    // A 401 closes the stream for good; a dropped connection retries on its own.
    live.textContent = es.readyState === EventSource.CLOSED ? 'token refused: open the board with /board:open' : 'offline';
    live.classList.remove('on');
  };
  es.addEventListener('cards', (ev) => {
    const data = JSON.parse(ev.data);
    skew = data.now - Date.now();
    for (const c of data.cards) {
      if (!seen.has(c.id)) fresh.add(c.id);
      seen.add(c.id);
      cards.set(c.id, c);
    }
    renderRepoOptions();
    render();
  });
  es.addEventListener('state', (ev) => {
    const data = JSON.parse(ev.data);
    skew = data.now - Date.now();
    cards.clear();
    for (const c of data.cards) {
      seen.add(c.id);
      cards.set(c.id, c);
    }
    renderRepoOptions();
    render();
  });
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
for (const id of ['repo', 'archived']) $(id).addEventListener('input', render);
// Typing re-filters every card: wait for a pause.
let searchTimer;
$('search').addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(render, 150);
});
// `/` jumps to search, unless the key is typed into a field.
document.addEventListener('keydown', (ev) => {
  if (ev.key !== '/' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
  if (ev.target.closest?.('input, select, textarea, [contenteditable]')) return;
  ev.preventDefault();
  $('search').focus();
});
setInterval(render, 30000);
connect();
