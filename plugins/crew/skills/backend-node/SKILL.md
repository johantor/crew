---
name: backend-node
description: Node backend stack conventions — service framework conventions (NestJS/Express/Fastify), headless CMS/Graph client usage, npm/pnpm/yarn workspace awareness. Load when the resolved backend stack is node.
---

# Backend: Node

You are working in a Node backend: a service framework (NestJS, Express, or Fastify — follow
whichever the project already uses), a headless-CMS/Graph client (e.g. Optimizely Graph), and
an npm/pnpm/yarn workspace. Search the repo for Optimizely Graph markers yourself
(`cg.optimizely.com`, `@optimizely/cms-sdk`, `@remkoj/optimizely-graph-client`); if one is
present, also load `optimizely-graph`. `@zaiusinc/node-sdk` or an ODP API host
(`api.zaius.com`, `*.odp.optimizely.com`) means Optimizely Data Platform: load `optimizely-odp`.
`@optimizely-opal/opal-tools-sdk` means an Opal custom tool: load `optimizely-opal` and
`optimizely-opal-tools-node`. An Opal tool written without the SDK (a `/discovery` route that
returns `functions` with `endpoint` and `http_method`) loads `optimizely-opal` alone.

In a SaaS-headless project shape, the "backend" may be thin — a BFF layer or a handful of API
routes wrapping Graph queries. Don't invent backend surface area the project doesn't have; a
thin backend is a valid shape, not a gap to fill.

## Crew config

`/crew:init` proposes from `package.json` `scripts`: `build`/`typecheck` → build, `test` → test,
`lint` → lint — the scripts that exist, never an assumed `npx` download. A script that only runs
from a subdirectory carries it in the value: `npm run build (from apps/api)`. Format matrix
rows are the web tooling rows `/crew:init` §2 describes (Biome, Prettier, ESLint, Stylelint from
the package's own config), one set per package.

## Route-handler ownership (Next.js frontend)

When the frontend stack is Next.js, its route handlers (`app/**/route.ts`) physically live
inside the frontend app directory but are **your lane by concern** — the same way Razor's
`@functions`/`@code` blocks are yours inside a `.cshtml` file frontend otherwise owns the
markup of. Implement route-handler business logic there rather than leaving it to frontend;
coordinate the markup/data contract instead of avoiding the file. `lane-guard.sh` exempts
these paths from your directory-based deny for this reason.

## Build

Watch/dev forms that never terminate: `nodemon`, a framework's dev server. The lock signature is
`EBUSY`/`EPERM`/`EACCES`, or a locked `dist`/build output.

### Parallel gates

Build, test and lint may run at once when no gate writes what another reads: `tsc --noEmit`
emits nothing, `eslint` and `prettier --check` only read, and the test runner's cache
(`node_modules/.vite`, or the OS temp dir for Jest) has no other writer. No per-gate path is
needed; each handoff carries the command as configured.

Use the recipe only when **all** of these hold; otherwise run the gates one at a time. Every
run under it passes `nocache` to the gate runner: a result the tree check may still discard is
never cached, and never answered from the cache.

- Each configured command is one of these, or a package script (`npm run <name>`, `npm test`;
  `pnpm`/`yarn` likewise) whose `package.json` entry — in the package the config names, e.g.
  `(from apps/api)` — is exactly one of these, optionally behind `npx`:
  - Build: `tsc --noEmit`, optionally with `-p`/`--project <path>`.
  - Test: `vitest run` or `jest`, optionally followed by paths.
  - Lint: `eslint` (optionally with `--max-warnings <n>`) or `prettier --check`, optionally
    followed by paths.

  Any other flag (`--cache`, `--coverage`, `--incremental`, `--build`, a reporter, …), a second
  command (`&&`, `;`, `|`), a script that calls another script, or a `pre<name>`/`post<name>`
  script beside it (npm runs those too) means serial. The list is closed on purpose: a flag it
  does not name is never judged safe.
- The `tsconfig` the build resolves sets neither `incremental` nor `composite`: with either,
  `--noEmit` still writes `.tsbuildinfo` into the tree.
- The **tree check** has passed this session and not failed since. A config file can send a
  cache or a report into the tree (Jest's `cacheDirectory`, Vitest's `cache.dir`, a coverage
  reporter), and no list of such settings is complete, so check the result on **every** run:
  touch a marker file first, and afterwards confirm that no file in the repo outside `.git` and
  `node_modules` is newer than it. The session's first run is serial. A parallel run that fails
  the check proves nothing: discard its results, rerun the gates one at a time, stay serial for
  the rest of the session, and report the new files without deleting them (they may be the
  developer's).
