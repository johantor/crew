---
name: accessibility
description: "Web accessibility to WCAG 2.2 level AA, the bar the European Accessibility Act (EN 301 549) sets for public websites and e-commerce in the EU: semantics, names and roles, keyboard and focus, contrast, forms and errors, motion, and how to test it. Load when you build, specify or review markup, components, styles or copy."
---

# Accessibility

The target is **WCAG 2.2 level AA**. In the EU, the European Accessibility Act applies to
e-commerce and many consumer services from 28 June 2025; its harmonized standard, EN 301 549,
incorporates WCAG 2.1 AA, and 2.2 AA is a superset of it. Treat an AA failure as a defect.

## Semantics first

- Use the native element: `<button>` for an action, `<a href>` for navigation, `<label>` for a
  field, `<table>` for tabular data, a list for a list. ARIA fixes what HTML cannot express; a
  wrong role is worse than none.
- A way to bypass repeated blocks (2.4.1): landmarks (`<main>`, `<header>`, `<nav>`,
  `<footer>`, each `<nav>` labelled when there are several), headings, or a skip link.
- Headings and lists in the markup match the visual structure (1.3.1).
- Recommended, not required by WCAG (report as a Warning): a skip link, one `h1` per page, and
  no skipped heading level.
- `<html lang>` is set, and a passage in another language has its own `lang`.

## Names and alternatives

- Every control has an accessible name that matches its visible label (2.5.3). An icon-only
  button gets `aria-label` or visually hidden text.
- Images: `alt` says what the image conveys; decorative images get `alt=""`. A chart or diagram
  needs its data in text too.
- Video has captions; audio has a transcript.

## Keyboard and focus

- Everything works with the keyboard alone, in a logical order, with no trap.
- Focus is always visible (2.4.7) and not hidden behind a sticky header (2.4.11, new in 2.2).
- A dialog moves focus in, keeps it in, closes on Escape and returns focus to its trigger. A
  menu or disclosure sets `aria-expanded`.
- Never remove an outline without a visible replacement.

## Visual

- Contrast: text 4.5:1, large text (24px, or 18.66px bold) 3:1, UI parts and focus indicators
  3:1 (1.4.3, 1.4.11).
- Never convey meaning by color alone (1.4.1).
- Reflow at 320 CSS px without horizontal scrolling (1.4.10); text resizes to 200% (1.4.4).
- Target size at least 24×24 CSS px, or enough spacing (2.5.8, new in 2.2). Exempt: a link
  inline in text, a browser-default control, a target with an equivalent that passes, and a
  size that is essential.
- Respect `prefers-reduced-motion`; nothing flashes more than 3 times a second; auto-playing
  motion longer than 5 seconds can be paused.

## Forms

- Each field has a visible `<label>`; group related fields with `<fieldset>`/`<legend>`.
- Use `autocomplete` tokens for personal data (1.3.5).
- An error names the field and says how to fix it, in text, linked to the field with
  `aria-describedby`; move focus to the first error or an error summary on submit.
- Never ask for the same information twice in one process (3.3.7), and a login offers an
  option without a cognitive test such as solving a puzzle (3.3.8). Both are new in 2.2.
- A status message (added to cart, results updated) is announced with a live region
  (4.1.3).

## CMS content

Editors create much of the content. Give an image field an alt-text field (required unless
marked decorative), keep heading levels in a rich-text editor's options, and make a block's
heading level configurable when it can sit at different depths.

## Testing

- Automated checks (axe-core through Playwright or Cypress, Lighthouse) find a minority of
  issues. Use them as a floor, not a pass.
- Then check by hand: keyboard-only through the changed flow, zoom to 200% and 400%, and the
  accessibility tree (names, roles, states) through the browser's tools or a browser MCP.
- Report each finding with its success criterion number (`WCAG 1.4.3`).
