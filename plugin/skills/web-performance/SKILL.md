---
name: web-performance
description: "Web performance for a public website: Core Web Vitals (LCP, INP, CLS) and their thresholds, images and fonts, JavaScript cost, HTTP and CDN caching, server and CMS rendering cost, and Optimizely Graph query cost. Load when you build or review pages, components, images, caching, data fetching or queries on a public site."
---

# Web performance

Measure, then change. A guess about what is slow is usually wrong, and every optimization
costs code.

## Core Web Vitals

Google judges a page at the 75th percentile of real visits, mobile and desktop apart:

| Metric | Good | Poor | Measures |
|---|---|---|---|
| LCP (Largest Contentful Paint) | ≤ 2.5 s | > 4 s | loading of the main content |
| INP (Interaction to Next Paint) | ≤ 200 ms | > 500 ms | response to input |
| CLS (Cumulative Layout Shift) | ≤ 0.1 | > 0.25 | visual stability |

INP replaced FID in March 2024. Lab tools (Lighthouse, a DevTools trace) cannot measure INP
from real users; use field data (CrUX, a RUM library) where the project has it, and Total
Blocking Time as the lab proxy.

## LCP

- The LCP element (usually the hero image or heading) must be in the server HTML, never
  injected by client JavaScript.
- The LCP image is not lazy-loaded; give it `fetchpriority="high"` and preload it when CSS
  sets it as a background.
- Serve images in AVIF or WebP at the rendered size, with `srcset`/`sizes`. Use an image
  service (a CDN resizer, `next/image`) instead of full originals.
- Keep TTFB low: cache the HTML (below), and never block render on a third-party script.

## CLS

- Every image, video, iframe and ad slot has `width`/`height` or an `aspect-ratio`.
- Fonts: `font-display: swap` or `optional`, preload the one or two fonts above the fold, and
  use a size-matched fallback (`size-adjust`).
- Never insert content above existing content after load (cookie banners overlay, they do not
  push).

## INP and JavaScript

- Ship less JavaScript: render on the server, hydrate only interactive parts (React Server
  Components, islands), split by route, and load third-party tags after interaction or idle.
- Break a long task (> 50 ms) into smaller ones; keep an event handler's own work small and
  defer the rest.
- A tag manager and an A/B-testing snippet are often the largest scripts on the page: measure
  them, and load experiment code before render only where a flicker would be worse.

## Caching

- Static assets: content-hashed file names with `Cache-Control: public, max-age=31536000,
  immutable`.
- HTML from a CMS: cache published pages at the CDN (`s-maxage` with
  `stale-while-revalidate`) and purge or revalidate on publish. Never cache a preview, an
  edit-mode response or a response with a user's data in a shared cache.
- Next.js: prefer static or ISR rendering with tag-based revalidation from the CMS webhook
  over rendering every request.
- Optimizely CMS 12 and 13: cache objects in `ISynchronizedObjectInstanceCache` with a
  dependency on the content cache key (`IContentCacheKeyCreator`); without it, a publish
  leaves the entry stale.

## Server and query cost

- Fetch only the fields a page renders. Avoid N+1 loads: one query or batch for a listing,
  never one per item or block.
- Optimizely Graph: select only rendered fields, page with `limit`, avoid deep reference
  expansion, and use the CDN cache and stored queries. The `optimizely-graph` skill holds its
  limits and caching headers; load it for Graph work.
- Commerce: price and inventory lookups per listing item are the usual N+1.

## Review checks

Compare before and after on the changed page: a DevTools performance trace or Lighthouse run
(mobile, throttled), the network waterfall (count, bytes, cache headers), and the LCP element.
Report a regression as a number and the metric it moves.
