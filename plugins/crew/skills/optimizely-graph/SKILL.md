---
name: optimizely-graph
description: Optimizely Graph (GraphQL delivery and search for Optimizely CMS) conventions — sync from CMS 12 and 13, the per-type and unified `_Content` schemas, keys and auth, querying from .NET and from a headless front end, preview, caching, search and facets, verifying sync. Load when a project references `Optimizely.Graph.*` or `Optimizely.ContentGraph.*`, `@optimizely/cms-sdk`, or queries `cg.optimizely.com`.
---

# Optimizely Graph

Optimizely Graph is a hosted GraphQL service. The CMS pushes content to it, and sites, front
ends and other services read and search it there. It is mandatory on CMS 13 and an add-on on
CMS 12. The content model that feeds it belongs to `optimizely-cms12`, `optimizely-cms13` or
`optimizely-cms-saas`.

## Detect

- **CMS 13:** `Optimizely.Graph.Cms` (sync) and `Optimizely.Graph.Cms.Query` (the C# query SDK).
- **CMS 12:** `Optimizely.ContentGraph.Cms` (sync, with `EPiServer.ContentDeliveryApi.Cms`) and
  `Optimizely.Graph.Client` (the C# query client, now deprecated).
- These packages are on the Optimizely NuGet feed (`nuget.optimizely.com`), not nuget.org; a
  restore without that source fails.
- **Front end:** `@optimizely/cms-sdk` (official), `@remkoj/optimizely-graph-client`
  (community), or a GraphQL client pointed at `https://cg.optimizely.com/content/v2`.
- Config: `Optimizely:ContentGraph` on CMS 12, `Optimizely:Graph` on CMS 13 (`GatewayAddress`,
  `AppKey`, `Secret`, `SingleKey`). On DXP the platform sets it; the section is for local runs.

## Startup and sync

- **CMS 13:** `services.AddContentGraph()` **before** `services.AddContentManager()`.
- **CMS 12:** `services.AddContentDeliveryApi()` **before** `services.AddContentGraph()`.
  Options go in `AddContentGraph(options => ...)` or the config section.
- Sync is event-driven: a publish, update or delete reaches Graph in seconds. Scheduled jobs
  cover the rest: a full sync (types and content) and, on CMS 12, a delta sync.
- `ContentVersionSyncMode` decides what is sent: `DraftAndPublishedOnly` (default),
  `PublishedOnly`, or `All`. Keep drafts out unless the site needs preview.
- A content type change changes the schema. Run the full sync and allow 5–10 minutes before
  queries see the new fields.
- Keep content that must not leave the CMS out of Graph with the `Include` allowlist (by
  content type or content ID), not with a front-end filter.
- An item over about 1 MB times out on sync; split it.

## Schema

- **CMS 12** is per content type: one root query per type (`ArticlePage(...)`) plus `Content`.
  Fields are the property names, plus `ContentLink { GuidValue }`, `Language { Name }`,
  `ContentType`, `RelativePath`, `Url`, `Status`. Linked content comes through `Expanded`.
- **CMS 13** is unified: `_Content`, `_Page`, `_Experience`, `_Component`, `_Section`,
  `_Media`, `_Image`, `_Video`, `_Folder`, with system fields under `_metadata` (`key`,
  `locale`, `types`, `displayName`, `status`, `published`, `lastModified`, `url { default
  hierarchical base }`). `Expanded` is gone: use fragments on the type. Site ID is gone: filter
  on `_metadata.url.base`.
- A query written for one schema does not run on the other. On an upgrade, rewrite each one
  (`optimizely-cms-upgrade`).

## Querying

- Root fields: `items`, `item`, `total`, `facets`, `cursor`, `autocomplete`. Use `item` for a
  single result; it caches better than `limit: 1`.
- `where` takes `eq`, `notEq`, `in`, `notIn`, `like`, `startsWith`, `endsWith`, `contains`,
  `match`, `exist`, `gt`, `gte`, `lt`, `lte`, combined with `_and`, `_or`, `_not`.
- Paging: `limit` defaults to 20, maximum 100; `skip` reaches only the top 10,000 hits. Past
  that, page with `cursor`. A cursor lives 10 minutes and does not mix with `skip`.
- Search: `where: { _fulltext: { match: "..." } }`, ranked by `RELEVANCE` (default) or
  `orderBy: { _ranking: SEMANTIC }`.
- Facets: default 10 values per facet, maximum 1,000. Ask only for the facets the page shows.
- Pass input as GraphQL variables, never by string concatenation into the query.

## Querying from .NET

- **CMS 13:** `services.AddGraphContentClient()`, then inject `IGraphContentClient`. Build with
  `QueryContent<T>()`, `.SearchFor(...)`, `.Where(x => ...)`, `.OrderBy(...)`, `.Skip()`/
  `.Limit()`, `.Facet(...)`, `.IncludeTotal()`, and run with `.GetAsync()` or
  `.GetAsContentAsync()`. `.ToGraphQL()` returns the query text. Search tracking (`.Track()`,
  with `.SearchFor()` only) needs `Optimizely.Graph.AspNetCore` and `app.UseGraphTrackingScripts()`.
- **CMS 12:** the CMS 13 SDK does not support 12. Existing code may use the deprecated
  `GraphQueryBuilder` (`Optimizely.Graph.Client`: `.ForType<T>().Fields(...).Where(...)
  .GetResultAsync<T>()`); keep it working, but do not add new uses. A query that must survive
  the upgrade to 13 is plain GraphQL, rewritten for the unified schema at that point.
- Search & Navigation (`EPiServer.Find*`) code maps to the CMS 13 SDK: `Search<T>` →
  `QueryContent<T>`, `For` → `SearchFor`, `Filter` → `Where`, `Take` → `Limit`, `GetResult()` →
  `await GetAsContentAsync()`, `TotalMatching` → `Total`. Inside the site, `IContentLoader` is
  still the way to read a known item.

## Headless front ends

- `@optimizely/cms-sdk`: `new GraphClient(singleKey, { graphUrl })`, `getContentByPath()`,
  `getPreviewContent()`. Configuration comes from `OPTIMIZELY_GRAPH_SINGLE_KEY` and
  `OPTIMIZELY_GRAPH_GATEWAY`.
- Generate types from the live schema (GraphQL Code Generator against the endpoint with the
  single key) rather than writing response types by hand; regenerate after a content type
  change.
- **Preview:** the CMS opens the preview URL with a `preview_token`. Query Graph with
  `Authorization: Bearer <token>`, server-side; the token lives 5 minutes. Load
  `/util/javascript/communicationinjector.js` from the CMS so on-page editing works, and refetch on
  its `optimizely:cms:contentSaved` event.
- Never cache a preview response, and never render a preview route statically.

## Caching and limits

- Graph sits behind a CDN. Cache hits do not count against the rate limit: 1,500 requests per
  10 seconds by default; above it Graph returns 429 with `Retry-After`. Honour it; do not retry
  in a tight loop.
- Stored (cached) templates: send `?stored=true` with the header `cg-stored-query: template`
  and pass every changing value as a variable, so one template serves all of them.
- In a front end, cache published responses with `s-maxage` and `stale-while-revalidate`, and
  purge on a Graph webhook (`POST https://cg.optimizely.com/api/webhooks`, topics such as
  `doc.updated`, `bulk.completed`). Never put a user identity in a shared cache key.

## Security

- The **single key** is public. It returns only published, unexpired content that Everyone can
  read, and it is the only credential that may reach a browser.
- The **app key and secret** (HMAC `epi-hmac` or Basic auth) read every item, drafts included,
  and ignore access rights unless the request sends `cg-username`/`cg-roles`. Server-side only,
  from configuration or DXP app settings, never committed.
- A preview token is a short-lived draft credential: keep it in the server-side preview flow,
  never in a log or a client bundle.

## Testing

- Unit-test code that builds queries through `.ToGraphQL()` (CMS 13) or behind your own
  interface over the client; assert on the query and map a fixed JSON response.
- Do not unit-test Graph itself. A contract check runs the project's real queries against an
  Integration or staging Graph instance, so a schema change fails there, not in production.

## Deploy and verify

- After a deploy, check *Scheduled Jobs* for the Graph sync jobs, and run the full sync after
  a content type change.
- Verify with a query: publish a change to a known item, then query that item and confirm the
  change arrived (on CMS 13, `_metadata.lastModified` matches the CMS).
- A `_Content(limit: 1) { total }` (CMS 13) or `Content(limit: 1) { total }` (CMS 12) with
  the single key confirms the gateway, the key and the sync in one call.

## Sources

https://docs.optimizely.com/graph/docs, https://docs.optimizely.com/cms-13/docs/cms-13-and-12-graph-comparison
and https://docs.optimizely.com/cms-12/docs/install-and-configure-optimizely-graph-on-your-site.
Limits and SDK method names change between releases: re-check them before you rely on one.
