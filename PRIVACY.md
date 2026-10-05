# Privacy Policy

**Effective date:** 2026-09-04

This policy covers the plugin published from this repository — `crew` —
distributed through the `johantor` marketplace and the Claude plugin directory.

## The short version

The plugins collect nothing. They are files that run inside your own Claude Code
session, on your own machine. There is no server behind them, no account, no
telemetry, and no data of yours ever reaches the maintainers.

## What these plugins are

Each plugin is a set of files that Claude Code loads into your session: Markdown
definitions for agents, commands, and skills, plus shell scripts wired as hooks.
There is no hosted service, no backend, and nothing to sign up for.

The hooks are ordinary shell scripts. They read the tool payload Claude Code
passes on stdin, decide whether to allow a call, and answer on stdout. They make
no network requests.

## Data the maintainers collect

**None.** No telemetry, no analytics, no crash reporting, no usage counters, and
no phone-home of any kind. The maintainers receive nothing when you install or
run these plugins, and therefore have nothing to store, share, or sell.

## Data processed on your machine

To do their work, the agents read and write files in the repository you run them
in — source code, tests, configuration, and git history. All of that processing
happens locally, in your working tree, under Claude Code's own permission
system and the plugins' guard hooks.

The plugins write only inside your repository:

- `.claude/crew.md` — the configuration `/crew:init` detects and records.
- `<plan-dir>/plan-<feature>.md` — the orchestrator's working plan, in `.claude/`
  unless you configure another directory.
- Ordinary git commits on the feature branch the orchestrator creates.

Nothing is copied anywhere else.

## Data that leaves your machine

Three paths, none of them the plugins' own and all of them under your control:

1. **Anthropic.** Claude Code sends your prompts, and the file content the agents
   read, to Anthropic's API to generate responses. This is how Claude Code works
   with or without these plugins. It is governed by
   [Anthropic's Privacy Policy](https://www.anthropic.com/legal/privacy) and the
   terms of your Claude plan, not by this policy.
2. **MCP servers you configure.** Some agents can use MCP servers — Playwright,
   Figma, Context7, a GitHub or Azure DevOps server — when you have them set up.
   **These plugins ship no MCP configuration and start no server.** The agent
   files only name tools they will use if you have already made them available.
   Anything sent to such a server is governed by that server's own terms.
3. **Your git remote.** `/crew:pr` pushes your branch and opens a pull request,
   and only when you run it. The crew stops at a local review gate by default;
   nothing is pushed on its own.

## Third parties

The maintainers share no data with anyone, because they receive none. There are
no advertisers, analytics vendors, or data processors involved.

## Changes to this policy

Changes are made in this file, and its full history is public in this
repository's git log. The effective date above changes with any material update.

## Contact

Questions about this policy: open an issue at
<https://github.com/johantor/crew/issues>.

To report a security vulnerability, follow [SECURITY.md](SECURITY.md) instead —
please do not use a public issue for that.
