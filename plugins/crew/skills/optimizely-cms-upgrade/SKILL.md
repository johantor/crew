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
  | `ISiteDefinitionResolver` | `IApplicationResolver` (`EPiServer.Applications`) |
  | `SiteDefinition.Current.RootPage` | `ContentReference.RootPage` |
  | `PageReference`, `.PageLink` | `ContentReference`, `.ContentLink` |
  | `ContentArea.FilteredItems` | `ContentArea.Items` |
  | `IContentTypeRepository<ContentType>` | `IContentTypeRepository` |
  | `ServiceLocator`, `Locate.Advanced` | constructor injection |

- **Changed behavior:** validation, `SaveAction`, versioning, `ContentProvider`, `XhtmlString`,
  `UriSupport`, routing and URL segments. Read each against the breaking-changes page before
  you touch custom code in that area.
- **Names:** content type, property and tab names are validated; tab names must be
  alphanumeric.

## Steps

1. **Prep on 12.** Set `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` and clear every
   `[Obsolete]` warning. List third-party packages and confirm each has a 13 release; this is
   usually the largest part of the work.
2. **Search** for the removed features above and plan a replacement for each. Search &
   Navigation moves to Optimizely Graph (`optimizely-search-navigation`, *Migrate to Graph*).
3. **Bump.** Set `net10.0`, update every `EPiServer.*`/`Optimizely.*` package to `13.*`
   together, then `dotnet restore`.
4. **Startup.** Fix the registrations (`AddCms()`, identity, visitor groups), then add
   `AddContentGraph()` before `AddContentManager()`. On SQL Server set
   `DataAccessOptions.UpdateDatabaseCompatibilityLevel = true`.
5. **Build and fix** the API renames. Leave non-blocking `[Obsolete]` warnings for a later step.
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

https://docs.optimizely.com/cms-13/docs/breaking-changes-in-cms-13 and
https://docs.optimizely.com/cms-13/docs/upgrade-to-cms-13; both are updated per release.
