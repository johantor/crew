---
frontendMode: unset
backendStack: shell
backendSkill: unset
frontendStack: none
frontendSkill: unset
frontendE2eTool: unset
frontendUnitTestTool: unset
backendTestCommand: none
frontendTestCommand: none
backendBuildCommand: none
frontendBuildCommand: none
backendLintCommand: none
frontendLintCommand: none
formatMatrix: none
baseBranch: main
branchNaming: <type>/<issue>-<slug>
runUrl: none
planDirectory: unset
---

This repository *is* the plugin — it holds no application code, so every build, test, and lint
slot is `none` and the matching `/crew:review` gates skip rather than fail. `formatMatrix` is
`none` too: shell is the only language here and shfmt belongs to the gate. What CI runs here is
in the root [AGENTS.md](../AGENTS.md), *Validating changes*: the validator, the changelog gate,
the hook tests, and shellcheck.

`backendStack` is `shell` and `frontendStack` is `none`: the hooks and scripts are the
deliverable, and there is no view. The mode slot stays `unset` because nothing needs it. `baseBranch` is `main`; `branchNaming` is the convention in AGENTS.md.

`planDirectory` is `unset`, so plans land in the `.claude/` fallback, which this repo does not
track.
