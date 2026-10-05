---
name: optimizely-cms13
description: Optimizely CMS 13 (.NET 10, PaaS) conventions — content types, Visual Builder experiences/sections/elements, IContentLoader/IContentRepository, applications, Graph delivery, rendering, scheduled jobs, caching, DXP deploys. Load when a project references `EPiServer.CMS*` 13.x. For an upgrade from 12, load `optimizely-cms-upgrade` too.
---

# Optimizely CMS 13

CMS 13 is the current .NET release of Optimizely CMS. It runs on .NET 10, self-hosted or on DXP
(Optimizely's PaaS). Optimizely Graph is its delivery and search layer, and Visual Builder is
the default editing experience.

## Detect

- A `PackageReference` to `EPiServer.CMS*` at `13.*`, and `<TargetFramework>net10.0</TargetFramework>`.
  The CMS package version, not the name, separates 13 from 12. Other `Optimizely.*` packages
  version on their own, so their version says nothing about the CMS.
- `Optimizely.Graph.Cms` and `EPiServer.Cms.UI.ContentManager` with `AddContentGraph()` /
  `AddContentManager()` in startup.
- Admin URL: `/ui/CMS` on DXP with Opti ID, `/Optimizely/CMS` when self-hosted.
- Graph queries, sync and keys: load `optimizely-graph`.
- Neighbour with no crew skill yet: `EPiServer.Commerce` (Customized Commerce); use its docs.
  `EPiServer.Find*` here is a leftover from 12: Search & Navigation is not supported on 13
  (`optimizely-cms-upgrade`; `optimizely-search-navigation` for the move to Graph).

## Startup

- `services.AddCms()` (plus identity and visitor groups as the site needs), then
  `services.AddContentGraph()` **before** `services.AddContentManager()`; the other order fails
  at startup.
- **Applications** replace site definitions: resolve the current one with
  `IApplicationResolver` (`EPiServer.Applications`), and use `ContentReference.RootPage` for the
  root. Host names and start pages live in admin *Settings > Applications*, not code.
- Constructor injection only. `ServiceLocator` and `Locate.Advanced` do not belong in 13 code.

## Content model

- A content type is a class: `PageData`, `BlockData`, or `MediaData`, decorated with
  `[ContentType(DisplayName = "...", GUID = "...", GroupName = "...")]`. **The GUID is the
  identity**: set it on every type, never change or reuse it.
- Properties are `public virtual` auto-properties with `[Display(Name, GroupName, Order)]`,
  `[CultureSpecific]`, `[Required]`, `[AllowedTypes(typeof(...))]` and `[UIHint]` as needed.
- Names are validated: type, property and tab names must be valid identifiers, and tab names
  alphanumeric only.
- Renaming a type or property needs a `MigrationStep` (`UsedToBeNamed(...)`), or its stored
  values are dropped.
- Use `ContentReference` and `.ContentLink`; the `PageReference`/`.PageLink` variants are gone.
  `ContentArea.Items` replaces `FilteredItems`.
- JSON is `System.Text.Json`. Do not put `JObject`/Newtonsoft types in content code.

## Visual Builder

- An **Experience** type extends the page type: editors compose it from sections. A
  **Section** is a horizontal slice in a row/column grid; an **Element** is the smallest
  building block (a heading, an image, a card).
- A block type becomes available in Visual Builder through its composition behavior: *Section*
  (usable in the experience outline) or *Element* (usable inside a section grid).
- Model sections and elements as self-contained and reusable. Do not build page-specific
  fragments or layout fields that Visual Builder already gives editors.
- **Content variations** hold A/B and personalization variants as deltas with their own version
  history. Do not add a custom variant property for the same need.

## Reading and writing content

- Read with `IContentLoader` (`Get<T>`, `TryGet<T>`, `GetChildren<T>`, `GetItems`): cached,
  read-only instances.
- Write with `IContentRepository`: `CreateWritableClone()`, then `Save(...)` with a `SaveAction`.
  `AccessLevel.NoAccess` only in trusted back-end code.
- Filter what a visitor sees (`FilterForVisitor`, or `FilterPublished` + `FilterAccess`).
- For headless or cross-site delivery, query Optimizely Graph or the CMS REST API (on by
  default) instead of exposing `IContentLoader` through custom endpoints.

## Rendering

- Server-side ASP.NET MVC rendering is still supported: `PageController<T>`,
  `BlockComponent<T>`, and `@Html.PropertyFor` / the `epi-property` tag helper, so editing
  works.
- `XhtmlString` is editor HTML: render it through `PropertyFor`, never `Html.Raw` on visitor
  input.
- A headless front end reads from Graph through the frontend stack skill. The Graph schema is
  unified: `_Content`, `_Page`, `_Component`, `_Media`, with metadata under `_metadata`.

## Background work

- Scheduled job: a `ScheduledJobBase` subclass with `[ScheduledJob(DisplayName = "...",
  GUID = "...")]`, both from `EPiServer.Scheduler`. `ScheduledPlugIn` and the
  `EPiServer.PlugIn` namespace are gone, and a job must inherit `ScheduledJobBase` (custom
  methods are not supported). An unset `InitialTime` gets a random start time, so set it when
  the time matters. Jobs run in the site's process and in an anonymous context.
- Init: register in startup. Event wiring that needs the CMS started goes in an initializable
  module; keep its teardown symmetric.

## Caching

- `IContentLoader` already caches. Cache derived data in `ISynchronizedObjectInstanceCache`
  with a dependency on the content's master key, so a publish evicts it on every instance.
- Never cache per-visitor or per-variation output in a shared cache.

## Security

- Keep edit and admin UI behind the CMS roles (Opti ID groups on DXP); never widen access in a
  controller.
- Graph and REST API keys, and DXP connection strings, come from configuration or DXP app
  settings, never a committed `appsettings.json`. A Graph *single key* is public; the secret
  and app key are not.

## Testing

- Unit-test controllers and services by mocking `IContentLoader`/`IContentRepository` and
  building content with `new T()`.
- Add a startup smoke test (the site starts and `/` returns 200): the registration order and
  the schema migration fail only at startup.

## Deploy and verify (DXP)

- Integration → Preproduction → Production, promoted with the EpiCloud PowerShell module or the
  DXP portal. `services.AddCmsCloudPlatformSupport(configuration)` wires DXP blobs, events and
  logging.
- After a deploy, check the slot's log stream, *Scheduled Jobs*, and that Graph sync finished
  before completing the swap.

## Sources

Verify against https://docs.optimizely.com/cms-13/docs before you rely on version-specific
details; Visual Builder and Graph change between minor releases.
