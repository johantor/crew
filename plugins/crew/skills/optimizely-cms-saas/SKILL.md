---
name: optimizely-cms-saas
description: Optimizely SaaS CMS conventions — content types defined in code with `@optimizely/cms-sdk` and pushed with `@optimizely/cms-cli`, Visual Builder experiences, sections, elements and display templates, live preview and on-page editing in a Next.js front end, webhooks, environments, keys. Load when a project has `optimizely.config.mjs` or a CMS URL on `*.cms.optimizely.com` and no `EPiServer.CMS*` package. Load `optimizely-graph` too.
---

# Optimizely SaaS CMS

SaaS CMS is the hosted, headless edition of Optimizely CMS. There is no .NET host to change:
the repo is a front end (usually Next.js) that defines content types in code, reads content
from Optimizely Graph, and renders preview for the editors. Graph itself (queries, keys,
caching, sync) is `optimizely-graph`.

## Detect

- `optimizely.config.mjs` exporting `buildConfig({ components: [...] })`, with
  `@optimizely/cms-sdk` and `@optimizely/cms-cli` in `package.json`.
- A CMS URL of the form `https://app-<id>.cms.optimizely.com` (`OPTIMIZELY_CMS_URL`), and a
  management API at `https://api.cms.optimizely.com`.
- No `*.csproj` and no `EPiServer.CMS*` package. The SDK and the CLI also work against CMS 13
  (PaaS), so the SDK alone does not prove SaaS: only the `*.cms.optimizely.com` URL does. A
  front end whose CMS is CMS 13 uses the SDK sections below (content types, Visual Builder,
  preview); its environments, keys and deploy follow `optimizely-cms13`.

## Content types in code

- Define each type with `contentType({ key, displayName, baseType, properties })` and a shared
  property set with `contract({ key, displayName, properties })`. Base types: `_page`,
  `_experience`, `_section`, `_component`, `_image`, `_media`, `_video`, `_folder`.
- An element (for Visual Builder) is a `_component` with `compositionBehaviors:
  ['elementEnabled']`; `'sectionEnabled'` makes it usable as a section.
- Property types: `string`, `richText`, `boolean`, `integer`, `float`, `dateTime`, `url`,
  `link`, `binary`, `json`, `content`, `contentReference`, `array`, `component`. Each `content`
  or `contentReference` property needs exactly one of `allowedTypes`/`restrictedTypes`, or the
  push fails.
- **The key is the identity.** It must start with a letter and hold only letters, digits and
  `_`. Never change or reuse a key.
- Push with the CLI: `config push` (add `--dryRun` first), `config pull` to bring the CMS state
  back into code. Credentials: `OPTIMIZELY_CMS_CLIENT_ID` and `OPTIMIZELY_CMS_CLIENT_SECRET`.
- A push that would drop stored data is refused. `--force` overrides it and loses the data of a
  removed or changed property: never add `--force` to make a push pass; tell the operator what
  it would drop.
- After a push, the Graph schema changes: regenerate types and re-check queries
  (`optimizely-graph`).

## Visual Builder

- An experience (`_experience`) holds a composition: render it with
  `<OptimizelyComposition nodes={content.composition.nodes ?? []} />`. A section (`_section`)
  renders its grid with `<OptimizelyGridSection nodes={content.nodes} />`.
- Register types with `initContentTypeRegistry([...])` and components with
  `initReactComponentRegistry({ resolver: { Key: Component } })`; render any content with
  `<OptimizelyComponent content={...} />` (`@optimizely/cms-sdk/react/server`). One registry, one
  mapping per key.
- **Display templates** (`displayTemplate({ key, displayName, baseType | contentType | nodeType,
  settings })`) carry editor choices such as alignment or color. Read them from
  `displaySettings`; do not add content properties for the same choice.
- Keep sections and elements self-contained. Layout belongs to the grid, not to fields.

## Preview and on-page editing

- In the CMS, *Settings > Applications*: set the host name and the live preview URL, and select
  *Use Preview Tokens*. Preview URL tokens include `{key}`, `{version}`, `{locale}`,
  `{context}`.
- A preview route (`app/preview/page.tsx`) calls `client.getPreviewContent(searchParams)`, which
  reads `preview_token`, `key`, `ver`, `loc` and `ctx`. The token lives 5 minutes and stays
  server-side.
- Load `/util/javascript/communicationinjector.js` from `OPTIMIZELY_CMS_URL` and render
  `<PreviewComponent />` (or `<NextPreviewComponent />`), so the page refreshes on
  `optimizely:cms:contentSaved`.
- Mark editable output with `getPreviewUtils(content).pa('property')`; it emits the
  `data-epi-edit` attributes in edit mode only.
- The preview route is always dynamic and never cached.

## Webhooks and revalidation

- Register a Graph webhook (`POST https://cg.optimizely.com/api/webhooks`, Basic or HMAC auth)
  for `doc.updated`, `doc.expired` and `bulk.completed`, pointing to an API route.
- On `doc.updated`, resolve the item's URL from Graph and `revalidatePath` it; on a bulk delete,
  revalidate the layout. Put an unguessable segment or a check in the webhook URL, since anyone
  can POST to the route.
- `next dev` does not cache: test revalidation against a production build.

## Environments

- A subscription has three instances: production, QA/UAT and development. Keep one set of
  environment variables (CMS URL, Graph keys, API client) per instance and deploy target; never
  point a QA front end at production keys.
- A host name change needs a Graph full sync before URLs resolve.

## Security

- Public: the Graph single key (published content only). Everything else is server-side: the
  Graph secret, the CMS client ID and secret, the webhook secret, the preview token.
- The SDK refuses HMAC auth in a browser; do not work around it.
- The management API is rate-limited (100 requests per 10 seconds per IP). A script that pushes
  or deletes in bulk waits on a 429.

## Testing

- Unit-test components with fixed content objects of the generated types; render through
  `OptimizelyComponent` with the real registry, so a missing mapping fails the test.
- Run `config push --dryRun` in CI against a non-production instance, so a breaking type change
  shows up before merge.

## Deploy and verify

- Targets: Optimizely Frontend Hosting (Next.js or Astro, deployed with the EpiCloud PowerShell
  module as a `<name>.head.app.<version>.zip` with exactly one lock file), Vercel or Netlify.
- Push content types to an instance before the front end that needs them deploys there.
- After a deploy, open a page in the CMS preview, change a field, and confirm the edit
  appears; then publish and confirm the public page updates through the webhook.

## Sources

https://docs.optimizely.com/cms-saas/docs and https://github.com/episerver/content-js-sdk
(`docs/`). The SDK changes quickly between major versions: check the installed version's docs
before you rely on a method name.
