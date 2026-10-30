# EvalSite

An Optimizely CMS 13 site: `src/EvalSite` is the site, `tests/EvalSite.Tests` its xUnit tests.

## Crew orchestration

Development in this repo is orchestrated: `lead` plans the work and delegates each step to a
worker subagent (`backend`, `frontend`, `unit-tests`, `e2e`, `visual-review`, `generalist`, `incident-triage`, `debt-scout`,
`analyst`, `architect`, `designer`, `copywriter`, `security-review`, `web-review`). Dispatching a
worker is ordinary in-repo development — the worker reads files in this working tree, an
implementer edits them (`visual-review`, `incident-triage`, `debt-scout`, `analyst`, `architect`,
`security-review` and `web-review` carry no edit tool), and each returns
a summary. It is not remote execution, and it sends nothing outside the repository.

The crew's guard hooks bound what a worker can do: only `lead` touches git, no agent commits on
the base branch, no agent writes inside `.git/`, `lead` checks each worker's changed files
against its plan step, file-mutating Bash is refused so a write cannot skip the Edit/Write hooks,
and destructive shell commands are refused. Nothing is pushed and no pull request is opened on its own — `/crew:pr` is the only
path out of the machine, and the user invokes it.
