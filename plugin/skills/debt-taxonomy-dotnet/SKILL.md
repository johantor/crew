---
name: debt-taxonomy-dotnet
description: .NET / C# suppression mechanisms, safe-removal recipes, NuGet package-manager variance, and upgrade-tier examples for crew's debt lane. Apply when stack detection (debt-taxonomy) finds a .NET project.
---

# Debt taxonomy — .NET / C#

Apply this skill when `debt-taxonomy` stack detection finds a .NET project (`*.csproj`,
`*.sln`, `Directory.Packages.props`, `global.json`). The rubric, the justified-suppression
filter, the blast-radius gate and the upgrade workflow are in the core skill; this skill supplies
the .NET rows they consume.

## Suppression mechanisms

One row per mechanism: its scope, where a keep-decision lives, what a grep-only pass reads as
"likely stale" (audit's `stale` scope never builds — `/crew:debt` proves a candidate with
`dotnet build` of the affected project), and how a worker removes it. .NET is the weaker stack
for justifications: only the `SuppressMessage` family has a native slot, so the rest rely on
project-level policy.

| Mechanism | Scope | Justification slot | Stale signal (grep-only) | Removal |
|---|---|---|---|---|
| `#pragma warning disable CS####` … `restore` | Block | **None native.** A trailing `// reason` on the `disable` line is the convention and is read as the justification; a bare `disable` is unjustified | The surrounded lines have no trigger for the diagnostic (a `CS8602` block over a line with no `.` member access; `CS0168` over a line with no declaration), or `restore` is missing or far from `disable` | Delete both the `disable` and the matching `restore` |
| `[SuppressMessage("category", "id", Justification = "…")]` | Member/type | The `Justification` param, e.g. `Justification = "validated by the ASP.NET model binder"` | The member has no construct that triggers the rule (`CA1062` on a member with no parameters). A meaningful `Justification` may still be class 1 — flag, don't assume | Delete the attribute |
| `GlobalSuppressions.cs` (`[assembly: SuppressMessage(...)]`) | Assembly | The same `Justification` param, per entry | The `Target` symbol no longer exists in source (`grep -rn --include="*.cs" "<symbol>" src/`) | Each entry is a separate finding; remove only the targeted entry |
| `<NoWarn>CS####;CS####</NoWarn>` in `.csproj` | Project | **None** — config, not a site; project policy | Out of `stale` scope: the ID lives in pragmas, not in the code the diagnostic fires on, so grep is inverted. Needs a build | Expand to **diagnostic count** before gating; remove only the target ID from the list, never the element |
| `<NoWarn>` in `Directory.Build.props` | Solution | **None** — project policy | Out of `stale` scope, as above | Tier 2 unless the diagnostic count is tiny |
| `.editorconfig` `dotnet_diagnostic.CS####.severity = none/silent` | Folder | **None** — project policy | Out of `stale` scope, as above | Count diagnostics under the folder, not this line; restore to `warning`/`error` |
| `[Fact(Skip="…")]`, `[Theory(Skip="…")]` | Test | N/A — never excluded (core: skipped tests) | Never a candidate | Class 4: the user decides |

## Analyzer / nullability notes

- **Nullable reference types** (`CS86xx`): the common debt cluster. A `#pragma warning disable CS8602` often hides a missing null-check — usually rubric class 2 (trivially fixable: add `?.`, null-guard, or `!` only where provably non-null).
- **Obsolete-API warnings** (`CS0618`): frequently caused by an old dependency — the fix may be an upgrade pointer, not a code edit. Flag the link.
- A suppression whose diagnostic no longer fires (`dotnet build` shows no warning at that line after removal) is class 2, stale — just delete it.

## Behavior sensitivity (which fixes need tests, not just a clean build)

Tag every finding before delegating (see core `debt-taxonomy`):

**Behavior-preserving** — `<NoWarn>` removal of a stale diagnostic, an `any`-equivalent cast tightening, unused-using/variable cleanup, a justification-only edit. "Compiles clean" is a sufficient gate.

**Behavior-sensitive** — adding a real **null-guard** for a `CS8602` fix changes control flow (an early return or default vs. a thrown `NullReferenceException`), so the *behavior under null* changes. Likewise re-enabling an analyzer that forces a logic change (e.g. `CA2007` ConfigureAwait, disposal fixes). Acceptance gate must be **tests-green**; with no test command configured, the orchestrator warns and requires acknowledgement.

## Package-manager variance (NuGet)

These are the concrete commands the core `debt-taxonomy` *Upgrade workflow* delegates here:

| Step | Command / location |
|---|---|
| Discover outdated | `dotnet list package --outdated` (add `--include-transitive` to see pulled-in deps); `dotnet-outdated` if installed |
| Version location | **Central Package Management** — if `Directory.Packages.props` exists, the version is the `<PackageVersion>` there, update in **one place**; otherwise it's the `<PackageReference Include="X" Version="Y" />` in **each** `.csproj` — update every occurrence |
| Apply | edit the version, then `dotnet restore` |
| Verify | `dotnet build <project>.csproj` — capture output to a file and grep for errors (`context-discipline`) |

- **Conflict signal:** transitive conflicts surface as `NU1605` (downgrade) / `NU1107` (version conflict) → report and stop; never silently add a binding redirect or downgrade pin.
- **Release-notes URL** (core workflow step 2 fallback when Context7 has nothing): the package's NuGet page `https://www.nuget.org/packages/<id>`, or its project/repo `/releases` page when the `.nuspec` `projectUrl` points at a Git host.

## Upgrade-tier examples (.NET)

| Upgrade | Tier | Notes |
|---|---|---|
| `Newtonsoft.Json 12 → 13` | 1 | Major, but API-stable for most uses; pull migration notes via Context7 |
| `EF Core 7 → 8` | 1 | Usually API-stable |
| `EF Core 6 → 7` | 2 if raw SQL / provider changes required | Otherwise 1 |
| **TFM bump** (`net6.0 → net8.0`) | **2 — outline only** | Changes the `<TargetFramework>`; ripples through analyzers, dependencies, runtime behavior |
| SDK major (`global.json` `sdk.version`) | 2 — outline only | Platform-scale |
| Optimizely CMS major | 2 — outline only | Content-model and API migration is a project |
