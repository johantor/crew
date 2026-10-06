---
name: frontend-server-rendered
description: Conventions for server-rendered frontends — a server template renders the page shell, with a client-side framework layered in as islands/widgets rather than a full SPA. The template language has its own skill (Razor: `frontend-razor`). Next.js/RSC is not covered here — crew's mode vocabulary treats Next.js as headless (see frontend-nextjs) even though it server-renders. Load when the repo's frontend mode is "server-rendered".
---

# Server-rendered frontend conventions

Confirm the actual setup from the repo first; follow its patterns over these defaults. The
shared principles below apply to any server template language. If the views are Razor
(`.cshtml`), also load `frontend-razor`.

Search the layouts yourself for the ODP web tag (`zaius`, `zaius-min.js`). If one
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
- **Styling** goes through the project's front-end build pipeline (SCSS or similar), per repo
  conventions.
