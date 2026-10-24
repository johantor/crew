---
name: tests-node
description: Node backend test conventions — Vitest or Jest, detected by config file (vitest.config.* vs jest.config.*/package.json "jest" key). Load when the resolved backend stack is node.
---

# Backend tests: Node (Vitest / Jest)

Detect the test framework from its config file:

- `vitest.config.*` present → **Vitest** conventions (`describe`/`it`/`expect`, `vi.fn()`
  mocks).
- `jest.config.*`, or a `jest` key in `package.json`, present → **Jest** conventions
  (`describe`/`it`/`expect`, `jest.fn()` mocks).

Run tests using the repository's backend test command from crew config, whichever framework
it resolves to. When the dispatch says the build and lint gates run beside you (`backend-node`,
"Parallel gates"), run that command exactly as given: a flag that writes into the tree
(`--coverage`, a file reporter) fails the recipe's tree check.

- **Targeted rerun:** the test file path as the path filter, plus `-t`/`--testNamePattern` to
  match by test name — both frameworks take both. Jest's `--testPathPattern` filters paths,
  never names.
- **Discovery:** Vitest lists test cases with `npx vitest list <file>`; Jest lists the files it
  would run with `npx jest --listTests` (files only — a listed file whose tests don't appear in
  the run summary has a `describe`/`it` problem, not a discovery one). A run that reports no
  tests is a config problem: the `include`/`testMatch` pattern, or a file name it misses.
- **Skip mechanism:** `it.skip`/`describe.skip`, `test.skip`.
