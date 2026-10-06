---
name: frontend-server-rendered
description: Conventions for server-rendered frontends — a server template renders the page shell, with a client-side framework layered in as islands/widgets rather than a full SPA. Covers Razor (.NET/Optimizely) and Blade (Laravel). Next.js/RSC is not covered here — crew's mode vocabulary treats Next.js as headless (see frontend-nextjs) even though it server-renders. Load when the repo's frontend mode is "server-rendered".
---

# Server-rendered frontend conventions

Confirm the actual setup from the repo first; follow its patterns over these defaults. The
shared principles below apply regardless of which server template language the project
uses; load the subsection matching the project's server template language (Razor or Blade)
for the specifics.

Search the layouts yourself for the ODP web tag (`zaius`, `tag.odp.optimizely.com`). If one
loads it, also load `optimizely-odp`.

## Shared principles

- **Client framework as islands:** mount components into server-rendered DOM nodes; pass
  initial data via `data-*` attributes or an embedded JSON island — don't re-fetch data the
  page already has.
- **Progressive enhancement:** usable server-rendered first; the client framework layers on
  top.
- **State:** keep client-side state scoped to its island; don't SPA-ify the whole page.
- **Template ownership is concern-split:** the *markup/DOM* inside the server template
  (element structure, classes, ARIA, presentation) is the frontend agent's; the server-side
  logic (data binding, control flow, data access) is the backend agent's. Coordinate the
  contract rather than crossing into each other's concern.

## Razor (.NET / Optimizely)

Render content through the CMS pipeline (display templates, `IContentRenderer`, partials),
not hardcoded markup; keep logic out of views. Styling via SCSS through the .NET/front-end
build pipeline per repo conventions.

## Blade (Laravel)

Render through Blade components/layouts (`@component`, `@include`), not hardcoded markup;
keep business logic in controllers/view models, not `.blade.php` files.
