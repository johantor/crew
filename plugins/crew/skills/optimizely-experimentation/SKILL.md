---
name: optimizely-experimentation
description: Optimizely Feature Experimentation and Web Experimentation conventions — SDK setup (.NET, JavaScript 6, React 4, Python), datafiles and secure environments, user contexts and decide, bucketing and sticky bucketing, events and shutdown, avoiding flicker, the Web snippet and Performance Edge, QA with allowlists and forced decisions, testing code behind a flag, flag cleanup, CMS content variations. Load when a project references `Optimizely.SDK`, `@optimizely/optimizely-sdk`, `@optimizely/react-sdk`, the Python `optimizely-sdk`, the Web snippet `cdn.optimizely.com/js/<project id>.js`, or a Performance Edge `/edge-client/v1/` script.
---

# Optimizely Experimentation

**Feature Experimentation** (FX) runs in your code: an SDK reads a JSON datafile, buckets users
locally and sends decision and conversion events. **Web Experimentation** is a browser snippet that
applies changes built in the Optimizely app. **Performance Edge** is a subset of Web that decides
at the CDN.

## Detect

- **.NET:** `Optimizely.SDK` (nuget.org, 4.x, namespace `OptimizelySDK`). **Python:**
  `optimizely-sdk` (PyPI, 5.x, `from optimizely import optimizely`).
- **JavaScript:** `@optimizely/optimizely-sdk`. 6.x is current; 5.x code passes `sdkKey` to
  `createInstance` and reads `{ success }` from `onReady()`. Follow the installed major; an upgrade
  is its own task.
- **React:** `@optimizely/react-sdk` 4.x: `<OptimizelyProvider client={...}>`, `useDecide`. 3.x: the
  `optimizely={...}` prop, `useDecision`, `<OptimizelyFeature>`.
- **Hosts:** `cdn.optimizely.com/datafiles/<sdk key>.json` (`.json/tag.js` sets
  `window.optimizelyDatafile`), `config.optimizely.com/datafiles/auth/...` (secure environments),
  events to `logx.optimizely.com` (`eu.logx.optimizely.com` in the EU).
- **Web:** `<script src="https://cdn.optimizely.com/js/<project id>.js">`, `window.optimizely`.
- **Performance Edge:** a script to `/edge-client/v1/<account id>/<project id>` on a subdomain
  CNAMEd to `cname.optimizely-edge.com`, or `/optimizely-edge/<project id>.js` that the CDN proxies
  to `optimizely-edge.com`; the `optimizelyEdge` global.
- Neighbours: `optimizely-odp` for ODP audiences (`createOdpManager`, `fetchQualifiedSegments`),
  not repeated here; `optimizely-graph`, `optimizely-cms-saas`, `optimizely-cms13` for variations.

## Feature Experimentation setup

```ts
const optimizelyClient = createInstance({      // one per process, not per request
  projectConfigManager: createPollingProjectConfigManager({
    sdkKey: process.env.OPTIMIZELY_SDK_KEY!,
    autoUpdate: true,   // the JS docs say the default is false, the 6.6 package uses true: set it
  }),
  eventProcessor: createBatchEventProcessor(), // without it, no events are sent at all
});
await optimizelyClient.onReady();              // rejects after 30 s or on close()
```

- Every JS 6 component is opt-in: no `eventProcessor` means empty results, and ODP and VUID stay
  off without `odpManager` and `vuidManager`. `createInstance` throws on an invalid config.
- Before the datafile loads, a decision is `enabled: false`, `variationKey: null`,
  `variables: {}`. Give every variable a default in code. Polling: 5 minutes; under 30 s warns.
- **React 4:** import `createInstance` and the factories from `@optimizely/react-sdk`; a JS SDK
  client does not work with the provider. Never name a browser client `optimizely`:
  `window.optimizely` belongs to the Web snippet.
- **Edge runtimes:** `@optimizely/optimizely-sdk/universal`, which needs a `requestHandler`.
- **.NET:** `OptimizelyFactory.NewDefaultInstance(sdkKey)` polls and batches without blocking. A
  hand-built `HttpProjectConfigManager.Builder()...Build()` blocks until the first datafile (up to
  15 s); `Build(true)` does not. `new Optimizely(configManager)` without `eventProcessor:` sends
  events unbatched, and a logger or notification center works only when passed. One singleton.

## Datafile and environments

- Each environment (Production and Development by default; add Staging) has its own datafile and
  SDK key. Set the key per deployment; never point local or test runs at Production's.
- **Secure environments** need the datafile access token: JS `datafileAccessToken`, .NET
  `NewDefaultInstance(sdkKey, null, token)` or `Builder.WithAccessToken(token)` (the C# README's
  `WithDatafileAccessToken` does not exist), Python `datafile_access_token`. Server-side only.
  Securing cannot be undone: ship the token before anyone removes the public datafile.
- A change reaches the CDN in about two seconds and a client on its next poll. A static or bundled
  datafile (`createStaticProjectConfigManager`, .NET `WithDatafile`) never updates: a fallback or a
  test fixture, not the source.

## Users, decisions, bucketing

- `client.createUserContext(userId, attributes).decide("flag_key")` (.NET `CreateUserContext`,
  `Decide`; Python `create_user_context`, `decide`) returns `enabled`, `variationKey`, `variables`.
- Bucketing hashes the user ID with the experiment ID: the same ID keeps its variation until the
  split or the variations change (0% and back rebuckets everyone). Use a stable, opaque ID, the
  same on server and client. Sticky bucketing needs a user profile service (`lookup`, `save`;
  with `userProfileServiceAsync`, call `decideAsync`); the JS SDK ships none.
- Never change a context's user ID. Anonymous and logged-in journeys get two contexts, each
  tracking its own events (an extra MAU on MAU plans).
- `decide` sends an impression; `decideAll` and `decideForKeys` send one per flag. When you
  precompute (edge cache, SSR), pass `DISABLE_DECISION_EVENT` and call `decide` where the user sees
  the feature. `INCLUDE_REASONS` explains a decision while you debug.

## Events and shutdown

- `user.trackEvent("event_key", { revenue: 4200, value: 1.5 })`, once per conversion even when
  several rules measure it. `revenue` is an integer in cents. An unknown key is dropped.
- Batches hold 10 events and flush every 1 s in browsers, 30 s in Node and .NET; over 3.5 MB is a
  400. Queued events die with the process: `await client.close()` (JS), `Dispose()` (.NET),
  `close()` (Python) on shutdown. Browsers flush on `pagehide` by themselves.
- Serverless, SSR or a client per request: `disposable: true` (no polling, each event sent at
  once), and still `await close()` before the handler returns.
- The JS SDK keeps no queue across navigation: track a link click on the destination page.

## Flicker

- **Web:** load the snippet synchronously (no `async`, no `defer`), first in `<head>` after the
  charset and meta tags, before analytics; not through a tag manager, one per page, unedited.
- **Performance Edge:** the same, plus `referrerpolicy="no-referrer-when-downgrade"` on the tag (URL
  targeting needs the full referrer). HTTPS pages only.
- **FX in a browser:** decide on the server or at the edge and render the result. If the browser
  decides, give it the datafile synchronously (`tag.js` or a datafile the server inlines).
- **React SSR:** the server cannot fetch a datafile during render: fetch it first and pass
  `datafile`. On the server set `disposable: true` and `defaultDecideOptions:
  [OptimizelyDecideOption.DISABLE_DECISION_EVENT]`, so only the browser sends impressions. Render a
  neutral state while `useDecide` reports `isLoading`. Static pages decide after hydration.

## Web Experimentation

- Pages say where an experiment runs. For an SPA enable *Support for Dynamic Websites*, or activate
  with `window["optimizely"].push({ type: "page", pageName })`. Events: `{ type: "event", eventName,
  tags }` after `window["optimizely"] = window["optimizely"] || []`; attributes: `{ type: "user",
  attributes }`. `{ type: "optOut", isOptOut: true }` blocks the snippet for good.
- Custom code is compiled into the snippet, and the UI does not check experiment code: one syntax
  error breaks the snippet on every page. Parse code before you save it.
- Wait for late elements with `optimizely.get('utils')` (`waitForElement`, `waitUntil`). Never read
  Optimizely's cookies or localStorage keys; they change without notice.
- Performance Edge: no custom snippets, its API is `optimizelyEdge`.
- To carry a Web variation into FX, pass its variation ID as an FX attribute and target on it.

## CMS content variations

- CMS 13 (Visual Builder) and CMS (SaaS) editors add named variations of a content item. Graph
  returns originals only unless asked: `_Content(variation: { include: SOME, value: [$key],
  includeOriginal: true })`.
- The documented FX integration is for CMS (SaaS): an FX string variable holds the variation name,
  the front end decides with the React SDK and queries Graph with it. Names match exactly
  (case-sensitive), start with a letter, alphanumeric only.
- The CMS 13 docs name A/B tests as a use but document no FX integration or selection API. Headless
  CMS 13 can follow the Graph pattern; for an in-process site, ask the operator first. CMS 13
  audiences personalize; they do not experiment.

## Flag cleanup

- After a test concludes, make the winner the only path: delete the flag check, the losing branch
  and its tests, and ship. Then archive the flag. Archiving removes it from the datafile, so code
  that still decides on it gets `enabled: false`: never archive first. *Conclude and deploy*
  serves the winner without code until the cleanup ships.

## Security

- The SDK key is in every client datafile URL: per environment, not secret. The datafile access
  token is secret: server-side configuration only, never committed, logged or bundled.
- A datafile carries every flag, variable, audience condition and allowlisted user ID of its
  environment: no secrets or PII there in a client-visible environment.
- User IDs and attributes travel with every event, and batching strips nothing. Use an opaque ID,
  never an email or name; send only attributes an audience or a report uses.
- Performance Edge on a subdomain receives every cookie scoped to it: keep personal data out of
  those cookies, or proxy through the CDN with a cookie allowlist.

## Testing

- Wrap the SDK in a small interface the app owns and unit-test both branches with a fake, plus the
  not-ready decision (`enabled: false`, empty `variables`). Never reach the CDN or logx in a test.
- Real decide logic offline: JS `createStaticProjectConfigManager({ datafile })` with a fixture and
  no `eventProcessor`; .NET `new Optimizely(datafileJson, eventDispatcher: <no-op>)`, since the
  default dispatcher posts to logx. `IOptimizely` and the virtual `OptimizelyUserContext.Decide`
  can be faked.
- QA: allowlist up to 50 user IDs per A/B or bandit rule (not targeted deliveries; the rule must run,
  so pair it with 0% traffic or a non-matching audience); larger groups get a QA audience.
  `setForcedDecision({ flagKey, ruleKey }, { variationKey })` fires impressions and lives only on
  that context: keep it behind a QA-only path.
- Web: `?optimizely_x=<variation id>` forces a variation once *Disable the force variation
  parameter* is cleared; add `optimizely_force_tracking=true` to count it, `optimizely_log=true` to
  log. `optimizely_token=PUBLIC` shows drafts to anyone: switch it off after QA.

## Deploy and verify

- FX: the client becomes ready (`onReady` resolves; .NET `IsValid`), and one known decision and
  event arrive (a `LOG_EVENT` notification listener, or the results page).
- Web: `window.optimizely` exists and `?optimizely_log=true` shows the expected experiment.
  Performance Edge: `optimizelyEdge` is defined and the visitor ID cookie survives a refresh.

## Sources

https://docs.optimizely.com/feature-experimentation/docs, .../web-experimentation/docs,
.../performance-edge/docs and .../cms-13/docs/create-content-variations, and the published
packages (`@optimizely/optimizely-sdk` 6.6, `@optimizely/react-sdk` 4.2, `Optimizely.SDK` 4.5,
`optimizely-sdk` 5.7). Defaults move between releases: re-read the installed package first.
