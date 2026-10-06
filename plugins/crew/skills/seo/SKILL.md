---
name: seo
description: "Search-engine optimization for a public website: titles and meta descriptions, canonical URLs, robots rules, hreflang for locales, structured data (JSON-LD), Open Graph, sitemaps, headings and link text, and what a headless or CMS-driven site gets wrong. Load when you write or review page metadata, routing, page templates or copy on a public site."
---

# SEO

A page is found only when a crawler can fetch it, understand it and pick the right URL for it.
Most SEO defects are a wrong default, not a missing trick.

## Per page

- **Title**: unique per page, the page's subject first and the site name last, about 50–60
  characters before a search result cuts it.
- **Meta description**: unique, a summary that makes someone click, about 150–160 characters.
  Search engines may rewrite it; a missing one is still a defect.
- **One `h1`** that names the page, and headings in order (`h2` under `h1`, no skipped level).
  Headings are structure, not styling.
- **Link text** names the target ("Pricing for teams", not "Read more"). An image link's `alt`
  is its link text.
- **Image `alt`** says what the image shows; a decorative image has `alt=""`.
- **Language**: `<html lang>` matches the page's locale.

## Indexing

- **Canonical**: every indexable page has a `<link rel="canonical">` to its own clean,
  absolute URL (no tracking parameters, no session IDs, one trailing-slash form). Filter,
  sort and paging variants point to the right canonical, never all to page 1.
- **Robots**: `noindex` only on purpose (search results, preview, thank-you pages, staging).
  A preview or staging host must never be indexable, and the production host must never ship
  the staging `noindex`. `robots.txt` blocks crawling, not indexing: a page that must stay out
  of search needs `noindex` and must stay crawlable.
- **Status codes**: a missing page returns 404 (not a 200 "not found" page); a moved page
  returns 301 to its new URL, in one hop.
- **Sitemap**: lists only canonical, indexable, 200 URLs, with `lastmod` from the content's
  real change date. A CMS generates it from published content, never from a static file.

## Locales

- **hreflang**: each locale variant lists every variant, itself included, with absolute URLs,
  plus `x-default`. The links are reciprocal: a one-way link is ignored.
- One URL per locale (`/sv/…`, `sv.example.com`), never a locale chosen by cookie or
  `Accept-Language` on the same URL.

## Structured data and sharing

- JSON-LD in the page, matching visible content: `Organization`, `BreadcrumbList`, `Article`,
  `Product` with `Offer`, `FAQPage` only where the page shows the questions. Markup that
  claims what the page does not show is a policy violation, not a bonus.
- Open Graph and Twitter tags: `og:title`, `og:description`, `og:image` (absolute URL, about
  1200×630), `og:url` equal to the canonical.

## Headless and CMS-driven sites

- Metadata must be in the server-rendered HTML. A title set only in client JavaScript is seen
  late or not at all.
- Editor fields drive SEO: give each page type a title, description, `noindex` and share-image
  field with sensible fallbacks (page name → title, teaser → description), and never index
  the fallback as a duplicate.
- Next.js: use the `metadata` export or `generateMetadata`, `alternates.canonical` and
  `alternates.languages`; generate `sitemap.ts` and `robots.ts` from the content source.
- Optimizely: a page's URL comes from its route segment; a rename changes the URL, so the old
  URL needs a redirect. Never index the edit or preview host.

## Review checks

Fetch the HTML as a crawler gets it (no JavaScript) and check: title, description, canonical,
robots, hreflang, `h1`, JSON-LD validity, and the status code. A changed route needs a
redirect from the old URL.
