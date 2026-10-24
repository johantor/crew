---
name: tests-xunit
description: .NET backend test conventions — xUnit test authoring and running, integration tests for the .NET layer. Load when the resolved backend stack is dotnet.
---

# Backend tests: xUnit (.NET)

Write and run backend tests using xUnit conventions and the repository's backend test command
from crew config (e.g. `dotnet test`). Integration tests exercise the .NET layer end to end
where the project has them.

## Running

If your dispatch hands you an artifacts path, add `--artifacts-path <path>` to every `dotnet test`
run: the build and lint gates may be running beside you on their own paths (`backend-dotnet`,
"Parallel gates").

- **Targeted rerun:** `--filter`. Every filter is `<property><op><value>`, so the property is
  never left off: `dotnet test --filter "FullyQualifiedName~Namespace.ClassName"` for a class,
  `--filter "FullyQualifiedName~Namespace.ClassName.MethodName"` for one test.
- **Discovery:** `dotnet test --list-tests --filter "FullyQualifiedName~Namespace.ClassName"`
  prints the tests the runner sees in that class. When it lists nothing, rerun `--list-tests`
  without the filter: if the rest of the project's tests appear, the value is misspelled or the
  namespace differs from the folder. When the unfiltered list is empty too, the cause is in the
  project file: the test project is missing `Microsoft.NET.Test.Sdk` or
  `xunit.runner.visualstudio`, is not in the solution, or has a stale build. Read the
  `.csproj`/`.sln`; never run `strings`, `ildasm` or the like over `bin/`.
- **Summary line:** `Total tests: 0` is the zero-tests failure.
- **Skip mechanism:** `Skip = "…"` on the attribute.
