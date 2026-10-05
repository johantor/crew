---
name: frontend-headless
description: Conventions for decoupled/headless frontends — a React SPA (or Next.js) consuming Optimizely's Content Delivery API / Optimizely Graph (GraphQL) rather than Razor server rendering. Use for tasks involving a headless/decoupled Optimizely frontend, Content Delivery API or Optimizely Graph, or a React/Next.js SPA against a CMS. Load when the repo's frontend mode is "headless".
---

# Headless frontend conventions
Confirm the actual setup from the repo first (framework, data source, fetch client); follow its patterns over these defaults. If the data source is Optimizely Graph, also load `optimizely-graph`.

- **Data layer:** fetch content from the content API via a typed, centralized client; never hardcode CMS-owned content.
- **Server vs UI state:** fetched/server state in a data-fetching layer (RTK Query/React Query) with caching + loading/error handling; only genuine UI state in Redux.
- **Content-type → component:** render blocks via a resolver/registry with one clear mapping.
- **Preview/edit:** preserve Optimizely preview/on-page-edit if present (preview tokens, draft content).
- **Routing/states:** client-side routing; handle loading/empty/error/404 explicitly.
- **SSR/SEO:** respect the repo's Next.js strategy (SSR/SSG/ISR); don't mix paradigms.
- No Razor/`.cshtml`. Coordinate the data contract with the backend agent.
