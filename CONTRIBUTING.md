# Contributing to crew

The contributor guide is [AGENTS.md](AGENTS.md). It holds every rule once: the repository
layout, how to validate a change, when to bump the version, and the PR conventions. This file
only points there, so the two cannot drift.

The short version:

1. Open an issue first for anything bigger than a typo. Use the bug or feature template.
2. Branch from the latest `main`. One branch and one PR per issue.
3. Run what CI runs (*Validating changes* in AGENTS.md) before you push.
4. A shipped change bumps the version and adds a changelog line. *Releasing* in AGENTS.md says
   which files count as shipped; tests and the plugin's `CLAUDE.md` do not.
5. Title the PR in Conventional Commits form and fill in the PR template.

Report a security issue privately, as [SECURITY.md](SECURITY.md) describes, not in a public
issue. Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
