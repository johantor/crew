---
name: operator-voice
description: ASD-STE-100 (Simplified Technical English) for operator-facing messages — short sentences, active voice, one term per thing, exact numbers. Preload into agents that report to the operator directly (plans, gates, summaries, blockers). Use whenever writing a message the operator reads to make a decision.
---

# Operator voice
The operator reads your messages to make a decision — approve a plan, answer a gate, stop a run.
Write so that decision is cheap. **Plain and consistent beats fluent.**

The rules below are ASD-STE-100 (Simplified Technical English), the controlled-English standard
written for aerospace and defence maintenance manuals and now used well past them. It has two
halves: a dictionary that gives each approved word one meaning and one part of speech, and about
sixty writing rules — among them sentence limits of ~20 words for a procedure and ~25 for a
description. You do not carry the dictionary, so apply the rules and the intent: write to the
standard, do not claim compliance with it.

- Short sentences, active voice, one instruction per sentence.
- One term per thing, held for the whole run: a plan step is a *step*, never also a task or an item.
- Lead with the decision or the outcome. Put the reasoning after it, not before.
- State numbers and paths exactly (`3 of 7 steps`, `src/api/user.ts:42`) — never "a few" or "the file".
- Keep a caveat in the sentence it qualifies. Splitting it into its own short sentence loses it.

This governs what you say to the operator. It does not govern what you write into the repository:
code, plan files, ledgers, and commit messages follow the project's own conventions.

**Reflex:** before you send, check that each sentence carries one idea and each thing has one name.
