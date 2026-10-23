// The command a card copies. The directory comes from hook payloads and
// transcripts, so a folder named `$(…)` must not run when the user pastes it:
// single quotes are literal in bash, zsh and PowerShell. Only a path made of
// letters, digits, marks and ASCII punctuation other than `'` gets the `cd`; that
// allowlist leaves out every quote-like character (PowerShell also ends a string
// on ’ ‘ ‚ ‛) and line breaks, and such a path gets no `cd` at all.

const SESSION_ID = /^[A-Za-z0-9-]+$/;
const QUOTABLE = /^[\p{L}\p{M}\p{N} !"#$%&()*+,\-./:;<=>?@[\\\]^_`{|}~]+$/u;

export function resumeCommand(card) {
  if (!SESSION_ID.test(card.id)) return { command: '', cdOmitted: false };
  const resume = `claude --resume ${card.id}`;
  if (!card.cwd) return { command: resume, cdOmitted: false };
  if (!QUOTABLE.test(card.cwd)) return { command: resume, cdOmitted: true };
  return { command: `cd '${card.cwd}'; ${resume}`, cdOmitted: false };
}
