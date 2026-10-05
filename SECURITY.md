# Security Policy

crew is a [Claude Code](https://code.claude.com/docs/en/overview) plugin
marketplace (`crew`). Much of its value is
in *guardrails* — the Bash hooks that block unsafe commands and enforce write
lanes — so a way to bypass a guard is a security bug, and we want to hear about
it privately before it's public.

## Reporting a vulnerability

**Please do not open a public issue for a security report.** Use GitHub's
private vulnerability reporting instead:

1. Open the **Security** tab of this repository and select **Advisories**.
2. Click **Report a vulnerability** and describe the issue.

That keeps the details private until a fix ships. We'll acknowledge the report,
work with you on a fix, and credit you in the release notes unless you prefer to
stay anonymous.

## In scope

Anything that lets an agent do something the guards are meant to prevent — for
example:

- A command that `plugins/*/hooks/bash-safety.sh` should block (destructive
  `rm`, force-push, writes into `.git/`, a worker running `git`, a protected-
  branch commit) but doesn't.
- A file write that `plugins/*/hooks/lane-guard.sh` should keep in-lane but lets through.
- A guard that fails **open** where it's documented to fail **closed**
  (`bash-safety.sh` and `lane-guard.sh` must block when they can't inspect their
  input; `read-guard.sh` is context-hygiene and fails open by design).
- A bypass of the drift/wiring checks in `scripts/validate-plugin.sh` that would
  let a diverged shared skill or an unwired hook ship undetected.

## Out of scope

- **The prose contracts** (agent/command/skill Markdown). These are executed by
  an LLM at runtime, not by a deterministic parser — their behavior is verified
  by the manual verification matrix, not this policy. A model choosing to ignore
  an instruction is a prompt-design issue, not a vulnerability; file it as a
  normal issue.
- Vulnerabilities in Claude Code itself, or in third-party MCP servers the
  plugins integrate with — report those to their respective projects.

## Supported versions

Fixes ship on the latest release (`crew/vX.Y.Z`); there are no
long-term-support branches.
Update with `claude plugin update <name>@johantor`.
