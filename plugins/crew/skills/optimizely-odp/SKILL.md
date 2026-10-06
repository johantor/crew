---
name: optimizely-odp
description: Optimizely Data Platform (ODP, formerly Zaius) conventions — the data model (objects, fields, identifiers, identity resolution), sending events and profiles (REST, GraphQL, the JavaScript tag, the Node SDK), real-time audiences and how CMS, Feature Experimentation and Web Experimentation consume them, keys, consent and PII, rate limits, testing without polluting production. Load when a project references `Optimizely.Cms.Odp`, `UNRVLD.ODP.VisitorGroups`, `EPiServer.Commerce.ODP`, `@zaiusinc/node-sdk`, the `zaius` web tag, or an ODP API host.
---

# Optimizely Data Platform

ODP (formerly Zaius) unifies customer profiles from events and identifiers and builds real-time
audiences (also called segments) that CMS and Experimentation target. The Zaius names are still
in the product: the `zaius` global, `zaius_id`, `api.zaius.com`, `app.zaius.com`.

## Detect

- **Web tag:** a snippet that starts `var zaius = window['zaius']||(window['zaius']=[]);` and
  loads `zaius-min.js` from `tag.odp.optimizely.com/v2/<tracker id>/` (older sites: a CloudFront
  host), then `zaius.event('pageview')`. Cookies: `vuid`, `z_customer_id`.
- **.NET:** `Optimizely.Cms.Odp` (official; 1.0 for CMS 12, 1.1+ for CMS 13), the community
  `UNRVLD.ODP.VisitorGroups`, and `EPiServer.Commerce.ODP`.
- **Node:** `@zaiusinc/node-sdk` (3.x needs Node 22+; main export `odp`), keyed by
  `ODP_SDK_API_KEY` (legacy `ZAIUS_SDK_API_KEY`).
- **Feature Experimentation:** `fetchQualifiedSegments`, `isQualifiedFor`, `sendOdpEvent`, or
  `createOdpManager` (JS SDK 6).
- **API hosts:** `api.zaius.com` or `api.us1.odp.optimizely.com` (US), `api.eu1.odp.optimizely.com`
  (EU), `api.au1.odp.optimizely.com` (APAC). An account lives in one region: use its host.
- Neighbours: `optimizely-cms12` / `optimizely-cms13` for the CMS side.

## Data model

- Data lives in **objects** (customers, events, products, orders, custom objects) made of
  **fields**: text (max 1,024 characters), number, date-time (ISO 8601 or epoch), boolean.
- A field or object cannot be renamed. A custom field can be deleted; a custom object only
  through support, and only app developers or the CSM create custom objects and identifiers.
  Name fields once, and ask the operator before you add one.
- **Identifiers** tie data to a customer: `email`, `phone`, `vuid` (the web tag's visitor ID),
  `zaius_id`, plus custom ones created with a `merge_confidence` of `high` or `low`.
- **Identity resolution:** a high-confidence identifier (email, a commerce customer ID) merges
  profiles; a low-confidence one (vuid, phone, push token) moves to the other profile instead.
  Never send a shared or reused value (a household email, a test address) as a high-confidence
  identifier: it merges unrelated people.
- **Events** are immutable: `type` and `action` describe them, `identifiers` (required) say
  whose they are, `data` carries the fields. Product events need `product_id`.

## Sending data

- REST, `x-api-key` header, against the account's regional host; all writes are `POST` and
  return 202 (accepted, not yet processed):
  - `/v3/events`, `/v3/profiles` (`[{ attributes: { ... } }]`), `/v3/objects/{object}`,
    `/v3/consent`.
  - Batch: the docs allow 500 items per request; `@zaiusinc/node-sdk` caps a batch at 100. Use
    the SDK's limit when the SDK sends.
- **JavaScript tag:** `zaius.event(type, { action, ... })` (adds the vuid),
  `zaius.customer({ identifiers }, { attributes })`, `zaius.object({ type, ... })`,
  `zaius.consent({ consent, identifier_field_name, identifier_value, ... })`, and
  `zaius.anonymize()` on logout or a shared device. Do not use the legacy `zaius.entity`,
  `subscribe` or `unsubscribe` in new code.
- Send orders, refunds and cancellations from the server (REST or the SDK), never through the
  tag: ad blockers drop them.
- **GraphQL** (`/v3/graphql`) is for point reads and joins, at most 1,000 results per page; use
  the Exports API for more.
- Every write is accepted asynchronously. Check that data arrived (Event Inspector or a read),
  never assume it from the 202.

## Real-time audiences

- An audience is a rule over profile and event data. Real-time audiences read the last 28 days
  of events, and membership updates within about 90 seconds.
- Read membership with GraphQL: `customer(vuid: "...") { audiences(subset: [...]) { edges {
  node { name } } } }`. Strip the hyphens from `zaius.VUID` before you query with it. Pass
  `recent_events` (each with `type` and `idempotence_id`) to count events still in the pipeline.
- **CMS:** with `Optimizely.Cms.Odp`, register `services.AddCms().AddOptimizelyOdp(configuration)`
  and `app.UseOptimizelyOdp()` after `UseStaticFiles()`; settings live under `Optimizely:Odp`
  (`ApiBase`, `Instances:<name>:PrivateApiKey|PublicApiKey|Tracking:Sites`). Editors add the
  *Data platform > Audience Membership* criterion. Membership is a synchronous GraphQL call on a
  cache miss (60 s membership cache), and a failed call counts as "not a member": personalize
  for a bonus, never gate access on it. CMS 13 also needs `EPiServer.Cms.UI.VisitorGroups`.
- **Feature Experimentation:** `await user.fetchQualifiedSegments()` (returns `false` on
  failure), then `user.isQualifiedFor(segment)` or a decision; `optimizely.sendOdpEvent(action,
  type, identifiers, data)` sends an event. Needs JS SDK 6+ (5+ for the older Node/browser SDKs),
  C# and Java 4+, Python 5+. The datafile carries the ODP host and key only while an ODP
  audience is on a running rule.
- **Web Experimentation:** *Settings > Integrations > Real-Time Segments*. With *ODP • VUID* as
  the user ID, the ODP snippet loads before the Web snippet, and not async.

## Security, consent and PII

- **Keys:** the public key (the tracker ID) sends data and may be in the browser. The private
  key reads profiles and manages audiences: server-side only, from configuration, never
  committed. A revoked private key keeps working for 12 hours, so rotate it before you revoke.
  The docs disagree on which key GraphQL needs (the SDKs query audiences with the public key);
  use the key the integration's docs name, and keep profile reads on the private key.
- **Consent** belongs to each identifier, not to the profile. Send it with `zaius.consent` or
  `/v3/consent` when the user changes it; never infer opt-in.
- **Deletion:** `POST /v3/compliance/{gdpr|ccpa|lgpd}/delete`; data is gone within 30 days, and
  events for that person are dropped meanwhile.
- **PII:** mark PII fields in *Data Setup > Objects & Fields*. Send only fields an audience or
  a report uses; never put PII in an event `action`, an object key or a URL.

## Rate limits

- Events and objects: no published limit. Profiles and lists: 10 requests per second. On-site
  GraphQL: 500 per second. The over-limit response is not documented: back off on any 4xx or
  5xx from these endpoints, batch profile writes, and never call the profile API per page view.

## Testing

- Use a separate ODP instance for test, with its own tracker ID and keys in configuration;
  there is no self-service delete, so test data in production stays until support removes it.
- Unit-test the code that builds events and identifiers against a fake client; assert on the
  payload (identifiers present, no PII where it should not be).
- Watch a test run in *Settings > Event Inspector* (it records up to 15 minutes).

## Deploy and verify

- After a deploy, trigger one known event and confirm it in the Event Inspector, and check that
  the web tag loads once per page with the environment's tracker ID.
- For CMS audiences, open a page with an audience-based personalization as a member and as a
  non-member.

## Sources

https://docs.optimizely.com/data-platform/docs and https://docs.optimizely.com/data-platform/api
(the API reference), and the Feature and Web Experimentation docs for audience targeting. Hosts
and package versions move: re-check them before you rely on one.
