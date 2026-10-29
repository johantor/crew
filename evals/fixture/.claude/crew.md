---
frontendMode: server-rendered
backendStack: dotnet
backendSkill: unset
frontendStack: other
frontendSkill: none
frontendE2eTool: none
frontendUnitTestTool: unset
backendTestCommand: dotnet test
frontendTestCommand: none
backendBuildCommand: dotnet build
frontendBuildCommand: none
backendLintCommand: dotnet format --verify-no-changes
frontendLintCommand: none
formatMatrix: |
  . cs,csproj dotnet format whitespace --include {file}
baseBranch: main
branchNaming: feature/<slug>
runUrl: http://localhost:5000/
planDirectory: unset
---

An Optimizely CMS 13 site with Razor views and no client bundle, so the frontend is
`server-rendered` with stack `other`: the mode skill and `frontend-razor` cover the views.
The site needs the database from `docker-compose.yml` to run; the build, test and lint gates
do not.
