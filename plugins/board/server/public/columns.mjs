// Which column a card sits in. Time-based, so the page runs it on a timer, and the
// tests import it from here too.

export const STALE_MS = 10 * 60 * 1000;
// A session silent this long had its terminal closed without a SessionEnd.
export const GONE_MS = 12 * 60 * 60 * 1000;

export const COLUMNS = [
  { id: 'needs', label: 'Needs me', empty: 'Nothing needs you' },
  { id: 'working', label: 'Working', empty: 'Nothing running' },
  { id: 'yourTurn', label: 'Your turn', empty: 'Nothing waits on you' },
  { id: 'closedToday', label: 'Closed today', empty: 'Nothing closed today' },
  { id: 'earlier', label: 'Earlier', empty: 'Nothing from this week' },
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

// Cards sort by age group, then by when the session started: two busy sessions both
// "0s ago" would otherwise swap places on every push.
const AGE_GROUPS_MS = [30e3, 60e3, 30 * 60e3, 60 * 60e3, 6 * 60 * 60e3, 24 * 60 * 60e3];

export function ageGroup(card, now) {
  const age = now - card.lastTs;
  const i = AGE_GROUPS_MS.findIndex((max) => age < max);
  // Past a day, one group per day.
  return i >= 0 ? i : AGE_GROUPS_MS.length + Math.floor(age / AGE_GROUPS_MS.at(-1));
}

export function byRecency(now) {
  return (a, b) => ageGroup(a, now) - ageGroup(b, now) || b.firstTs - a.firstTs || (a.id < b.id ? -1 : 1);
}

export function isStale(card, now) {
  return card.state === 'working' && !isGone(card, now) && now - card.lastTs >= STALE_MS;
}
