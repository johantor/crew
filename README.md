# Zion

<!-- Release-tag scheme is `plugin/vX.Y.Z` (see auto-release.yml). The label is
     blanked (`&label=`) so each badge is a single pill of the tag itself, which
     already names the plugin, instead of doubling it up as "crew crew/v3.5.2". -->
[![crew](https://img.shields.io/github/v/release/johantor/zion?filter=crew/v*&label=)](https://github.com/johantor/zion/releases)
[![Validate](https://github.com/johantor/zion/actions/workflows/validate.yml/badge.svg)](https://github.com/johantor/zion/actions/workflows/validate.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**Ship features like a crew, not a single agent.** Zion is a
[Claude Code](https://code.claude.com/docs/en/overview) plugin marketplace for
team-style software delivery across .NET and Optimizely, Node and shell: a
captain that plans and delegates to backend, view, test, and design specialists
behind hook-enforced guardrails (**crew**). The same captain pays down tech debt and
upgrades dependencies one verified fix at a time.

```bash
claude plugin marketplace add johantor/zion
claude plugin install crew@zion
```

<!-- Illustration source: docs/solo-vs-crew.svg (edit the SVG, then re-export the PNG).
     A terminal-style animation of a /crew:feature run also lives at docs/demo.gif. -->
![A solo agent juggling every concern, versus the zion crew: planned lanes, a review gate, then a PR](docs/solo-vs-crew.png)

## Plugins

| Plugin | Status | What it does | Adds to your session |
|---|---|---|---|
| **[crew](plugins/crew/README.md)** | Stable | Orchestrated, multi-agent feature delivery: a captain (`morpheus`) plans the work and delegates to backend, client-facing, test, and visual-review specialists across .NET, Node, Python, Go, Rust, the JVM and shell, with a consolidated review gate before anything ships. | `/crew:*` commands, agents, safety hooks, skills |

## Requirements

- [Claude Code](https://code.claude.com/docs/en/overview) with plugin support
  (CLI, desktop, or IDE extension).
- A git repository: `crew` branches and commits its work.
- Optional, for `crew`'s visual review and PR workflows: Playwright, Figma, and
  GitHub / Azure DevOps MCP servers. Setup is documented in the
  [crew README](plugins/crew/README.md); everything else works without them.

## Installation

Add the marketplace once:

```bash
claude plugin marketplace add johantor/zion
```

Then install the plugin:

```bash
claude plugin install crew@zion
```

Alternatively, install from the UI: run `/plugin` in Claude Code and browse to
**Discover**.

## Quick start

### crew — build a feature

```bash
claude --agent crew:morpheus     # dedicated orchestration session, just describe the feature
```

or, from a normal session:

```
/crew:init                 # once per project: detect and record build/test/lint config
/crew:feature <task>       # plan, delegate, build, then stop at the gate
/crew:review               # pre-PR GO / NO-GO: code + security + design review, build/test/lint
/crew:pr                   # push the branch and open the pull request
/crew:address              # route PR comments and CI failures back to the crew
/crew:triage <signal>      # a bug report, trace, or alert -> the code and the suspect commits
```

`morpheus` presents its plan before building, commits each verified step to a
feature branch, and runs workers in the background so you can keep talking to it
mid-flight. Nothing is pushed and no PR is opened until you say so.

### crew — fix debt, one pointer at a time

```
/crew:debt src/Orders/OrderService.cs:42    # a suppression at a specific line
/crew:debt CS8602                           # every suppression of a rule
/crew:debt eslint no-explicit-any           # an ESLint rule
/crew:debt Newtonsoft.Json 13.x             # a dependency upgrade
/crew:audit <scope>                         # read-only scout: returns ready-to-paste pointers
```

In a `claude --agent crew:morpheus` session, just name the pointer.

Each fix is classified, gated on its blast radius, fixed in verified batches,
and committed per batch. The deleted suppression makes the analyzer itself the
regression test. Supports .NET / C# and TypeScript / JavaScript today.

## Updating and uninstalling

```bash
claude plugin marketplace update zion    # refresh the plugin catalog
claude plugin update crew@zion           # update an installed plugin
claude plugin uninstall crew@zion        # remove a plugin
```

Release notes: [crew](plugins/crew/CHANGELOG.md).

## Documentation

- [crew](plugins/crew/README.md): agents, commands, hooks, background
  delegation, and optional MCP setup.
- [AGENTS.md](AGENTS.md): contributing a plugin or hacking on the crew.

## License

[Apache-2.0](LICENSE)

The plugins collect no data and send nothing to the maintainers — see
[PRIVACY.md](PRIVACY.md) for what stays local, what leaves your machine, and why.

---

<details>
<summary>Trivia: what's with the names?</summary>

Everything here is named from *The Matrix*. **Zion** is humanity's last city — the home
that houses the resistance, and a fitting name for a marketplace of crews. The agents are
mapped loosely to what they do:

- **morpheus** — the captain: plans and leads, writes no code himself (crew orchestrator).
- **neo** — "The One," not bound to a single role: the generalist who takes the express lane for small fixes.
- **tank** & **dozer** — the operators: **tank** runs the backend, **dozer** runs the e2e tests.
- **trinity** — the hacker on point: the client-facing layer.
- **oracle** — sees what will and won't hold up: the unit tests (backend, plus frontend component tests).
- **seraph** — the guardian who knows you by testing you ("you do not truly know someone until you fight them"): visual design conformance.
- **sentinel** — the machines' search unit, hunting through the dark: post-merge triage, tracking a production signal back to the commit that caused it.

</details>
