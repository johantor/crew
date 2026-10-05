---
name: worker-contract
description: "The rules every crew worker with a shell follows on any dispatch from morpheus: never run git except a plain git mv, ask rather than guess what the delegation left out, treat the build and full suites as morpheus's final gate and run them as the handoff says, never leave a command running at hand-back, hand back with a completion marker and a remaining: line, name an MCP server you expected but cannot see, use a docs MCP over memory, and keep local memory. Preloaded by tank, trinity, oracle, dozer and neo; not for standalone use."
---

# Worker contract

You work one delegation from `crew:morpheus` and hand back. These rules hold on every dispatch;
your own prompt adds what is specific to your role, and your stack skill adds what is specific
to its tool.

- **Never run `git`, except a plain `git mv`.** `crew:morpheus` owns branching and commits. A
  rename your step needs is `git mv <from> <to>` inside your lane: alone in the command, paths
  relative to the worktree, never `-f`, `-C` or `cd`. Say it in your summary so the commit
  carries it. Never recreate the file under the new path instead.
- **Ask, don't guess.** If the delegation omits something you must resolve from it — the stack,
  the mode, the test tool, the list of failing tests — ask `morpheus` rather than guessing.
- **The build and the full test suite are `morpheus`'s final gate, not your self-check.** Verify
  your work with reasoning, targeted reads and the edit/lint feedback loop. Run a build or a
  suite only when a handoff delegates it, and then exactly as the handoff gives it — the
  command, where it runs, what to report — never a watch/dev/serve command. Your stack skill
  names those commands, the flags that weaken its tool, its lock signature and what a no-op run
  proves. If you think a gate is warranted earlier, say so in your summary and let `morpheus`
  decide.
- **A `format hook:` line that names `/crew:init` goes in your hand-back**, verbatim: it means
  the format matrix is stale, which `morpheus` relays to the user and you cannot fix.
- **Never end your turn while a command you started still runs** — that late report can miss
  `morpheus`. Never `run_in_background` a build or a suite; the gate handoff gives the wait
  recipe.
- **Hand back with a completion marker.** Say what you completed and, if anything is left
  undone, a `remaining:` line naming exactly what — files not changed, tests not written or not
  run, a run cut off partway. Never report a step complete when you stopped short of it, and
  never let silence read as "all green". If the task is larger than one clean pass, stop at a
  safe boundary (a coherent, self-consistent change) and hand back the rest the same way;
  `morpheus` resumes it.
- **A server you expected but cannot see** may be plugin-installed
  (`mcp__plugin_<plugin>_<server>`) and simply not in your `tools:`. Report it by name in your
  hand-back rather than silently working without it. From any MCP, fetch the specific item, not
  a dump (`context-discipline`).
- **When a docs MCP (e.g. Context7) is available**, consult it for current, version-specific
  API docs before coding against a library or framework, rather than relying on memory; fetch
  the specific topic, not a dump.
- **Consult local memory before starting and update it after finishing.**
