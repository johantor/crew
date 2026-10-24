---
name: tests-playwright
description: Playwright e2e test conventions — spec writing, fixture/mock patterns, and running. Load when the resolved frontend e2e tool is playwright.
---

# Frontend e2e tests: Playwright

Write and run frontend e2e specs using Playwright conventions and the repository's frontend test command from crew config.

- Spec files typically live in `tests/` or `e2e/` (configured via `playwright.config.*`). In
  crew, keep them in a structured e2e location — `e2e/` or `tests/e2e/` — so they stay apart
  from backend tests, which a bare root `tests/` can also hold.
- Use `page.route()` for network mocking; `test.use({ storageState })` for auth state reuse.
- Prefer `getByRole()`, `getByTestId()`, and `getByLabel()` locators — avoid CSS/XPath selectors.
- **Targeted rerun:** the spec file path, or `--grep`.
- **Skip mechanism:** `test.skip`, `test.fixme`.
