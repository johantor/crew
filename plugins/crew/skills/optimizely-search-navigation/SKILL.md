---
name: optimizely-search-navigation
description: Optimizely Search & Navigation (formerly Find) on CMS 12 and Customized Commerce — indexing and the conventions API, typed and unified search, filters, facets, best bets and synonyms, limits, and the migration to Optimizely Graph that CMS 13 requires. Load when a project references `EPiServer.Find*`.
---

# Optimizely Search & Navigation

Search & Navigation (S&N, formerly Episerver Find) is a hosted search index for CMS 12 and
Customized Commerce 14. It does not exist on CMS 13 and no CMS 13 support is planned, so new
search work on a site that will upgrade goes to Optimizely Graph. Optimizely calls the switch
a recommended step before the upgrade.

## Detect

- `EPiServer.Find`, `EPiServer.Find.Cms`, `EPiServer.Find.Framework` (17.x, CMS 12 only), and
  `EPiServer.Find.Commerce` for the catalog.
- `services.AddFind()` in startup, and an `EPiServer:Find` config section with `ServiceUrl`
  and `DefaultIndex`.
- On a CMS 13 project, an `EPiServer.Find*` reference is a leftover to remove
  (`optimizely-cms-upgrade`).
- Neighbours: `optimizely-cms12`, and `optimizely-graph` for the migration target.

## Indexing

- Published CMS content is indexed on save, publish, move and delete, through a local queue that
  runs every 5 seconds. The *Content Indexing Job* rebuilds the whole index: run it after the
  first install, after a convention change, or after an indexing failure, not on a schedule.
- Change what is indexed with conventions, registered once at startup (an initializable
  module):
  - `ContentIndexer.Instance.Conventions.ForInstancesOf<T>().ShouldIndex(x => ...)` to skip
    content.
  - `client.Conventions.ForInstancesOf<T>().ExcludeField(x => x.Field)` (or `[JsonIgnore]`) to
    keep a field out; `.IncludeField(x => x.Computed())` to add a computed field.
  - `.IdIs(x => x.Key)` for objects you index yourself with `client.Index(obj)`.
- Blocks in a `ContentArea` are not indexed with the page by default; nesting goes 3 levels
  deep when enabled. Content in the trash is indexed: filter it out at query time.
- Never index personal data or access-restricted fields you do not filter on. The index is a
  copy outside the CMS's access checks.

## Querying

- In a CMS site use the registered client (`SearchClient.Instance`, or `IClient` by
  constructor injection); never construct a new client per request.
- Typed search: `client.Search<T>().For(query).Filter(x => ...).Skip(n).Take(n)`, then
  `.GetContentResult()` for CMS content (cached for 1 minute) or `.GetResult()` (not cached).
- Always filter what a visitor may see: `.FilterForVisitor()` (excludes deleted, applies
  language and read access), or `.CurrentlyPublished()` + `.ExcludeDeleted()` +
  `.FilterOnReadAccess()`; `.FilterOnCurrentSite()` on a multi-site install.
- Unified search: `client.UnifiedSearchFor(query).GetResult()` over `ISearchContent`; register
  types through `Conventions.UnifiedSearchRegistry`. `MultiUnifiedSearch()` batches up to 10.
- Facets: `TermsFacetFor(x => x.Tag, f => f.Size = 20)` (default 10 terms; set `Size`, not
  `Take`), `RangeFacetFor`, `HistogramFacetFor`.
- `.Track()` before `GetResult()` records statistics; `.ApplyBestBets()` and
  `.UsingSynonyms()` are off until called.

## Limits

- `Take` defaults to 10 and throws above 1,000; `Skip` + `Take` cannot reach past hit 10,000.
- An index request is at most 50 MB (about 37 MB of content after encoding); a term over 8,191
  bytes is not indexed.
- A developer index (from find.optimizely.com) holds 10,000 documents, takes 20 queries per
  second and is deleted after 30 days. Never point a production config at one.

## Migrating to Graph

Follow Optimizely's *Overview of migrating from Search & Navigation* guide. Do it as steps, each
reviewable: install Graph beside S&N, run both, compare results, switch traffic, then remove S&N.

1. **Sync on CMS 12.** Add `EPiServer.ContentDeliveryApi.Cms` and `Optimizely.ContentGraph.Cms`,
   register `AddContentDeliveryApi()` then `AddContentGraph()`, and run the full sync
   (`optimizely-graph`).
2. **Port the queries.** On CMS 12 the queries are plain GraphQL; `Optimizely.Graph.Client` is
   deprecated and the CMS 13 SDK does not run on 12. On CMS 13 the SDK maps the Find API:
   `Search<T>` → `QueryContent<T>`, `For` → `SearchFor`, `Filter` → `Where`, `Take` → `Limit`,
   `GetResult()` → `await GetAsContentAsync()`, `TotalMatching` → `Total`. Replace `AddFind()`
   with `AddContentGraph()` and `AddGraphContentClient()`.
3. **Port the features.** Best bets become pinned results and synonyms move to Graph's REST
   API, per language; neither has an admin UI. Autocomplete works only on string filter fields.
   Title and URL overrides on best bets, did-you-mean, spellcheck and the statistics dashboard
   have no equivalent: list each one the site uses and ask the operator before you drop it.
4. **Unified search** has no one-to-one equivalent; query the base type (`Content` on 12,
   `_Content` on 13) with the fields the result list shows.
5. **Compare** the top results for the site's most common queries on both engines before you
   switch, and keep S&N as a fallback until the switch is confirmed.

## Security

- Treat the `ServiceUrl` as a secret, since it addresses the index: it comes from configuration
  or DXP app settings, never a committed `appsettings.json`.
- A query without a visitor filter returns unpublished and restricted content; every
  visitor-facing search goes through `FilterForVisitor()` or its parts.

## Testing

- Inject `IClient` and test the code around the query (filters chosen, mapping of hits) with a
  mocked client; do not unit-test the search engine.
- Test relevance and facets against a developer index with known content, not production.

## Deploy and verify

- After a deploy that changes conventions or content types, run the content indexing job and
  check its log in *Scheduled Jobs*.
- Run a known query on the deployed site and confirm the expected item is the first hit.

## Sources

https://docs.optimizely.com/cms-12/docs (the S&N pages live there now) and
https://docs.optimizely.com/graph/docs/migration-documentation-overview. Graph's feature set
grows release by release: re-check the migration gaps before you report one as missing.
