---
name: optimizely-experimentation
description: Optimizely Feature Experimentation and Web Experimentation conventions — SDK setup (.NET, JavaScript 6, React 4, Python), datafiles and secure environments, user contexts and decide, bucketing and sticky bucketing, events and shutdown, avoiding flicker, the Web snippet and Performance Edge, QA with allowlists and forced decisions, testing code behind a flag, flag cleanup, CMS content variations. Load when a project references `Optimizely.SDK`, `@optimizely/optimizely-sdk`, `@optimizely/react-sdk`, the Python `optimizely-sdk`, the Web snippet `cdn.optimizely.com/js/<project id>.js`, or a Performance Edge `/edge-client/v1/` script.
---

# Optimizely Experimentation

**Feature Experimentation** (FX) runs in your code: an SDK reads a JSON datafile, buckets users
locally and sends decision and conversion events. **Web Experimentation** is a browser snippet
that applies changes built in the Optimizely app; **Performance Edge** decides them at the CDN.

## Detect

- **.NET:** `Optimizely.SDK` (nuget.org, 4.x, namespace `OptimizelySDK`). **Python:**
  `optimizely-sdk` (PyPI, 5.x, `from optimizely import optimizely`).
- **JavaScript:** `@optimizely/optimizely-sdk` 6.x; 5.x code passes `sdkKey` to `createInstance`
  and reads `{ success }` from `onReady()`. Follow the installed major; an upgrade is its own task.
- **React:** `@optimizely/react-sdk` 4.x: `<OptimizelyProvider client={...}>`, `useDecide`. 3.x: the
  `optimizely={...}` prop, `useDecision`, `<OptimizelyFeature>`.
- **Hosts:** `cdn.optimizely.com/datafiles/<sdk key>.json` (`.json/tag.js` sets
  `window.optimizelyDatafile`), `config.optimizely.com/datafiles/auth/...` (secure environments),
  `logx.optimizely.com` (events; `eu.logx.optimizely.com` in the EU).
- **Web:** `<script src="https://cdn.optimizely.com/js/<project id>.js">`, `window.optimizely`.
  **Performance Edge:** `/edge-client/v1/<account id>/<project id>` on a subdomain CNAMEd to
  `cname.optimizely-edge.com`, or `/optimizely-edge/<project id>.js` proxied by the CDN to
  `optimizely-edge.com`; the `optimizelyEdge` global.
- Neighbours: `optimizely-odp` for ODP audiences (`createOdpManager`, `fetchQualifiedSegments`),
  not repeated here; `optimizely-graph`, `optimizely-cms-saas`, `optimizely-cms13` for variations.

## Feature Experimentation setup

```ts
const optimizelyClient = createInstance({      // one per process, not per request
  projectConfigManager: createPollingProjectConfigManager({
    sdkKey: process.env.OPTIMIZELY_SDK_KEY!,
    autoUpdate: true,   // default: false in the browser build, true in Node and universal: set it
  }),
  eventProcessor: createBatchEventProcessor(), // without it, no events are sent at all
});
await optimizelyClient.onReady();              // rejects after 30 s or on close()
```

- Every JS 6 component is opt-in: no `eventProcessor` means empty results; ODP and VUID stay off
  without `odpManager`/`vuidManager`. `createInstance` throws on an invalid config.
- Before the datafile loads, a decision is `enabled: false`, `variationKey: null`, `variables: {}`:
  give every variable a default in code. Polling: every 5 minutes; under 30 s logs a warning.
- **React 4:** take `createInstance` and the factories from `@optimizely/react-sdk`; a JS SDK client
  does not work with the provider. Never name a browser client `optimizely` (the Web snippet's).
- **Edge runtimes:** `@optimizely/optimizely-sdk/universal`, which needs a `requestHandler`.
- **.NET:** `OptimizelyFactory.NewDefaultInstance(sdkKey)` polls and batches without blocking; a
  hand-built `HttpProjectConfigManager.Builder()...Build()` blocks up to 15 s for the first
  datafile (`Build(true)` does not). `new Optimizely(...)` wires only what you pass.
- Each environment (Production, Development; add Staging) has its own datafile and SDK key. Set the
  key per deployment; never point local or test runs at Production's.
- **Secure environments** need the datafile access token: JS `datafileAccessToken`, .NET
  `NewDefaultInstance(sdkKey, null, token)` or `Builder.WithAccessToken(token)` (the C# README's
  `WithDatafileAccessToken` does not exist), Python `datafile_access_token`. Server-side only.
  Securing cannot be undone: ship the token before anyone removes the public datafile.
- A change reaches the CDN in about two seconds, a client on its next poll. A static datafile
  (`createStaticProjectConfigManager`, .NET `WithDatafile`) never updates: a fallback or fixture.

## Users, decisions, bucketing

- `client.createUserContext(userId, attributes).decide("flag_key")` (.NET `CreateUserContext`,
  `Decide`; Python `create_user_context`, `decide`) returns `enabled`, `variationKey`, `variables`.
- Bucketing hashes user ID and experiment ID: an ID keeps its variation only while it still
  matches the rule's audience and the traffic allocation and variations stay the same. Use a stable, opaque ID, the same on server and client. Sticky bucketing needs
  a user profile service (`lookup`, `save`); the JS SDK ships none.
- Never change a context's user ID. Anonymous and logged-in journeys get two contexts, each
  tracking its own events (an extra MAU on MAU plans).
- `decideAll` and `decideForKeys` send an impression per flag. To precompute (edge cache, SSR), pass
  `DISABLE_DECISION_EVENT` and call `decide` where the user sees the feature.

## Events and shutdown

- `user.trackEvent("event_key", { revenue: 4200, value: 1.5 })`, once per conversion even when
  several rules measure it. `revenue` is an integer in cents. An unknown key is dropped.
- Batches: 10 events, flushed every 1 s in browsers, 30 s in Node and .NET; over 3.5 MB is a 400.
  Queued events die with the process: on shutdown `await client.close()` (JS), `Dispose()` (.NET),
  `close()` (Python). Browsers flush on `pagehide` by themselves.
- Serverless, SSR or a client per request: `disposable: true` (no polling, each event sent at once),
  and still `await close()` before the handler returns.

## Flicker

- **Web:** the snippet loads synchronously (no `async`/`defer`), first in `<head>` after charset and
  meta tags, before analytics; never through a tag manager, one per page, unedited. **Performance
  Edge:** the same, plus `referrerpolicy="no-referrer-when-downgrade"`; HTTPS pages only.
- **FX:** decide on the server or at the edge. If the browser decides, give it the datafile
  synchronously (`tag.js` or a server-inlined datafile).
- **React SSR:** the server cannot fetch a datafile mid-render: fetch it first, pass `datafile`, and
  on the server set `disposable: true` and `defaultDecideOptions: [DISABLE_DECISION_EVENT]` so only
  the browser sends impressions. Render a neutral state while `useDecide` is `isLoading`.

## Web Experimentation

- Pages say where an experiment runs; for an SPA enable *Support for Dynamic Websites* or push
  `{ type: "page", pageName }`. Events: `window["optimizely"] = window["optimizely"] || []`, then
  push `{ type: "event", eventName, tags }`; attributes: `{ type: "user", attributes }`.
- Custom code is compiled into the snippet and the UI does not check experiment code: one syntax
  error breaks the snippet on every page. Parse code before you save it.
- Wait for late elements with `optimizely.get('utils')`. Never read Optimizely's cookies or
  localStorage keys: they change without notice. To carry a Web variation into FX, pass its
  variation ID as an FX attribute and target on it.

## CMS content variations

- CMS 13 (Visual Builder) and CMS (SaaS) editors add named variations of an item. Graph returns
  originals only unless asked: `variation: { include: SOME, value: [$key], includeOriginal: true }`.
- The documented FX integration is CMS (SaaS) only: an FX string variable holds the variation name
  (exact, case-sensitive, letter first, alphanumeric), the React SDK decides, Graph returns it.
- The CMS 13 docs name A/B tests as a use but document no FX integration or selection API. Headless
  CMS 13 can follow the Graph pattern; for an in-process site, ask the operator first.

## Security

- The SDK key is in every client datafile URL: per environment, not secret. The datafile access
  token is secret: server-side configuration only, never committed, logged or bundled.
- A datafile carries every flag, variable, audience condition and allowlisted user ID; every event
  carries the user ID and attributes, unfiltered. Use an opaque ID, never an email or name.
- Performance Edge on a subdomain receives every cookie scoped to it: keep personal data out of
  them, or proxy through the CDN with a cookie allowlist.

## Testing

- Wrap the SDK in a small interface the app owns; unit-test both branches with a fake, plus the
  not-ready decision (`enabled: false`, empty `variables`). Never reach the CDN or logx in a test.
- Real decide logic offline: JS `createStaticProjectConfigManager({ datafile })` with a fixture and
  no `eventProcessor`; .NET `new Optimizely(datafileJson, eventDispatcher: <no-op>)`, since the
  default dispatcher posts to logx.
- QA: allowlist up to 50 user IDs per A/B or bandit rule (it must run: pair it with 0% traffic);
  use a QA audience for more. `setForcedDecision` fires impressions: keep it in a QA-only path.
- Web: `?optimizely_x=<variation id>` (once *Disable the force variation parameter* is cleared)
  forces a variation; `optimizely_token=PUBLIC` shows drafts to anyone: switch it off after QA.

## Deploy and verify

- FX: `onReady` resolves (.NET `IsValid`), and one known decision and event arrive (a `LOG_EVENT`
  listener, or the results page). Web: `?optimizely_log=true` logs the expected experiment.
  Performance Edge: `optimizelyEdge` is defined and the visitor ID cookie survives a refresh.
- **Flag cleanup** after a test concludes: make the winner the only path (delete the flag check, the
  losing branch and its tests), ship, then archive the flag. Archiving removes it from the
  datafile, so code still deciding on it gets `enabled: false`. *Conclude and deploy* serves the
  winner until the cleanup ships.

## Sources

https://docs.optimizely.com/feature-experimentation/docs, `/web-experimentation/docs`,
`/performance-edge/docs`, `/cms-13/docs/create-content-variations`; the packages listed in Detect
(JS 6.6, React 4.2, .NET 4.5, Python 5.7). Defaults move: re-read the installed package first.
