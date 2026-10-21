// The command a card copies. The directory comes from hook payloads and
// transcripts, so a folder named `$(…)` must not run when the user pastes it:
// single quotes are literal in bash, zsh and PowerShell. A path holding a quote
// or a line break has no form all three read the same, so it gets no `cd`.

const SESSION_ID = /^[A-Za-z0-9-]+$/;

export function resumeCommand(card) {
  if (!SESSION_ID.test(card.id)) return { command: '', cdOmitted: false };
  const resume = `claude --resume ${card.id}`;
  if (!card.cwd) return { command: resume, cdOmitted: false };
  if (/['\r\n]/.test(card.cwd)) return { command: resume, cdOmitted: true };
  return { command: `cd '${card.cwd}'; ${resume}`, cdOmitted: false };
}
