## Summary

<!-- Why this change, plus anything a reviewer needs to approve safely.
BUDGET: 150 words max here, 5 bullets max, whole body under 400 words. Count
before posting; if over, cut rather than reword.
NOT here: self-review write-ups, bugs-found-and-fixed logs, how-the-work-went
narrative, design-alternatives reasoning, pasted tool output. Those belong in the
commit message (not budgeted), the issue, or a review comment on the line.
See AGENTS.md, "Conventions". -->

-

## Scope

<!-- Which area does this touch? The plugin (agents, commands, skills, hooks), or the repo (docs, CI, tooling). -->

## Version / changelog

<!-- Per AGENTS.md "Releasing": a shipped change bumps the version. If this PR touches anything
under the plugin except tests/, CLAUDE.md, VERIFICATION.md and the changelog itself, bump
`version` in `plugin/.claude-plugin/plugin.json` and add a matching `CHANGELOG.md` entry.
CI (`scripts/check-changelog.sh`) blocks a shipped change without a bump. Only changes that
reach no user through `claude plugin update` are N/A. Entries are one line, two at most: what
changed, not why — the why is in the commit message. -->

- [ ] Bumped `plugin/.claude-plugin/plugin.json` version + matching `CHANGELOG.md` entry
- [ ] Each changelog bullet is one line, two at most
- [ ] N/A — nothing shipped changed (CI, root docs, tests)

## Test plan

<!-- What you ran, as results not transcripts: "ran X, all green", or one line
per case. Never paste output. Per AGENTS.md "Validating changes". -->

- [ ] `shellcheck plugin/hooks/*.sh plugin/hooks/lib/*.sh plugin/scripts/*.sh tests/*.sh scripts/*.sh`
- [ ] `bash scripts/validate-plugin.sh`
- [ ] Manually exercised the affected agent/command/skill flow

## Related issues

<!-- Use a closing keyword (Closes/Fixes/Resolves #N) so the issue auto-closes on merge.
Plain references (Implements #N) only cross-link, they don't close it. -->
