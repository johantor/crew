---
name: backend-python
description: Python backend stack conventions — FastAPI/Django/Flask service conventions, packaging and virtualenv awareness, typecheck-as-build, ruff/black lint. Load when the resolved backend stack is python.
---

# Backend: Python

You are working in a Python backend: a service framework (FastAPI, Django, or Flask — follow
whichever the project already uses), a dependency manifest (`pyproject.toml`, or a legacy
`requirements*.txt`/`setup.py`), and a virtual environment.

Read the project's own layout before adding to it. A `src/<package>/` layout, a flat package at
the repo root, and a Django project with per-app directories are all valid shapes — match the one
that is there rather than importing a layout from another project.

## Crew config

`/crew:init` proposes: build is the static gate — `mypy .` from a `[tool.mypy]`/`mypy.ini`,
`pyright` from a `[tool.pyright]`/`pyrightconfig.json`, `none` when neither is configured (a
confirmed absence, not an open question); test `pytest` when the project has it (a
`[tool.pytest.ini_options]` table, a `pytest.ini`, or pytest in the dependencies),
`python -m unittest discover` for a `unittest`-only project, `none` when neither; lint `ruff check .` / `flake8` plus `black --check .` where configured. Every command is
prefixed with the project's runner when it has one (`poetry run`, `uv run`, `pdm run`, `pipenv
run`) — a bare `pytest` resolves against whatever interpreter is active. Format matrix rows,
extensions `py,pyi`, from the package that holds the config: `ruff check --force-exclude --fix
{file}` for a `[tool.ruff]`/`ruff.toml`/`.ruff.toml`; `ruff format --force-exclude {file}` only with an
explicit `[tool.ruff.format]`/`[format]` (lint config alone is not a formatting choice);
`black {file}` for a `[tool.black]`. Black ignores `exclude` for an explicit path, so a vendored
or generated directory gets no row rather than a row that reformats it.

## Packaging and the environment

The dependency manifest tells you which tool the project uses; use that one and no other:

- `[tool.poetry]` in `pyproject.toml` → Poetry (`poetry run …`, `poetry add`).
- `uv.lock`, or `[tool.uv]` → uv (`uv run …`, `uv add`).
- `[tool.pdm]`/`pdm.lock` → PDM.
- `Pipfile`/`Pipfile.lock` → Pipenv (`pipenv run …`, `pipenv install`).
- `requirements*.txt` with no `pyproject.toml` → pip against the project's venv.

Never add a dependency by editing the lockfile, and never install into the system interpreter.
When a command fails with `ModuleNotFoundError` for a package the manifest lists, that is an
**environment** problem (the venv is not active or not synced), not a code error — report it as
such rather than adding the import path by hand.

## Build

Python has no compile step, so the crew-config **backend build command** is whatever the project
uses as its static gate — typically a type checker (`mypy`, `pyright`) and often an import or
collection check beside it. Watch/dev/serve forms that never terminate: `uvicorn … --reload`,
`flask run`, `python manage.py runserver`, `watchmedo`, `pytest-watch`.

What weakens the gate: `--ignore-missing-imports`, `--no-strict-optional`,
`--follow-imports=skip`, or a narrowed path list — those settings belong to
`pyproject.toml`/`setup.cfg`, not to the invocation. Several Python tools report findings and
still exit 0 depending on configuration, and `mypy` reports per-file when handed paths instead of
the project, so read the summary line.

## Lint

`ruff check`, `flake8`, `black --check`, and `isort --check-only` are report/verify mode; the
`--fix`/write forms are not a gate. Use the configured verify command.
