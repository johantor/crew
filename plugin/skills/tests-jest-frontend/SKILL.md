---
name: tests-jest-frontend
description: Jest frontend component/unit test conventions — test authoring with React Testing Library, mocking patterns, and running. Load when the resolved frontend unit test tool is jest.
---

# Frontend unit tests: Jest

Write and run frontend component and unit tests using Jest conventions. The unit-test script is
the project's own (`test`/`test:unit`) or `npx jest`.

- Test files are typically co-located with their source file (`Button.test.tsx` next to
  `Button.tsx`) or collected under `src/__tests__/`. Check the project's `jest.config.*` (or
  the `jest` key in `package.json`) for the actual `testMatch` / `testPathPattern` before
  creating a new file.
- Use `@testing-library/react` (`render`, `screen`) with `userEvent` from
  `@testing-library/user-event` for component tests; use
  plain `jest.fn()` / `jest.spyOn()` for unit mocks and `jest.mock()` for module mocks.
- Prefer queries that reflect how users perceive the UI (`getByRole`, `getByLabelText`,
  `getByText`) over implementation-detail selectors (`getByTestId`, CSS class).
- **Targeted rerun:** the test file path or `--testPathPattern` as the path filter, plus
  `-t`/`--testNamePattern` to match by test name.
- **Discovery:** `npx jest --listTests` (files only). A file the list misses has a `testMatch`
  problem.
- **Skip mechanism:** `it.skip`/`describe.skip`, `xit`.
