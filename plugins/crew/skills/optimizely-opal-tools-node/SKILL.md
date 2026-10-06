---
name: optimizely-opal-tools-node
description: Opal custom tools in Node/TypeScript with `@optimizely-opal/opal-tools-sdk` — Express setup (and the JSON body parser it does not add), registerTool with Zod schemas (not validated at runtime), the @tool decorator, the registry bearer token, user auth, endpoint naming, errors, tests. Load when a project depends on `@optimizely-opal/opal-tools-sdk`; load `optimizely-opal` too.
---

# Opal tools: Node

The contract and the Opal side are in `optimizely-opal`. This skill is the TypeScript SDK.

## Detect

- `@optimizely-opal/opal-tools-sdk` in `package.json` (every release is `-dev`; pin it). Peers:
  `express` 4 (not 5), `zod` 3.25+ or 4, `axios`.

## Setup

```ts
import express from "express";
import { ToolsService, registerTool } from "@optimizely-opal/opal-tools-sdk";

const app = express();
app.use(express.json());              // required: the SDK does not add it
const tools = new ToolsService(app, {
  authMode: "static_token",
  bearerToken: process.env.OPAL_BEARER_TOKEN,
});
```

- Without `express.json()`, parameters arrive `undefined` and the call still returns 200.
- Without `authMode`, the service accepts every call: always configure the token.
- Create `ToolsService` before any tool registers: `registerTool` only adds to services that
  exist. Import the API from the package root; the README's `/auth` subpath does not resolve.
- Routes: `GET /discovery` and one `POST /tools/{name}` per tool; `_` in a name always becomes
  `-` in its endpoint (`get_events` is served at `/tools/get-events`).

## Defining a tool

```ts
import { z } from "zod";   // on zod 3.25.x: from "zod/v4" (the SDK reads v4 schemas)

registerTool("get_events", {
  description: "Lists the user's calendar events for one day.",
  inputSchema: {
    date: z.string().describe("Day to list, ISO 8601 date"),
    limit: z.number().int().optional().describe("Max events, 1-50"),
  },
}, async (params, extra) => listEvents(params.date, params.limit ?? 10));
```

- Prefer `registerTool` with Zod over the `@tool` decorator: `@tool` publishes `parameters: []`
  unless you list them by hand, since TypeScript types are not read at runtime.
- **The Zod schema is not enforced at runtime:** a call missing a required field still runs,
  and `.default()` values are not applied (and are published as required). Parse the input
  yourself (`z.object(schema).parse(params)`) before you use it.

## Auth

- **Registry token:** pass `authMode: "static_token"` and `bearerToken` from the environment
  (above); the comparison is constant-time and `/discovery` stays public.
- **User auth:** declare `authRequirements: { provider, scopeBundle, required }` on the tool,
  and read `extra?.auth` in the handler (`extra` is optional in the typings). The SDK does not
  enforce `required`: when `auth` is missing or names another provider, refuse the call. The
  `@requiresAuth` decorator never reaches discovery: do not use it.

## Errors

- A thrown error returns 500 `{ error: message }`, and the message reaches the agent: throw
  messages the agent can act on, and never include secrets or stack details.

## Testing

- Unit-test the handler function with fakes.
- Test the HTTP contract against `app.listen(0)` (or supertest): `/discovery`, a call to the
  published endpoint with the token and one without (401). Tools register into a global
  registry that the package root does not export (it lives in
  `@optimizely-opal/opal-tools-sdk/dist/registry`): build the app in a factory per test that
  creates `ToolsService` first and registers the tools after it.

## Deploy and verify

- Host it as a Node service behind HTTPS. After a deploy, `curl` `/discovery`, call one tool
  without the token and expect 401, then *Sync* the registry in Opal.

## Sources

The published package (README, `dist/` typings and code) at 0.1.41-dev; the source repository
is not public. Pre-1.0: re-read the README of the version the project pins.
