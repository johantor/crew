---
name: optimizely-cms12
description: Optimizely CMS 12 (PaaS, ASP.NET Core) conventions — content types, blocks, IContentLoader/IContentRepository, rendering, scheduled jobs, init modules, caching, DXP deploys. Load when a project references `EPiServer.CMS*` 12.x. For 13.x load `optimizely-cms13`; for an upgrade from 12 to 13 load `optimizely-cms-upgrade`.
---

# Optimizely CMS 12

CMS 12 is the ASP.NET Core release of Optimizely (formerly Episerver) CMS. It runs self-hosted
or on DXP (Optimizely's PaaS). It is in maintenance: new work targets CMS 13, so flag a pattern
that blocks the upgrade (`optimizely-cms-upgrade` lists them).

## Detect

- A `PackageReference` to `EPiServer.CMS` (or `EPiServer.CMS.Core`, `EPiServer.CMS.UI`) at
  `12.*`. The version, not the package name, separates 12 from 13.
- `services.AddCms()` in `Startup.cs`/`Program.cs`, an `"EPiServer"` section in
  `appsettings.json`, an `EPiServerDB` connection string.
- `EPiServer.CloudPlatform.Cms` means the site deploys to DXP.
- `Optimizely.ContentGraph.Cms` means the site syncs to Optimizely Graph: load `optimizely-graph`.
- `EPiServer.Find*` means Search & Navigation: load `optimizely-search-navigation`.
- `Optimizely.Cms.Odp` or `UNRVLD.ODP.VisitorGroups` means ODP audiences: load `optimizely-odp`.
- Neighbour with no crew skill yet: `EPiServer.Commerce` (Customized Commerce). Work from its
  docs.

## Content model

- A content type is a class: `PageData`, `BlockData`, or `MediaData` (with
  `[MediaDescriptor(ExtensionString = "jpg,png")]`), decorated with
  `[ContentType(DisplayName = "...", GUID = "...", GroupName = "...")]`.
- **The GUID is the identity.** Never change or reuse it; renaming the class keeps the data
  only because the GUID stays. Set it on every new type.
- Properties are `public virtual` auto-properties. Use `[Display(Name, GroupName, Order)]`,
  `[CultureSpecific]` for translated fields, `[Required]`, `[AllowedTypes(typeof(...))]` on a
  `ContentArea` or `ContentReference`, and `[UIHint]` for editor choice.
- Renaming a property or a type without a migration drops its stored values. Add a
  `MigrationStep` that calls `ContentType("NewName").UsedToBeNamed("OldName")` or
  `.Property("NewProp").UsedToBeNamed("OldProp")` in its `AddChanges()`.
- Shared fields go in a base class or an interface, not copied across types. Keep page types
  few; blocks carry reusable parts.
- Use `ContentReference`, not `PageReference`, in new code (13 removes the page variants).

## Reading and writing content

- Read with `IContentLoader` (`Get<T>`, `TryGet<T>`, `GetChildren<T>`, `GetItems`). It is cached
  and returns **read-only** instances.
- Write with `IContentRepository`: `CreateWritableClone()` first, then
  `Save(content, SaveAction.Publish, AccessLevel.NoAccess)` only in trusted back-end code. Use
  `SaveAction.Default`/`CheckIn` when an editor must review.
- Inject services through the constructor. `ServiceLocator.Current` and `Locate.Advanced` are
  legacy; 13 pushes them out.
- Filter what a visitor sees: `FilterForVisitor` (or `FilterPublished` + `FilterAccess`) on any
  list you render. `GetChildren` alone returns unpublished and restricted content.
- Content events (`IContentEvents.PublishingContent` and similar) run inside the editor's
  request; keep handlers fast and never throw for flow control.

## Rendering

- Pages: `PageController<T>` with an `Index(T currentPage)` action, or a view found by
  convention. Blocks: `BlockComponent<T>` (a view component) or a partial view.
- Views render every property through `@Html.PropertyFor` or the `epi-property` tag helper, so
  on-page edit works; `XhtmlString` never through `Html.Raw`. The view rules (ContentArea,
  display options, client resources, edit mode) are in `frontend-razor`.

## Background work

- Scheduled job: a `ScheduledJobBase` subclass with
  `[ScheduledPlugIn(DisplayName = "...", GUID = "...")]`. Return a status string from
  `Execute()`, report progress with `OnStatusChanged`, honor `Stop()` when `IsStoppable`.
  Jobs run without an HTTP context and as an anonymous user unless the job sets one.
- Init: prefer `IServiceCollection` registration in `Startup`. An `[InitializableModule]` with
  `[ModuleDependency(typeof(EPiServer.Web.InitializationModule))]` is for event wiring that needs
  the CMS started; keep `Uninitialize` symmetric.

## Caching

- `IContentLoader` already caches content. Cache derived data with
  `ISynchronizedObjectInstanceCache` and a dependency on the content's master key
  (`IContentCacheKeyCreator.CreateCommonCacheKey`), so publishing evicts it on every instance.
- Never cache per-visitor data (visitor groups, personalized content areas) in a shared cache.

## Security

- Admin and edit UI live under `/EPiServer` by default. Keep them behind the CMS roles
  (`WebAdmins`, `WebEditors`, `CmsAdmins`); never widen access in a controller.
- `AccessLevel.NoAccess` skips access checks. Use it only in jobs and import code, never with
  input from a request.
- Secrets (DXP connection strings, Graph keys) come from configuration or DXP app settings,
  never `appsettings.json` in the repo.

## Testing

- Unit-test controllers and services by mocking `IContentLoader`/`IContentRepository`; build
  content instances with `new T()` and set properties directly.
- Do not unit-test the CMS itself. Content type changes are verified by starting the site and
  checking the admin *Content Types* view for warnings.

## Deploy and verify (DXP)

- Environments: Integration → Preproduction → Production. Code goes to Integration first;
  promote with the EpiCloud PowerShell module (`Start-EpiDeployment`,
  `Complete-EpiDeployment`) or the DXP portal.
- Register `services.AddCmsCloudPlatformSupport(configuration)` (from
  `EPiServer.CloudPlatform.Cms`) for DXP; it wires blobs, events and logging.
- After a deploy, check the slot's log stream and the admin *Scheduled Jobs* list before
  completing the swap.

## Sources

Verify version-specific details against https://docs.optimizely.com/cms-12/docs before you rely
on them.
