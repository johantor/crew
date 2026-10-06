---
name: optimizely-search-navigation
description: Optimizely Search & Navigation (formerly Find) on CMS 12 and Customized Commerce — indexing and the conventions API, typed and unified search, filters, facets, best bets and synonyms, limits, and the migration to Optimizely Graph that CMS 13 requires. Load when a project references `EPiServer.Find*`.
---

# Optimizely Search & Navigation

Search & Navigation (S&N, formerly Episerver Find) is a hosted search index for CMS 12 and
Customized Commerce 14. It does not exist on CMS 13 and no CMS 13 support is planned, so a site
that upgrades moves its search to Optimizely Graph. Optimizely recommends doing that move with
the CMS 13 upgrade, not before: the Graph schema changes between 12 and 13, so queries written
on 12 are written twice.

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
  constructor injection). Never create an `IClient` yourself: a client built after the
  conventions are applied overwrites them.
- Typed search: `client.Search<T>().For(query).Filter(x => ...).Skip(n).Take(n)`, then
  `.GetContentResult()` for CMS content or `.GetResult()`. Both are cached for 10 minutes by
  default (`DefaultSearchCacheDuration`, in seconds; `0` turns it off); a query that must see
  fresh content sets its own duration.
- Always filter what a visitor may see: `.FilterForVisitor()` (`ExcludeDeleted()` +
  `PublishedInCurrentLanguage()` + `FilterOnReadAccess()`); `.FilterOnCurrentSite()` on a
  multi-site install. Built from parts, use `PublishedInCurrentLanguage()`:
  `CurrentlyPublished()` accepts content published in any language.
- Unified search: `client.UnifiedSearchFor(query).GetResult()` over `ISearchContent`; register
  types through `Conventions.UnifiedSearchRegistry`. `MultiUnifiedSearch()` batches up to 10.
- Facets: `TermsFacetFor(x => x.Tag, f => f.Size = 20)` (default 10 terms; set `Size`, not
  `Take`), `RangeFacetFor`, `HistogramFacetFor`.
- `.Track()` before `GetResult()` records statistics; `.ApplyBestBets()` and
  `.UsingSynonyms()` are off until called.

## Limits

- `Take` defaults to 10 and throws above 1,000; `Skip` + `Take` cannot reach past hit 10,000.
- An index request is at most 50 MB (about 37 MB of content after encoding); a string field
  over 8,191 characters is neither indexed nor stored.
- A developer index (from find.optimizely.com) holds 10,000 documents, takes 5 MB per request
  and 20 queries per second, and is deleted after 30 days. Never point a production config at
  one.

## Migrating to Graph

Follow Optimizely's *Overview of migrating from Search & Navigation* guide, as reviewable steps.
`EPiServer.Find.Cms` 17 requires CMS 12, so S&N and the CMS 13 SDK never run in one site: the
CMS 12 site with S&N is the baseline to compare against.

1. **Pick the path.** By default, port search as part of the CMS 13 upgrade
   (`optimizely-cms-upgrade`). Move on CMS 12 only when the site must leave S&N before 13; then
   sync with `EPiServer.ContentDeliveryApi.Cms` and `Optimizely.ContentGraph.Cms`
   (`AddContentDeliveryApi()` then `AddContentGraph()`, full sync), and write plain GraphQL,
   since `Optimizely.Graph.Client` is deprecated and the CMS 13 SDK does not run on 12. Tell
   the operator that those queries are rewritten at the upgrade.
2. **Port the queries (CMS 13).** For CMS content the SDK maps the Find API: `Search<T>` →
   `QueryContent<T>`, `For` → `SearchFor` (with `.UsingFullText()` or `.UsingField(...)`),
   `Filter` → `Where`, `Take` → `Limit`, `GetResult()` → `await GetAsContentAsync()`,
   `TotalMatching` → `Total` (add `.IncludeTotal()`, or it is null). Startup: remove
   `AddFind()`, add `AddContentGraph()`, `AddGraphContentClient()` and `AddVisitorGroupsCore()`,
   and `app.UseGraphTrackingScripts()` for tracking. Follow the guide's full startup diff.
3. **Port the features.** Best bets become pinned results and synonyms are set per language,
   both through Graph's REST API or the Search Management portal (beta). Autocomplete works
   only on fields of type `StringFilterInput`, not on searchable strings such as `Name`, and S&N
   autocomplete phrases do not carry over. Title and URL overrides on best bets, did-you-mean
   and spellcheck have no equivalent: list each one the site uses and ask the operator before
   you drop it.
4. **Unified search** has no one-to-one equivalent; query the base type (`_Content` on 13) with
   the fields the result list shows.
5. **Compare** the top results for the site's most common queries against the CMS 12 baseline
   before you switch, and keep the CMS 12 deployment until the switch is confirmed.

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
