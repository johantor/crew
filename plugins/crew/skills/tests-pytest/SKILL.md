---
name: tests-pytest
description: Python backend test conventions — pytest layout and naming, conftest fixtures, parametrize, targeted reruns, unittest fallback. Load when the resolved backend stack is python.
---

# Backend tests: pytest (Python)

Detect the test framework from the project:

- `pytest.ini`, a `[tool.pytest.ini_options]` table in `pyproject.toml`, a `[pytest]` section in
  `setup.cfg`/`tox.ini`, or a `conftest.py` → **pytest**.
- Only `unittest.TestCase` subclasses and no pytest configuration → the project is on stdlib
  `unittest`. Write `unittest` tests; pytest can still run them, but don't introduce pytest-only
  constructs into a suite that doesn't use it.

## Naming and layout

pytest collects `test_*.py` and `*_test.py`, and within them `test_*` functions and `Test*`
classes (which must have no `__init__`). Follow the project's existing choice between the two file
spellings rather than mixing them.

Both a `tests/` directory beside the package and tests colocated in the package are valid; match
what is there. When `tests/` has no `__init__.py`, two test modules of the same basename in
different directories collide under the default import mode — give them distinct names rather than
adding `__init__.py` to a project that deliberately has none.

## Fixtures

`conftest.py` is where shared fixtures live, and it applies to its directory and below — a fixture
in the root `conftest.py` reaches every test. Prefer a narrow scope: put a fixture in the closest
`conftest.py` that needs it.

Fixture `scope=` (`function` by default, then `class`/`module`/`package`/`session`) decides how
often setup runs, and a wider scope shares mutable state between tests. Widen it only for
genuinely expensive, genuinely read-only setup, and never to make an order-dependent test pass.

Use `pytest.mark.parametrize` for the same assertion over several inputs rather than a loop inside
one test — a loop reports one failure and hides the rest.

## Running

- **Targeted rerun:** a node id or a `-k` expression — `pytest path/to/test_mod.py::test_name`,
  `pytest path/to/test_mod.py::TestClass::test_name`, or `pytest -k 'expression'`.
- **Discovery:** `pytest --collect-only -q path/to/test_mod.py` lists the node ids pytest would
  run without running them; a file or function the pattern misses shows up as an empty list, and
  the fix is the name or the config.
- **Summary line:** a run that collected zero tests exits 5 — the zero-tests failure. `xfail`,
  `xpass` and `skip` counts are results too.
- **Skip mechanism:** `skip`/`xfail` marks.
