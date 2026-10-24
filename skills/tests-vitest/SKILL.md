---
name: tests-vitest
description: Vitest component/unit test conventions — test authoring with React Testing Library, mocking patterns, and running. Load when the resolved frontend unit test tool is vitest.
---

# Frontend unit tests: Vitest

Write and run frontend component and unit tests using Vitest conventions. The unit-test script
is the project's own (`test`/`test:unit`) or `npx vitest run`.

- Test files are typically co-located with their source file (`Button.test.tsx` next to
  `Button.tsx`) or collected under `src/__tests__/`. Check the project's `vitest.config.ts`
  (or `.js`/`.mjs`) for the actual `include` pattern before creating a new file.
- Use `@testing-library/react` (`render`, `screen`) with `userEvent` from
  `@testing-library/user-event` for component tests; use plain `vi.fn()` / `vi.spyOn()` for
  unit mocks and `vi.mock()` for module mocks.
- Prefer queries that reflect how users perceive the UI (`getByRole`, `getByLabelText`,
  `getByText`) over implementation-detail selectors (`getByTestId`, CSS class).
- **Targeted rerun:** the test file path and/or `-t`/`--testNamePattern`. `--reporter` only
  changes output format; it does not filter which tests run.
- **Discovery:** `npx vitest list <file>` prints the test cases without running them. An empty
  list means the `include` pattern misses the file.
- **Skip mechanism:** `it.skip`/`describe.skip`.
