---
name: backend-dotnet
description: .NET backend stack conventions — MVC controllers, Razor server-side ownership, dotnet build specifics. Load when the resolved backend stack is dotnet. If the project also uses Optimizely, also load the matching `optimizely-<product>` skill.
---

# Backend: .NET

You are working in a .NET backend: C#, ASP.NET MVC controllers, and the server-side of Razor
views. If the project uses Optimizely, load the `optimizely-<product>` skills whose markers it
carries:

- `optimizely-cms12` or `optimizely-cms13` by the `EPiServer.CMS*` version, plus
  `optimizely-cms-upgrade` when the task is moving 12 to 13;
- `optimizely-graph` for `Optimizely.Graph.*` or `Optimizely.ContentGraph.*`;
- `optimizely-search-navigation` for `EPiServer.Find*`;
- `optimizely-odp` for `Optimizely.Cms.Odp`, `UNRVLD.ODP.VisitorGroups` or
  `EPiServer.Commerce.ODP`;
- `optimizely-opal` and `optimizely-opal-tools-dotnet` for `Optimizely.Opal.Tools` (or the
  legacy `OptimizelyOpal.OpalToolsSDK`).

Each product skill names its own markers and neighbours.

## Crew config

`/crew:init` proposes from a `*.sln`/`*.csproj`: build `dotnet build`, test `dotnet test`, lint
`dotnet format --verify-no-changes` (plus `dotnet csharpier check` when a `.csharpierrc` or
`.csharpierrc.*` exists). Format matrix row, extensions `cs,csproj`: `dotnet csharpier format
{file}` when that config exists, else `dotnet format whitespace --include {file}` — full `dotnet format` evaluates
analyzers against the project and takes 10-60s, so it stays at the lint gate.

## Razor ownership (server-rendered mode)

Own the server-side of Razor (`.cshtml`): view-model binding, `@functions`/`@code`, control
flow over data, and data access. In server-rendered mode, frontend owns the *markup/DOM*
(structure, classes, ARIA, presentation) — coordinate the view-model contract with frontend
rather than reworking the markup yourself. In headless mode, Razor is entirely yours. Load
`frontend-razor` before you change a `.cshtml` file: it holds the view rules, the Optimizely
ones included.

## Build

The gate is the crew-config backend build command, e.g. `dotnet build`. Watch/run forms that
never terminate: `dotnet watch`, `dotnet run`.

### `obj/` is per-writer state, not a shared cache

MSBuild writes `project.assets.json`, `*.nuget.g.props`/`*.nuget.g.targets`,
`*.csproj.nuget.dgspec.json` and the per-configuration intermediates into `obj/`. Two processes
racing over those files can corrupt or truncate them — you get a restore that contradicts the
project file, or a nonsense compile error, rather than a clean lock error that names itself. And
`dotnet test`, `dotnet publish` and `dotnet format` all build, so each of them is a writer too.

- **Shareable across concurrent builds:** the NuGet package cache (`NUGET_PACKAGES`). It is
  read-mostly, and it is where the warm-cache benefit actually lives — point every build at one.
- **Never shared by concurrent builds:** `BaseIntermediateOutputPath` and `BaseOutputPath`
  (`obj/`, `bin/`). They are per-build-writer.

So if another crew build/test/lint run may be live against the same project, either wait for it or
use the path your dispatch gave you (below). Say which you did in your findings — lead knows
the dispatch and you do not.

### Parallel gates

Build, test and lint may run at once when each gets its own artifacts root, `<path>` from the
dispatch (`<location>/<lane>/<gate>`). The SDK then puts every project under
`<path>/bin/<Project>/` and `<path>/obj/<Project>/`, so projects in one solution do not collide
either, and nothing is written into the source tree. Reuse the same `<path>` per gate across the
session and the second run is incremental.

- Build: `dotnet build <sln> --artifacts-path <path>`
- Test: `dotnet test <sln> --artifacts-path <path>`
- Lint: `UseArtifactsOutput=true ArtifactsPath=<path> dotnet format <sln> --verify-no-changes`
  (`dotnet format` has no `--artifacts-path`; MSBuild reads the environment instead)

Use the recipe only when **all** of these hold; otherwise run the gates one at a time. Every
run under it passes `nocache` to the gate runner: a result the tree check may still discard is
never cached, and never answered from the cache.

- The SDK is 8.0 or newer.
- The **tree check** has passed this session and not failed since. A repo property
  (`UseArtifactsOutput=false`, `BaseIntermediateOutputPath`, `MSBuildProjectExtensionsPath`, …)
  can send outputs back into the tree, and no list of such properties is complete, so check the
  result on **every** run: touch a marker file first, and afterwards confirm that no file in the
  repo outside `.git` is newer than it. The session's first run is serial. A parallel run that
  fails the check proves nothing: discard its results, rerun the gates one at a time, stay serial
  for the rest of the session, and report the new files without deleting them (they may be the
  developer's).
- Each configured gate command is exactly `dotnet build`, `dotnet test` or
  `dotnet format --verify-no-changes`, optionally followed by one solution or project path, and
  nothing else. Any other flag (`--no-build`, `--no-restore`, `-c Release`, …) or a wrapper script
  means serial. The list is closed on purpose: a flag it does not name is never judged safe.

### The lock signature

A file-lock/in-use error is `MSB3027`/`MSB3026`, "being used by another process", or corrupted or
truncated `obj/` state. It has two possible causes: a running app/dev process holding the outputs,
**or** two crew builds sharing `obj/`. Report the failure, the path it names, and whether you had
the intermediate path to yourself — and don't assert the user's dev server is at fault when you
were building against a location you were not given exclusively.

### What weakens the gate

- **A narrowed target.** `-t:CoreCompile` — or any `-t:`/`/t:` (`--target:` under `dotnet
  msbuild`) other than the default — skips the analyzer-bearing part of the build, so it
  reports 0 warnings while analyzers fire.
- **Relaxed analysis.** `-p:EnforceCodeStyleInBuild=false`, `-p:RunAnalyzers=false`,
  `-p:TreatWarningsAsErrors=false`, or any other property that loosens what the project sets.
  Analyzer and code-style settings belong to the project, not to the build invocation.
- **`--no-restore`.** It reuses whatever restore assets are already on disk (and fails
  outright when there are none), so a stale `project.assets.json` builds against a different
  analyzer set than the developer's own build resolves. Let the gate restore.
- **Verbosity below the default.** `dotnet build`'s default (`minimal`) prints warnings;
  `-v q`/`--verbosity quiet` hides them.
- **A no-op build.** MSBuild does not re-emit warnings for projects it finds up to date, so
  rebuilding an unchanged tree can print 0 warnings a real compile would print. If the output
  shows nothing compiled, report that — not a clean build.

`dotnet build` exits 0 with warnings present. Report every warning — compiler (`CSxxxx`),
analyzer, and code-style (`IDExxxx`) — and report zero warnings only when the build printed none.
