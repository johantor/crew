---
name: design-tokens
description: Reading a project's design tokens and reporting visual findings in token terms rather than raw pixels — where tokens live per system (CSS custom properties, Tailwind, SCSS, a tokens JSON, Figma variables), which of them survive to runtime, and how to map a measured value back to the token it should have been. Load when checking rendered UI against a design reference.
---

# Design tokens

A measured value is a symptom; the token is the fix. `font-size: 18px` tells an implementer
what you saw, `text-lg where the spec is text-xl` tells them what to change. Report both.

## Where the table lives

Read the token table **once per run**, from source — not per element (`context-discipline`).

- **CSS custom properties** — `:root {}` in a global stylesheet, or Tailwind v4's `@theme`.
  The only kind readable at runtime: `getComputedStyle(el).getPropertyValue('--space-3')`
  resolves them, and `getComputedStyle(document.documentElement)` enumerates the whole table.
- **Tailwind (v3)** — `tailwind.config.*` under `theme` / `theme.extend`. Utility classes
  compile to literal values, so the class list on the element is the token: `p-4` *is* the
  finding, and the class attribute is worth reading alongside the computed style.
- **SCSS / Less variables** — `$spacing-md`, `@brand-primary`. Compiled away entirely; nothing
  in the browser knows they existed. Grep the source for the declarations and match numerically.
- **A tokens file** — `tokens.json`, Style Dictionary output, a `design-tokens` package. The
  most authoritative source when present; prefer it over inferring the scale from usage.
- **Figma variables / styles** — the reference side of the comparison. A Figma value bound to a
  named variable is the spec's token; an unbound raw value in Figma is a design-side smell worth
  one line in the report.

## Mapping a measured value back

Match the measured value against the table **exactly**. Two failure modes to avoid:

- **Don't snap to the nearest token.** 15px against a 4pt scale is not "basically `space-4`" —
  it is off-scale, and saying so is the finding. Nearest-match reporting hides exactly the bug
  the token system exists to catch.
- **A value matching no token is itself a finding**, even when it matches the design. It means a
  hardcoded value that the next theme change will miss. Report it as off-scale, separately from
  spec mismatches, and don't inflate its severity — it is correct today.

Colors need normalizing before comparison: computed styles come back as `rgb()`/`rgba()` (or
`color()` in newer engines) whatever the source spelled, so convert both sides to one form
rather than diffing strings. `#FFF`, `#ffffff`, and `rgb(255 255 255)` are one color.

## When there is no token system

Say so once and report raw values. Inventing a scale from observed usage produces confident
nonsense — three components sharing a padding is not evidence of a token.
