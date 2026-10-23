// Which column a card sits in. Time-based, so the page runs it on a timer, and the
// tests import it from here too.

export const STALE_MS = 10 * 60 * 1000;
// A session silent this long had its terminal closed without a SessionEnd.
export const GONE_MS = 12 * 60 * 60 * 1000;

export const COLUMNS = [
  { id: 'needs', label: 'Needs me' },
  { id: 'working', label: 'Working' },
  { id: 'yourTurn', label: 'Your turn' },
  { id: 'closedToday', label: 'Closed today' },
  { id: 'earlier', label: 'Earlier' },
];

function sameLocalDay(a, b) {
  const x = new Date(a);
  const y = new Date(b);
  return x.getFullYear() === y.getFullYear() && x.getMonth() === y.getMonth() && x.getDate() === y.getDate();
}

export function isGone(card, now) {
  return card.state !== 'closed' && now - card.lastTs >= GONE_MS;
}

export function columnOf(card, now) {
  if (card.state !== 'closed' && !isGone(card, now)) return card.state;
  return sameLocalDay(card.lastTs, now) ? 'closedToday' : 'earlier';
}

export function isStale(card, now) {
  return card.state === 'working' && !isGone(card, now) && now - card.lastTs >= STALE_MS;
}
