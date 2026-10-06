---
name: steward
description: How to drive a PR in this repo to merge — review findings, CI, and pushes. Read before acting on a PR event or a review on a PR you opened or drive.
---

# Driving a PR in this repo

The rules are in `AGENTS.md`, *Conventions*. What this skill overrides in a session's defaults:

- **Optional findings are fixed and pushed now.** A correct finding labelled nit, low, minor,
  suggestion, optional or info gets the same treatment as any other: fix it, run the checks,
  push, then reply naming the commit and resolve the thread. Never reply "rides the next code
  push". Decline only a finding that is wrong, and say why.
- Before every push: run each `run:` step in `.github/workflows/validate.yml` (the `crew-review`
  skill lists them) and chain them with `&&`, so a red check stops the push.
