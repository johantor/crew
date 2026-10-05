---
frontendMode: unset
backendStack: unset
frontendStack: unset
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
baseBranch: unset
branchNaming: unset
runUrl: none
planDirectory: unset
---

This repository *is* the plugins — it holds no application code, so every build, test, and lint
slot is `none` and the matching `/crew:review` gates skip rather than fail. `formatMatrix` is
`none` too: shell is the only language here and shfmt belongs to the gate. What CI runs here is
in the root [AGENTS.md](../AGENTS.md), *Validating changes*: the validator, the changelog gate,
the hook tests, and shellcheck.

The stack, mode, and lane-path slots stay `unset` because there is no app stack to resolve; a
task that genuinely needs one lets `morpheus` resolve it per run, as in any project. `baseBranch`
and `branchNaming` stay `unset` for the same reason they always were — `morpheus` resolves them
per session and remembers.

`planDirectory` is `unset`, so plans land in the `.claude/` fallback, which this repo does not
track.
