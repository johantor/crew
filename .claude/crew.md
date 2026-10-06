---
frontendMode: unset
backendStack: shell
backendSkill: unset
frontendStack: none
frontendE2eTool: unset
frontendUnitTestTool: unset
backendLanePaths: unset
frontendLanePaths: unset
backendTestCommand: none
frontendTestCommand: none
backendBuildCommand: none
frontendBuildCommand: none
backendLintCommand: none
frontendLintCommand: none
formatMatrix: none
baseBranch: main
branchNaming: unset
runUrl: none
planDirectory: unset
---

This repository *is* the plugins — it holds no application code, so every build, test, and lint
slot is `none` and the matching `/crew:review` gates skip rather than fail. `formatMatrix` is
`none` too: shell is the only language here and shfmt belongs to the gate. What CI runs here is
in the root [AGENTS.md](../AGENTS.md), *Validating changes*: the validator, the changelog gate,
the hook tests, and shellcheck.

`backendStack` is `shell` and `frontendStack` is `none`: the hooks and scripts are the
deliverable, and there is no view. Mode and lane-path slots stay `unset` because nothing needs
them. `baseBranch` is `main`; `branchNaming` stays `unset`, so `lead` asks once per run.

`planDirectory` is `unset`, so plans land in the `.claude/` fallback, which this repo does not
track.
