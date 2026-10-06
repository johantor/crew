---
name: frontend-nextjs
description: Next.js frontend stack conventions — App Router, Server/Client Components, data fetching (e.g. Optimizely Graph), npm build specifics. Load when the resolved frontend stack is nextjs.
---

# Frontend: Next.js

You are working in a Next.js frontend: App Router, React Server Components (RSC) and Client
Components, and data fetching from the project's headless CMS/API (e.g. Optimizely Graph).
`@optimizely/react-sdk` or `@optimizely/optimizely-sdk` means Feature Experimentation: load
`optimizely-experimentation`.

## Server/client split

- **Server Components** run on the server: data fetching, no browser APIs, no event handlers.
  Prefer them by default.
- **Client Components** (`"use client"`) are for interactivity — state, effects, browser APIs,
  event handlers. Keep the client boundary as small as possible; push data fetching to the
  server.

## Route-handler ownership

Route handlers (`app/**/route.ts`) are server logic that happens to live inside the frontend
app directory — that makes them **backend's lane by concern**, not yours, the same way Razor's
`@functions`/`@code` blocks are backend's inside a `.cshtml` file you otherwise own the markup
of. Don't implement route-handler business logic yourself; coordinate the data contract with
backend. `lane-guard.sh` enforces this by path when lanes are directory-based (same-language
stacks); don't rely on that alone — the rule holds regardless of enforcement mode.

## Build

Watch/dev/serve forms that never terminate: `npm run dev`, `next dev`. The lock signature is
`EBUSY`/`EPERM`/`EACCES`, or a locked `.next`/bundler cache.
