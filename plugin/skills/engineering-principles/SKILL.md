---
name: engineering-principles
description: Core code-quality rules — YAGNI, KISS, DRY with judgment, small single-purpose units, clear naming, minimal-scope diffs. Preload into implementer agents and consult during any code review. Use whenever writing, refactoring, or reviewing code.
---

# Engineering principles
Defaults, not dogma — when a rule conflicts with the repo's established patterns, the repo wins.

- **Match the repo.** Follow existing conventions, structure, and idioms even over personal preference. Consistency beats local "better".
- **YAGNI.** Build only what the task needs. No speculative abstractions, config knobs, unused params, or "future-proofing". Delete dead code.
- **KISS.** Simplest solution that works; optimize for the next reader, not cleverness.
- **DRY with judgment.** Rule of three before abstracting; a little duplication beats the wrong abstraction; don't couple unrelated code that merely looks similar.
- **Small units.** One thing, one reason to change; short functions; composition over inheritance; minimal public surface.
- **Naming/comments.** Intention-revealing names; comments explain *why*, not *what*; no commented-out code; no TODO graveyards.
- **Errors.** Fail fast, handle explicitly, validate at boundaries; never silently swallow.
- **Security.** Treat external input as untrusted — validate and encode at trust boundaries; prefer the framework's safe API (parameterized queries, safe templating) over hand-rolled escaping. Never hardcode or log secrets; least privilege by default.
- **Observability.** Make failures diagnosable — log with enough context to locate the cause and surface errors where they'll be seen, never bury them. Match the repo's logging idiom; no noisy logging on the happy path.
- **Minimal-scope diffs.** Smallest change that solves the problem; don't sprawl refactors into unrelated files; list unrelated improvements instead of doing them.
- **Backward compatibility.** Don't break existing callers or data — preserve public signatures, serialized formats, and observable behavior unless changing them is the task; when you must, migrate or version deliberately.
- **Dependencies.** Prefer stdlib/existing deps; don't add a package for something trivial.
- **Reach for new code last.** Before writing any, check these in order and stop at the first that applies. Subordinate to *match the repo*: never pick a shorter option over the house pattern.
  1. Not needed → don't build it.
  2. Stdlib or runtime covers it → use that.
  3. Native platform/framework feature covers it → use that.
  4. Installed dependency covers it → use that; don't add a new one.
  5. Collapses to a line or two without hurting readability → do that.
  6. Else write the minimum that works. On a tie between equal-size options, take the one that handles the edge cases.
- **Performance.** Clarity first; measure before optimizing.
- **Tests.** Test behavior, not implementation; meaningful assertions; no coverage theater.
- **Before finishing.** Re-read your diff as a reviewer; remove anything unneeded; confirm it follows repo conventions.
