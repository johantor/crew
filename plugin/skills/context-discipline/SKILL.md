---
name: context-discipline
description: Token/context discipline — process large data with code and surface only the answer, never read raw bulk output into context. Preload into agents that run verbose commands (tests, builds, log/data analysis). Use whenever about to read a large file, command output, or big API/tool response.
---

# Context discipline
Keep raw bulk data out of the context window. **Program the analysis — don't read everything in.** Raw output (logs, build streams, large files, full responses) is the main thing that silently fills the window and degrades quality.

- Before reading a large file or full output, ask: all of it, or a slice/answer? Fetch only the slice.
- Filter/search/count/transform with a script and print only the result — `grep`/`rg`, `jq`, `sed`/`awk`, or a short Node/Python one-off via Bash. One script replaces many reads.
- Don't `cat` a whole file to find one thing — `grep -n -C2` (or `rg`) for the match with a little context.
- For build/test output, capture to a file and grep it; surface a short summary, not the stream.
- When a tool/MCP returns a large blob (e.g. a full-page snapshot), request the narrowest form (specific element/fields), not the whole dump.
- Return summaries with an evidence pointer (file:line, command, count), not transcripts.

**Reflex:** if you're about to put more than a screenful of machine output into context, stop and script it instead.
