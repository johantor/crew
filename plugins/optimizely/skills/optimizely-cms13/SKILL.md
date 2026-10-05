---
name: optimizely-cms13
description: Optimizely CMS 13 (.NET 10) — what changed from CMS 12 (applications, Graph built in, Visual Builder, content variations, removed APIs) and how to upgrade a 12 site. Load with `optimizely-cms12` when a project references `EPiServer.CMS*` 13.x, or when asked to upgrade from 12.
---

# Optimizely CMS 13

CMS 13 is the current .NET release. The content model, rendering, job and caching rules in
`optimizely-cms12` still hold; this skill lists only what is different. Where the two disagree,
this one wins on a 13 project.

## Detect

- `EPiServer.CMS*`/`Optimizely.*` package references at `13.*`, and `<TargetFramework>net10.0`.
- `Optimizely.Graph.Cms` and `EPiServer.Cms.UI.ContentManager` are the usual 13 companions.
- Admin URL: `/ui/CMS` on DXP with Opti ID, `/Optimizely/CMS` when self-hosted.

## What changed

- **Applications replace site definitions.** `ISiteDefinitionResolver` →
  `IApplicationResolver` (`EPiServer.Applications`); `SiteDefinition.Current.RootPage` →
  `ContentReference.RootPage`. Host names and start pages live in *Settings > Applications*.
- **Graph is the delivery and search layer.** Register `services.AddContentGraph()` **before**
  `services.AddContentManager()`, or startup fails. Query patterns: `optimizely-graph`.
- **Search & Navigation is not supported.** Code on `EPiServer.Find*` must move to Graph
  (`optimizely-search-navigation`, *Migrate to Graph*).
- **Visual Builder** is the default editing experience; it replaces on-page editing. Experiences
  and sections let editors compose layouts, so model blocks as self-contained sections rather
  than page-specific fragments.
- **Content variations** store A/B and personalization variants as deltas with their own
  version history. Do not build a custom variant property for the same need.
- **Removed:** Dynamic Properties, mirroring, and the legacy `EPiServer.PlugIn` system.
- **Renamed or narrowed APIs:** `PageReference` → `ContentReference`; `.PageLink` →
  `.ContentLink`; `ContentArea.FilteredItems` → `ContentArea.Items`;
  `IContentTypeRepository<ContentType>` → `IContentTypeRepository`. `UriSupport` and parts of
  routing and URL segments changed too.
- **Platform:** Newtonsoft.Json → `System.Text.Json`; Castle.Windsor removed; nullable
  annotations added. A custom converter or a `JObject` in content code breaks.
- **Validation:** content type, property and tab names are validated; tab names must be
  alphanumeric. The validation, `SaveAction` and versioning APIs changed; re-read any custom
  validator against the breaking-changes page.
- **Service location:** constructor injection only in new code; `ServiceLocator` and
  `Locate.Advanced` are the first thing to remove during an upgrade.
- Built in: the CMS REST API (on by default), DAM integration, and Opal (`optimizely-opal`).

## Upgrade from 12

1. Before you touch packages, on 12: set `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`
   and clear every `[Obsolete]` warning. List third-party packages and confirm each has a 13
   release; this is usually the largest part of the work.
2. Search for removed features: `EPiServer.Core.DynamicProperty*`, `EPiServer.PlugIn`,
   mirroring types, `EPiServer.Find`.
3. Set `net10.0`, update every `EPiServer.*`/`Optimizely.*` package to `13.*` together, then
   `dotnet restore`.
4. Fix the registrations (`AddCms()`, identity, visitor groups), add `AddContentGraph()` then
   `AddContentManager()`. On SQL Server, set `DataAccessOptions.UpdateDatabaseCompatibilityLevel
   = true`.
5. Build, then fix the API renames above. Leave non-blocking `[Obsolete]` warnings for a
   follow-up step.
6. Back up the database. The schema migration runs on first start; SQL error 1913 means a
   conflicting custom index to drop first.
7. In admin, check *Settings > Applications* (start page, host names) and the content type list.
8. Do not migrate DAM assets until Optimizely ships the migration tool. There is no upgrade
   assistant for 12 → 13.

Plan an upgrade as several reviewable steps (prep on 12, package bump, API fixes, Graph, search
migration), not one large diff.

## Testing

- Same unit-test approach as 12. Add a startup smoke test (the site starts and `/` returns
  200), because the registration order and the migration fail only at startup.

## Sources

Verify against https://docs.optimizely.com/cms-13/docs, especially
*Breaking changes in CMS 13* and *Upgrade to CMS 13*; both are updated per release.
