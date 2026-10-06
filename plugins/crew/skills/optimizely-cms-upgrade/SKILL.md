---
name: optimizely-cms-upgrade
description: Upgrade an Optimizely CMS 12 site to CMS 13 — the breaking changes, the removed features, and the ordered steps. Load with `optimizely-cms12` when a 12 project is to be upgraded, or with `optimizely-cms13` mid-upgrade.
---

# Optimizely CMS 12 → 13 upgrade

There is no upgrade assistant for 12 → 13. Plan it as several reviewable steps (prep on 12,
package bump, API fixes, Graph, search migration), never one large diff. The target state is
described in `optimizely-cms13`.

## Breaking changes to find

- **Platform:** .NET 10; Newtonsoft.Json → `System.Text.Json`; Castle.Windsor removed; nullable
  annotations added. A custom JSON converter or a `JObject` in content code breaks.
- **Removed:** Dynamic Properties (`EPiServer.Core.DynamicProperty*`), mirroring, the legacy
  `EPiServer.PlugIn` system, and Search & Navigation (`EPiServer.Find*`).
- **Renamed or narrowed:**

  | CMS 12 | CMS 13 |
  |---|---|
  | `ISiteDefinitionResolver`, `ISiteDefinitionRepository` | `IApplicationResolver`, `IApplicationRepository` (`EPiServer.Applications`) |
  | `SiteDefinition.Current.StartPage` | `IApplicationResolver.GetByContext()?.EntryPoint` |
  | `SiteDefinition.Current.RootPage` | `ContentReference.RootPage` |
  | `PageReference`, `.PageLink` | `ContentReference`, `.ContentLink` |
  | `ContentArea.FilteredItems` | `ContentArea.Items` (or `IContentAreaItemsRenderingFilter`) |
  | `IContentAreaLoader.Get()` | `IContentAreaLoader.LoadContent()` |
  | `PageTypeRepository`, `BlockTypeRepository`, `IContentTypeRepository<ContentType>` | `IContentTypeRepository` |
  | `[ScheduledPlugIn]` (`EPiServer.PlugIn`) | `[ScheduledJob]` (`EPiServer.Scheduler`); the class must inherit `ScheduledJobBase` |
  | `PrincipalInfo.IsPermitted()` | `PermissionService.IsPermitted()` |
  | `IContentRouteEvents.CreatingVirtualPath` / `.RoutedContent` | `IContentUrlGeneratorEvents.GeneratingUrl` / `IContentUrlResolverEvents.ResolvedUrl` |
  | `EPiServer.CacheManager` | `ISynchronizedObjectInstanceCache` |
  | `ServiceLocator`, `Locate.Advanced`, `.Instance` singletons | constructor injection |

- **Extracted packages** now need an explicit `PackageReference`: `EPiServer.CMS.UI.AspNetIdentity`,
  `EPiServer.CMS.UI.VisitorGroups` (call `AddVisitorGroupsMvc()` and `AddVisitorGroupsUI()`),
  `EPiServer.Blobs`, `EPiServer.Cache`, `EPiServer.Geolocation`,
  `EPiServer.Events.ChangeNotification`.
- **Scheduled jobs:** an unset `InitialTime` now gets a random start time, and the
  `IntervalLength` default is 1; check every job's schedule after the upgrade.

- **Changed behavior:** validation, `SaveAction`, versioning, `ContentProvider`, `XhtmlString`,
  `UriSupport`, routing and URL segments. Read each against the breaking-changes page before
  you touch custom code in that area.
- **Names:** content type, property and tab names are validated; tab names must be
  alphanumeric.

## Steps

1. **Prep on 12.** Build once with `-warnaserror` (or a temporary
   `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`) and clear every `[Obsolete]` warning;
   remove the temporary setting before step 3. List third-party packages and confirm each has a 13 release; this is
   usually the largest part of the work.
2. **Search** for the removed features above and plan a replacement for each. Search &
   Navigation moves to Optimizely Graph (Optimizely's *Overview of migrating from Search &
   Navigation* guide). Load `optimizely-search-navigation` for the steps and the API mapping.
3. **Bump.** Set `net10.0` and move the CMS package family (`EPiServer.CMS*`,
   `EPiServer.Framework*`, the extracted packages above, and `Optimizely.Graph.Cms` /
   `EPiServer.Cms.UI.ContentManager`, which ship as `13.*`) to 13 together. Add-on packages
   (`EPiServer.CloudPlatform.Cms`, Commerce, third-party) have their own version lines: move
   each to its release that supports CMS 13, never to a guessed `13.*`.
   Then `dotnet restore`.
4. **Startup.** Fix the registrations (`AddCms()`, identity, visitor groups), then add
   `AddContentGraph()` before `AddContentManager()`. On SQL Server set
   `DataAccessOptions.UpdateDatabaseCompatibilityLevel = true`.
5. **Build and fix** the API renames. New `[Obsolete]` warnings from 13 can wait for a later
   step; a project that keeps warnings-as-errors on fixes them here instead.
6. **Database.** Back up first. The schema migration runs on first start; SQL error 1913 means
   a conflicting custom index to drop.
7. **Admin.** Check *Settings > Applications* (start page, host names), the content type list
   and *Scheduled Jobs*. Update bookmarks to the new admin URL.
8. **DAM.** Do not migrate assets until Optimizely ships the migration tool.

## Verify

- The site starts, `/` returns 200, and editors can open and publish a page.
- Graph sync finishes and the front end's queries return content; the schema moved to a
  unified `_Content`/`_Page`/`_Component` model, so headless queries written for 12 need
  rework.
- Every scheduled job runs once by hand.

## Sources

https://docs.optimizely.com/cms-13/docs/breaking-changes-in-cms-13,
https://docs.optimizely.com/cms-13/docs/api-replacement-map and
https://docs.optimizely.com/cms-13/docs/upgrade-to-cms-13; all are updated per release.
