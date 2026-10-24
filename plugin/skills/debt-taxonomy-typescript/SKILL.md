---
name: debt-taxonomy-typescript
description: TypeScript / JavaScript suppression mechanisms, safe-removal recipes, npm/pnpm/yarn package-manager variance, and upgrade-tier examples for crew's debt lane. Covers any JS/TS project — React frontend or Node backend/CLI. Apply when stack detection (debt-taxonomy) finds a JS/TS project.
---

# Debt taxonomy — TypeScript / JavaScript

Apply this skill when `debt-taxonomy` stack detection finds a JS/TS project (`package.json`,
`tsconfig.json`, `.eslintrc*`, `biome.json`) — this covers any JavaScript/TypeScript code,
whether a React frontend or a Node backend/CLI. The React-specific rows below apply only when
React is present. The rubric, the justified-suppression filter, the blast-radius gate and the
upgrade workflow are in the core skill; this skill supplies the JS/TS rows they consume.

## Suppression mechanisms

One row per mechanism: its scope, where a keep-decision lives, what a grep-only pass reads as
"likely stale" (audit's `stale` scope never compiles — `/crew:debt` proves a candidate with a
lint or `tsc --noEmit` pass), and how a worker removes it. Most JS/TS mechanisms have a native
justification slot, so no crew-specific syntax is needed.

| Mechanism | Scope | Justification slot | Stale signal (grep-only) | Removal |
|---|---|---|---|---|
| `// eslint-disable-next-line <rule>` | Next line | ESLint's `--` description (v7+): `// eslint-disable-next-line no-explicit-any -- vendor payload is genuinely untyped` | The next line no longer contains the rule's syntactic trigger (`no-explicit-any` over a line with no `any`; `no-unused-vars` over an identifier referenced elsewhere in the file) | Delete the comment; re-lint the file |
| `// eslint-disable <rule>` … `// eslint-enable` | Block | The same `--` description on the `disable` | The surrounded block has no occurrence of the rule's trigger | Delete both markers |
| `/* eslint-disable */` (no rule) | File | **None** — file-wide, nothing to attach a per-rule reason to; project policy | Not a candidate from grep alone — covers every rule; needs a lint pass | Expand to **diagnostic count** before gating; replace with targeted per-line disables only where needed, then remove the rest |
| `// biome-ignore lint/category/rule: reason` | Next line | The `reason`, **required** by biome: `// biome-ignore lint/style/noVar: emitted by codegen` | The next line no longer contains the rule's trigger. A meaningful `reason` may still be class 1 — flag, don't assume | Delete the comment; re-lint |
| `@ts-ignore` | Next line | Trailing text after the directive | The next line has no type-error shape (no member access, call or JSX). Riskier than `@ts-expect-error`: removal does not self-report when stale, so `/crew:debt` verifies with `tsc --noEmit` | Worst kind — it suppresses **all** errors on the line, so removal may surface several; enumerate them first. Prefer `@ts-expect-error` if one specific error remains |
| `@ts-expect-error` | Next line | Trailing text after the directive | **Always a candidate**, whatever its text: TypeScript reports an unused directive as an error, so a stale one self-proves. Rank these first | Delete it; if the error is still real it is now explicit. **Always safe to attempt** |
| `it.skip` / `test.skip` / `xit` / `xdescribe` | Test | N/A — never excluded (core: skipped tests) | Never a candidate | Class 4: the user decides |
| `tsconfig.json` `"strict": false` or a disabled check (`noImplicitAny`, `strictNullChecks`) | Project | **None** — config; project policy | Not a candidate | Tier 2 — outline only; flipping these surfaces a flood of errors |
| ESLint `rules: { "rule": "off" }` in config | Project | **None** — config; project policy | Not a candidate | Like a blanket disable — expand to **diagnostic count** before gating |

## Behavior sensitivity (which rules need tests, not just lint)

Tag every JS/TS finding before delegating (see core `debt-taxonomy`):

**Behavior-sensitive** — fixing these moves/reorders/adds runtime logic; acceptance gate
**must be tests-green**, and with no test suite configured the orchestrator warns and requires
acknowledgement:
- `react-hooks/rules-of-hooks` — moving a hook out of a conditional/loop changes *when and how often it runs*. This is a structural refactor (lift state, split component, map a loop to child components), not a comment deletion — rubric class 3, behavior-sensitive.
- `react-hooks/exhaustive-deps` — adding a missing dependency can change effect timing or cause re-render loops. Never just append the dep to silence it; understand why it was omitted.
- Any suppression whose removal forces a logic change (not a type change).

**Behavior-preserving** — type-only or cosmetic; "tsc/eslint clean" is a sufficient gate:
- `@typescript-eslint/no-explicit-any`, `no-unused-vars`, unused `@ts-expect-error`, import ordering, formatting rules.

## TypeScript notes

- `any` introduced to silence `no-explicit-any`: usually rubric class 2–3 (replace with a real type or `unknown` + narrowing).
- After edits, run the project's **own** lint/typecheck on the touched files only — `tsc --noEmit` for the project, or the configured `lint` script scoped to the changed paths. Capture output to a file and grep (`context-discipline`).

## Package-manager variance

Detect by lockfile, then update `package.json` **and commit the matching lockfile** in the same batch.
These are the concrete commands the core `debt-taxonomy` *Upgrade workflow* delegates here:

| Lockfile | Manager | Discover outdated | Apply (single pkg) |
|---|---|---|---|
| `package-lock.json` | npm | `npm outdated` | `npm install <pkg>@<target>` |
| `pnpm-lock.yaml` | pnpm | `pnpm outdated` | `pnpm add <pkg>@<target>` |
| `yarn.lock` | yarn | `yarn outdated` | `yarn up <pkg>@<target>` (Berry) / `yarn upgrade <pkg>@<target>` (classic) |

- **Conflict signal:** a peer-dependency resolution conflict → report and stop; never silently pass an override flag (npm `--legacy-peer-deps`/`--force`, or the yarn/pnpm equivalents). It surfaces differently per manager — npm reports `ERESOLVE`; pnpm and yarn emit their own peer-dependency warnings/errors — so match the manager in use.
- **Monorepo:** a version may be pinned at the workspace root (or `pnpm-workspace.yaml`) — update there, not in the leaf package.
- **Release-notes URL** (core workflow step 2 fallback when Context7 has nothing): `npm view <pkg> repository.url`, strip the `git+` prefix and `.git` suffix, append `/releases`; if no repo URL, use `https://www.npmjs.com/package/<pkg>?activeTab=versions`.
- **Verify:** `tsc --noEmit` for the project (or the configured `lint`/`build`/`test` scripts) on the touched paths — capture to a file and grep (`context-discipline`).

## Upgrade-tier examples (JS/TS)

| Upgrade | Tier | Notes |
|---|---|---|
| `lodash 4.17.19 → 4.17.21` | 1 | Patch |
| `react + react-dom + @types/react` (minor) | 1 | Coordinated same-lane bump |
| `@types/*` bumps | 1 | Type-only |
| **React major** (`17 → 18`) | **2 — outline only** | Concurrent rendering, root API, effect timing changes |
| **Node major** (`18 → 22`) | 2 — outline only | Runtime-wide |
| CommonJS → ESM | 2 — outline only | Module-system migration |
| `webpack → vite`, `tsc → swc` | 2 — outline only | Toolchain replacement |
