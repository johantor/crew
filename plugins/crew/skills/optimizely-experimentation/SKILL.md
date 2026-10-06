---
name: optimizely-experimentation
description: Optimizely Feature Experimentation and Web Experimentation conventions — SDK setup (.NET, JavaScript 6, React 4, Python), datafiles and secure environments, user contexts and decide, bucketing and sticky bucketing, events and shutdown, avoiding flicker, the Web snippet and Performance Edge, QA with allowlists and forced decisions, testing code behind a flag, flag cleanup, CMS content variations. Load when a project references `Optimizely.SDK`, `@optimizely/optimizely-sdk`, `@optimizely/react-sdk`, the Python `optimizely-sdk`, the Web snippet `cdn.optimizely.com/js/<project id>.js`, or a Performance Edge `/edge-client/v1/` script.
---

# Optimizely Experimentation

Two products share the results and stats, not the code. **Feature Experimentation** (FX) runs in
your code: an SDK reads a JSON datafile, buckets users locally, and sends decision and conversion
events. **Web Experimentation** runs in the browser: a snippet applies changes built in the
Optimizely app. **Performance Edge** is a subset of Web that decides at the CDN.

## Detect

- **.NET:** `Optimizely.SDK` on nuget.org (4.x, namespace `OptimizelySDK`).
- **JavaScript:** `@optimizely/optimizely-sdk`. 6.x is current and its API differs from 5.x: 5.x
  passes `sdkKey` to `createInstance` and reads `{ success }` from `onReady()`. Follow the
  installed major; an upgrade is its own task (*Upgrade the JavaScript SDK from v5 to v6*).
- **React:** `@optimizely/react-sdk`. 4.x (on JS SDK 6): `<OptimizelyProvider client={...}>`,
  `useDecide`, `useDecideForKeys`, `useDecideAll`. 3.x: the `optimizely={...}` prop, `useDecision`,
  `<OptimizelyFeature>`, `<OptimizelyExperiment>`.
- **Python:** `optimizely-sdk` on PyPI (5.x, `from optimizely import optimizely`).
- **Hosts:** datafiles at `cdn.optimizely.com/datafiles/<sdk key>.json` (`.json/tag.js` sets
  `window.optimizelyDatafile`) and `config.optimizely.com/datafiles/auth/<sdk key>.json` (secure
  environments); events to `logx.optimizely.com/v1/events` (`eu.logx.optimizely.com` in the EU).
- **Web snippet:** `<script src="https://cdn.optimizely.com/js/<project id>.js">`, the
  `window.optimizely` API (`push`, `get`), the `optimizelyEndUserId` cookie.
- **Performance Edge:** a script to `/edge-client/v1/<account id>/<project id>` on a subdomain
  CNAMEd to `cname.optimizely-edge.com`, or `/optimizely-edge/<project id>.js` proxied by the CDN
  to `optimizely-edge.com`; the `optimizelyEdge` global.
- Neighbours: `optimizely-odp` for real-time (ODP) audiences (`createOdpManager`,
  `fetchQualifiedSegments`); this skill does not repeat it. `optimizely-graph`,
  `optimizely-cms-saas` and `optimizely-cms13` for content variations.

## Feature Experimentation setup

```ts
import { createInstance, createPollingProjectConfigManager, createBatchEventProcessor }
  from "@optimizely/optimizely-sdk";

const optimizelyClient = createInstance({            // one per process, not per request
  projectConfigManager: createPollingProjectConfigManager({
    sdkKey: process.env.OPTIMIZELY_SDK_KEY!,
    autoUpdate: true,      // the JS docs say the default is false, the package uses true: set it
  }),
  eventProcessor: createBatchEventProcessor(),       // without it no events are sent at all
});
await optimizelyClient.onReady();                    // rejects after 30 s or on close()
```

- Every 6.x component is opt-in: no `eventProcessor` means empty results; ODP and VUID stay off
  without `odpManager` and `vuidManager`. `createInstance` throws on an invalid config.
- A decision before the datafile loads returns `enabled: false`, `variationKey: null` and
  `variables: {}`. Give every variable a default in code.
- Polling defaults to 5 minutes; the package warns below 30 s.
- **React 4:** import `createInstance` and the factories from `@optimizely/react-sdk`; a client from
  the JS SDK does not work with the provider. In a browser never name the client `optimizely`:
  `window.optimizely` belongs to the Web snippet.
- **Edge runtimes** (Workers, Vercel Edge, Lambda@Edge): `@optimizely/optimizely-sdk/universal`,
  which needs a `requestHandler`.
- **.NET:** `OptimizelyFactory.NewDefaultInstance(sdkKey)` polls and batches events without
  blocking. A hand-built `HttpProjectConfigManager.Builder()...Build()` blocks the thread until the
  first datafile (up to 15 s); `Build(true)` does not. `new Optimizely(configManager)` without
  `eventProcessor:` sends events unbatched, and a logger or notification center works only when
  passed. Register one instance as a singleton; it is `IDisposable`.
- **Python:** `optimizely.Optimizely(sdk_key=...)`.

## Datafile and environments

- Each environment (Production and Development by default; add Staging) has its own datafile and
  SDK key. Configure the key per deployment; never point local or test runs at Production's.
- **Secure environments:** pass the datafile access token: JS `datafileAccessToken`, .NET
  `NewDefaultInstance(sdkKey, null, token)` or `Builder.WithAccessToken(token)` (the C# README's
  `WithDatafileAccessToken` does not exist), Python `datafile_access_token`. Server-side SDKs
  only. Securing cannot be undone: ship the token before anyone removes the public datafile.
- A change reaches the CDN in about two seconds and a client on its next poll; webhooks push
  faster. A static or bundled datafile (`createStaticProjectConfigManager`, .NET `WithDatafile`)
  never sees changes: use it as a fallback or a fixture.

## Users, decisions, bucketing

- `client.createUserContext(userId, attributes).decide("flag_key")` (.NET `CreateUserContext` /
  `Decide`, Python `create_user_context` / `decide`); read `enabled`, `variationKey`, `variables`.
- Bucketing hashes the user ID with the experiment ID. The same ID gets the same variation until
  the traffic split or the variations change (0% and back rebuckets everyone). Use a stable,
  opaque ID and the same one on server and client.
- Never change a user context's ID. For anonymous and logged-in journeys, create two contexts and
  track events on each (each counts as a MAU).
- Sticky bucketing needs a user profile service (`userProfileService`, or `userProfileServiceAsync`
  with `decideAsync`), `lookup` and `save`; the JS SDK ships none.
- `decide` sends an impression; `decideAll` and `decideForKeys` send one per flag. When you
  precompute (edge cache, SSR), pass `DISABLE_DECISION_EVENT` and call `decide` where the user sees
  the feature. Also: `ENABLED_FLAGS_ONLY`, `IGNORE_USER_PROFILE_SERVICE`, `INCLUDE_REASONS`.

## Events and shutdown

- `user.trackEvent("event_key", { revenue: 4200, value: 1.5 })`, once per conversion even when
  several rules measure it. `revenue` is an integer in cents. An unknown key is dropped.
- Batches: 10 events, flushed every 1 s in browsers and 30 s in Node and .NET; a batch over
  3.5 MB is rejected with 400.
- Queued events die with the process: `await client.close()` (JS), `Dispose()` (.NET), `close()`
  (Python) on shutdown. Browsers flush on `pagehide` by themselves.
- Serverless, SSR or a client per request: `disposable: true` (no polling, each event sent at
  once), and still `await close()` before the handler returns.
- The JS SDK keeps no queue across navigation: track a link click on the destination page.

## Flicker

- **Web:** the snippet loads synchronously (no `async` or `defer`), first in `<head>` after the
  charset and meta tags, before analytics. Never through a tag manager, one snippet per page,
  never edited. Move heavy visual changes to variation CSS.
- **Performance Edge:** the same placement, no `async`, and `referrerpolicy="no-referrer-when-downgrade"`
  on the tag (URL targeting needs the full referrer). HTTPS pages only.
- **FX in a browser:** decide on the server or at the edge and render the result. If the browser
  decides, give it the datafile synchronously (the `tag.js` script or a server-inlined datafile).
- **React SSR (Next.js):** the server cannot fetch the datafile during render: fetch it first and
  pass `datafile`. On the server, `disposable: true` and
  `defaultDecideOptions: [OptimizelyDecideOption.DISABLE_DECISION_EVENT]`, so only the browser
  sends impressions. `useDecide` returns `{ decision, isLoading, error }`: render a neutral state
  while loading. Static pages decide after hydration.

## Web Experimentation

- Pages say where an experiment runs. For an SPA enable *Support for Dynamic Websites* (URL or DOM
  change triggers), or activate with `window["optimizely"].push({ type: "page", pageName })`.
- Events: `window["optimizely"] = window["optimizely"] || []; window["optimizely"].push({ type:
  "event", eventName, tags })`. Attributes: `{ type: "user", attributes }`, string values.
  `{ type: "optOut", isOptOut: true }` blocks the snippet; the API cannot opt back in.
- Custom code is compiled into the snippet: a syntax error in project, experiment or variation code
  breaks the snippet on every page, and the UI does not check it. Parse it before you save.
- Wait for late elements with `optimizely.get('utils')` (`waitForElement`, `waitUntil`). Never read
  Optimizely's cookies or localStorage keys: they change without notice; use the `get` API.
- A strict CSP needs the sources in *Update your site's content security policies*; audiences with
  custom JavaScript also need `'unsafe-eval'`.
- **Performance Edge** has no custom snippets, its API is `optimizelyEdge`, and force parameters
  work only on running experiments.
- To keep a Web variation through an FX journey, pass its variation ID as an FX attribute and target
  an FX audience on it.

## CMS content variations

- CMS 13 (Visual Builder) and CMS (SaaS) let editors add named variations of a content item. Graph
  returns originals only, unless asked: `_Content(variation: { include: SOME, value: [$key],
  includeOriginal: true })`, or `ALL` / `NONE`.
- The documented FX integration is for CMS (SaaS): an FX string variable holds the CMS variation
  name, the front end decides with the React SDK, then queries Graph with that name. Names match
  exactly (case-sensitive), start with a letter, alphanumeric only.
- The CMS 13 docs list A/B tests as a use of variations but document no FX integration or
  selection API. Headless CMS 13 can use the Graph pattern; for an in-process site, ask the
  operator before you build a selection mechanism. CMS 13 audiences (visitor groups) personalize;
  they do not experiment.

## Flag cleanup

- After a test concludes: make the winner the only code path, delete the flag check, the losing
  branch and its tests, and ship. Then archive the flag. Archiving removes it from the datafile,
  so code that still decides on it gets `enabled: false`; never archive first. *Conclude and
  deploy* serves the winner without code until the cleanup ships.

## Security

- The SDK key is in every client datafile URL: per environment, not secret. The datafile access
  token is secret: server-side configuration only, never committed, logged or bundled.
- A datafile lists every flag, variable, audience condition and allowlisted user ID of its
  environment. Keep secrets and PII out of all of them in a client-visible environment.
- User IDs and attributes go to Optimizely with every event, and batching strips nothing. Use an
  opaque ID, never an email or name; send only attributes an audience or a report uses.
- Performance Edge on a subdomain receives every cookie scoped to it: keep personal data out of
  those cookies, or use a CDN proxy with a cookie allowlist.

## Testing

- Wrap the SDK in a small interface the app owns and unit-test both branches with a fake. Include
  the not-ready decision (`enabled: false`, empty `variables`).
- Real decide logic offline: JS `createStaticProjectConfigManager({ datafile })` with a fixture and
  no `eventProcessor`; .NET `new Optimizely(datafileJson, eventDispatcher: <no-op>)`, since the
  default dispatcher posts to logx. `IOptimizely` is an interface and `OptimizelyUserContext.Decide`
  is virtual. Never reach `cdn.optimizely.com` or `logx` from a unit test.
- QA: allowlist up to 50 user IDs per A/B or bandit rule (not targeted deliveries; the rule must
  run, so pair it with 0% traffic or a non-matching audience); larger groups get a QA audience.
  `setForcedDecision({ flagKey, ruleKey }, { variationKey })` fires impressions and lives only on
  that user context: keep it behind a QA-only path.
- Web: `?optimizely_x=<variation id>` forces a variation once *Disable the force variation
  parameter* is cleared; `optimizely_force_tracking=true` sends events, `optimizely_log=true` logs,
  `optimizely_disable=true` turns the snippet off. `optimizely_token=PUBLIC` shows drafts to anyone
  who knows it: re-disable it after QA.

## Deploy and verify

- FX: confirm the client becomes ready (`onReady` resolves, .NET `IsValid`), then one known decision
  and one known event arrive (a `LOG_EVENT` notification listener, or the results page).
- Web: `window.optimizely` exists, the snippet loads once, and `?optimizely_log=true` shows the
  expected experiment. Performance Edge: `optimizelyEdge` is defined and the visitor ID cookie keeps
  its value across a refresh.

## Sources

https://docs.optimizely.com/feature-experimentation/docs, https://docs.optimizely.com/web-experimentation/docs,
https://docs.optimizely.com/performance-edge/docs, https://docs.optimizely.com/cms-13/docs/create-content-variations,
and the published packages (`@optimizely/optimizely-sdk` 6.6, `@optimizely/react-sdk` 4.2,
`Optimizely.SDK` 4.5, `optimizely-sdk` 5.7). SDK defaults move between releases: re-read the
installed package's typings before you rely on one.
