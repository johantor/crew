---
name: optimizely-ocp
description: Optimizely Connect Platform (OCP) app conventions — the `app.yml` manifest and file layout, functions and global functions, jobs (prepare and perform, state, the 60-second loop, Quartz cron), lifecycle hooks and OAuth, settings forms and the settings, secrets and key-value stores, data sync sources and destinations, Opal tools on OCP, the `ocp` CLI, versions and app review, testing. Load when a project has an OCP `app.yml`, or references `@zaiusinc/app-sdk`, `@optimizely/ocp-cli`, `@optimizely/ocp-cli-v2`, `ocp-app-sdk validate` or `@optimizely-opal/opal-tool-ocp-sdk`.
---

# Optimizely Connect Platform

OCP builds and hosts Node/TypeScript apps that move data between Optimizely products (CMS, Graph,
CMP, ODP) and third parties. The Zaius name remains: `@zaiusinc/*` packages, `function.zaius.app`.

## Detect

- `app.yml` at the root with `meta.app_id`, `runtime` and `functions:`/`jobs:`, beside
  `forms/settings.yml`, and `src/lifecycle/Lifecycle.ts`.
- `@zaiusinc/app-sdk` (3.x needs `runtime: node22`; 2.x is its `v2-latest` tag; `@zaius/app-sdk`
  in some docs is the old name) with its peer `@zaiusinc/node-sdk`, the ODP client. `node-sdk`
  without `app-sdk` is an ODP integration, not an OCP app: load `optimizely-odp` only.
- A `validate` script ending in `ocp-app-sdk validate`; the `ocp` CLI (v2 `@optimizely/ocp-cli-v2`
  or its install script, v1 `@optimizely/ocp-cli`), keyed by `~/.ocp/credentials.json`.
- `runtime: node22-cms-ext` with `ui_extensions:`: a CMS UI extension app (beta); read its page.
- Neighbours: `backend-node` (the stack), `tests-vitest` (the template's runner), `optimizely-odp`
  (ODP data and the `z` client), `optimizely-opal` (the Opal tool contract).

## Layout and manifest

- `entry_point` is both the file name and the exported class: `entry_point: HandleEvent` loads
  class `HandleEvent` from `src/functions/HandleEvent.ts` (jobs from `src/jobs/`, destinations
  from `src/destinations/`). The lifecycle has no entry: OCP loads `src/lifecycle/Lifecycle.ts`.
- `forms/settings.yml` and `assets/` (`icon.svg`, `logo.svg`, `directory/overview.md`) sit at the
  root. *Form basics* says `src/forms/`; the SDK validator and the reference apps use the root.
- Schemas: `src/schema/` (ODP fields, prefixed with the app ID), `src/sources/schema/`,
  `src/destinations/schema/`. The template's `build` copies `app.yml` and `src/**/*.yml` into
  `dist/`, which the validator and runtime read: keep that step.
- `meta.version` is semver plus at most one tag: `-dev[.n]`, `-beta[.n]` or `-private`.
- `environment:` lists app-wide variables, each named `APP_ENV_*`. Values come from `.env`
  (`.env.<region>` overrides it, not with `availability: [all]`), upload with each version, and
  read as `process.env.APP_ENV_X`. A changed value needs a new version.

## Functions

- A function is a public webhook: extend `Function`, implement `perform(): Promise<Response>`,
  return `new Response(status, body?)`.
- `this.request` has `path`, `params` (query), `body` (raw `Uint8Array`), `bodyJSON` (parsed on
  read; bad JSON throws, so return 400) and `headers`, a `Headers` object: `headers.get('x-name')`.
- The default URL `https://function.zaius.app/<app_id>/<function>/<uuid>` (US) is unique per
  install. Read it with `functions.getEndpoints()` and register it with the source in `onInstall`,
  or in `onFinalizeUpgrade` for a function new in that version. `installation_resolution`
  (`HEADER`, `QUERY_PARAM`, `JSON_BODY_FIELD`) gives one fixed URL routed by the public tracker ID.
- **Global functions** (`global: true`, extend `GlobalFunction`) have no install context and only
  `storage.sharedKvStore`, and OCP runs the one in the highest deployed release, whatever version
  an account runs: keep them backward compatible. Developers cannot see their logs.
- A function has a maximum run time (no number is published) and hundreds run at once: hand long
  work to `jobs.trigger(name, params)`, and change shared state with `patch`, never `get` + `put`.
- **Opal tools:** `opal_tool: true` and a class extending `ToolFunction` or `GlobalToolFunction`
  (`@optimizely-opal/opal-tool-ocp-sdk`) with `@tool(...)` methods. The SDK checks parameters and
  the Opti ID token, not a custom `authRequirements` provider: check it in the handler. Contract:
  `optimizely-opal`.

## Jobs

- Extend `Job`. `prepare(params, status?, resuming?)` runs at the start and again on a resume
  (then return the `status` it got). `perform(status)` loops until it returns `complete: true`.
  Keep the phase in `status.state`, as a state machine.
- Keep each `perform` under 60 seconds: a longer one can be killed without warning, and the job
  resumes from the last returned state. Save state before a long call; wait with
  `await this.sleep(ms, { interruptible: true })` or `this.performInterruptibleTask(...)`.
- `Batcher` (default 100 items) buffers writes: `flush()` before `perform` returns.
- A failed job retries once with the same `jobId`: make each step idempotent.
- `cron:` is Quartz: six fields from seconds, with `?` in day-of-month or day-of-week
  (`0 0 0 ? * *` is daily at midnight). A five-field Unix cron fails validation.

## Lifecycle and OAuth

- `Lifecycle` implements `onInstall`, `onSettingsForm`, `onUpgrade`, `onFinalizeUpgrade`,
  `onUninstall`, `onAuthorizationRequest` and `onAuthorizationGrant`: the validator requires all
  seven (a docs table lists five). `onAfterUpgrade` and `canUninstall` are optional.
- `{ success: false }` from `onInstall` cancels the install, but schema changes stay. `onUpgrade`
  runs before functions migrate, `onFinalizeUpgrade` once new URLs exist, `onAfterUpgrade` last
  (start one-off jobs there). `fromVersion` need not be the last release, and a failure rolls back:
  make upgrade steps idempotent. `onUninstall` removes the app's webhooks and tokens at the source.
- `onSettingsForm(section, action, formData)` returns `LifecycleSettingsResult` (`addToast`,
  `addError(field, message)`, `redirectToSettings`), not the `Response` an older page shows.
  Validate, then `await storage.settings.put(section, formData)` (a docs sample drops the `await`).
- **OAuth:** an `oauth_button` calls `onAuthorizationRequest`, which returns
  `result.redirect(providerUrl)` with `functions.getAuthorizationGrantUrl()` as the return URL.
  `onAuthorizationGrant(request)` checks the response, exchanges the code, puts the tokens in
  `storage.secrets` and returns `new AuthorizationGrantResult(section)`.

## Storage

- `storage.settings` backs the form, per section, and the form reads it back: collect credentials
  in `type: secret` fields. `storage.secrets` holds tokens the form never shows. Only these two
  (AES-256) may hold credentials; OCP deletes both on uninstall.
- `storage.kvStore` (per install, about 400 KB a record, `{ ttl }`, `patch`, `increment`, lists,
  sets) and `storage.sharedKvStore` (all installs: prefix keys by install) hold no secrets.
- Each call is a network call: read once per run into a local. Importing `storage` at module
  level is fine: its getters resolve the current install on each access. Never keep a resolved
  store (`const s = storage.settings`) at module level: it stays bound to the context it was
  first read in. Store nothing outside OCP or on disk.

## Data sync sources and destinations

- **Source:** a `sources:` entry (`description`, `schema`), then `await sources.emit(name, {data})`
  from any function or job; a delete emits the primary key with `_isDeleted: true`.
- **Destination:** `destinations: { <name>: { entry_point, schema, supports_delete } }` and a
  `Destination<T>` class: `ready()`, and `deliver(batch)` returning `{ success, retryable }` (the
  typings' spelling; the docs' samples say `retriable`). OCP retries a retryable batch up to three
  times and drops deletes without `supports_delete: true`. Users build syncs in *Sync Manager*.

## Security

- No secret in `app.yml`, source, forms or logs. App-wide values go in a git-ignored `.env`:
  `ocp app prepare` packages what Git does not ignore, and a release's code goes to a GitHub
  review repository. Per-install credentials go in the settings or secrets store.
- Customers read the app's logs in its *Troubleshooting* tab: log through `logger`, not `console`,
  and never a token or PII. Send data only to the integration's own target.
- Function URLs are public, and fixed URLs route on the public tracker ID. Where the source signs
  its webhooks, verify the signature over the raw `this.request.body` with a timing-safe compare
  and return 401 before parsing; neither OCP nor its Shopify reference app does it for you.
- OAuth: ask for the fewest scopes, and send and check a `state` value.

## Testing

- `yarn test` (Vitest in the template) runs in `ocp app validate`, `ocp app prepare` and the OCP
  build; a failing test blocks the publish. Load `tests-vitest`.
- Outside OCP the stores are in memory: use them, and call `resetLocalStores()` after each test.
  `jobs.*`, `functions.getEndpoints()` and `getAuthorizationGrantUrl()` throw locally: mock them.
- Test a function with a real `new Request('POST', '/', {}, [['x-sig', sig]], Buffer.from(json))`;
  a job with `prepare`, then `perform` until `complete`, and once from a mid-run status.
- `ocp dev` (http://localhost:3000) runs forms, functions, jobs and stores, not OAuth,
  `onFinalizeUpgrade`, `onAfterUpgrade` or cron. Git-ignore its `.ocp-local/`.

## Deploy and verify

- `ocp app validate`, `ocp app prepare` (needs a Git repo; uploads the `.env` values), `ocp
  directory publish <app_id>@<version>`, `ocp directory install <app_id>@<version> <trackerId>`.
  `ocp app prepare --bump-dev-version --publish` does a dev round in one step. Validate and
  prepare may offer to upgrade the SDK packages: expect a `package.json` diff.
- `-dev` runs only in your own accounts, skips review, and auto-upgrades installs on its tag.
  `-beta`, `-private` and plain versions go through app review (one to two business days, on
  GitHub): fix on `-dev`, then prepare the same version again; a new number opens a new review.
- Released minor and patch versions auto-upgrade installs; a major waits for the customer. At most
  2 majors, 3 minors per major, 5 `-dev`, 5 `-beta` and 2 `-private` run at once;
  `ocp directory unpublish` frees a slot and uninstalls that version everywhere.
- Verify with `ocp directory list-installs <app_id>`, `ocp directory list-functions <app_id>
  <trackerId>`, `ocp jobs trigger <app_id> <job> <trackerId>` and `ocp app logs` (`--jobId`,
  `--buildId`). The reference also spells them camelCase (`listFunctions`): check `ocp <ns> -h`.

## Sources

https://docs.optimizely.com/optimizely-connect-platform/docs (old docs.developers.optimizely.com
links redirect there), the published `@zaiusinc/app-sdk` 3.5.1 and `@optimizely/ocp-cli` 1.4.3,
and github.com/ZaiusInc/shopify-sync-source-reference-ocp-app. Re-check versions and CLI names.
