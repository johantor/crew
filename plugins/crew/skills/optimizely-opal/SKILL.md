---
name: optimizely-opal
description: Optimizely Opal concepts and the custom-tool contract that does not depend on an SDK — agents, specialized and workflow agents, skills (formerly instructions), tool types, the discovery endpoint and its JSON, the call and response shapes, registering a tool registry, the registry bearer token and user OAuth, hosting, naming, limits, testing, and the SDK table. Load when a project builds or changes an Opal custom tool (`Optimizely.Opal.Tools`, `@optimizely-opal/opal-tools-sdk`, `optimizely-opal.opal-tools-sdk`, or a hand-written `/discovery` endpoint); load the SDK skill too.
---

# Optimizely Opal

Opal is Optimizely's agent platform. A **custom tool** is an HTTP service your team hosts: Opal
reads its manifest from a discovery endpoint and calls it when an agent or chat needs it. The
SDK skills (`optimizely-opal-tools-dotnet`, `-node`, `-python`) cover the code; this skill
covers the contract and the Opal side.

## Detect

| Language | Package | Skill |
|---|---|---|
| C# | `Optimizely.Opal.Tools` (the docs' `OptimizelyOpal.OpalToolsSDK` is deprecated) | `optimizely-opal-tools-dotnet` |
| JS/TS | `@optimizely-opal/opal-tools-sdk` | `optimizely-opal-tools-node` |
| Python | `optimizely-opal.opal-tools-sdk` (import `opal_tools_sdk`) | `optimizely-opal-tools-python` |

All three SDKs are pre-1.0 (the npm and PyPI releases are `-dev`/`.dev`): pin the version, and
read the installed package's README before you rely on an API. A tool built on OCP uses
`@optimizely-opal/opal-tool-ocp-sdk` instead; work from the OCP docs.

## Concepts

- **Agents** combine tools (actions) with **skills** (behavior guidelines; called
  *instructions* before May 2026). A **specialized agent** has a prompt template with
  `[[variables]]`, and uses only the tools its prompt names in backticks. A **workflow agent**
  chains triggers, logic and specialized agents.
- **Tool types:** system tools, connector tools, and custom tools (yours). Remote MCP servers
  are added as *External Providers*, not as a tool registry.
- In chat, Opal picks a tool from its **description**. Each tool can be *Active* and,
  separately, *Enabled in Chat*.

## The contract

- **Discovery:** `GET /discovery` returns
  `{"functions": [{"name", "description", "parameters": [{"name", "type", "description",
  "required"}], "endpoint", "http_method", "auth_requirements"?}]}`. Parameter types:
  `string`, `integer`, `number`, `boolean`, `array`, `object` (nested schemas since April 2026).
- **Call:** Opal sends `POST <endpoint>` with `{"parameters": {...}}`, plus `auth` when the tool
  declares an auth requirement and `environment` (`execution_mode`: `headless` or
  `interactive`). Headers such as `x-opal-thread-id` identify the conversation.
- **Response:** JSON. Return what the agent needs to answer, not a raw upstream payload: the
  model reads every byte. The SDKs map validation errors to 400 and exceptions to 500.
- No sync timeout or payload limit is documented: keep a call to seconds, and use the SDK's
  async mode (202, then a callback) for long work.

## Registering and changing a tool

- *Connectors > Registries > Add tool registry*: a name, the **discovery URL**, and an optional
  **bearer token**.
- After a change to a tool's name, description or parameters, run *More > Sync* on the
  registry; Opal does not see new or changed tools until then.
- Tool and registry names must be unique in the instance. Use `snake_case` names; the SDKs turn
  `_` into `-` in some endpoint paths, so let the SDK publish the endpoint.
- An instance allows a limited number of active tools (128 per the November 2025 notes); prefer
  fewer, well-described tools over many narrow ones.

## Naming and descriptions

- The description is how Opal chooses the tool: say what it does, when to use it, and what it
  returns. Describe every parameter, including format and units. Never put secrets or internal
  hostnames in a description: Opal and its users see it.

## Security

- **Registry token:** Opal sends `Authorization: Bearer <token>` on calls. The tool must check
  it, in constant time; `/discovery` stays public. Each SDK turns this on differently, and one
  of them accepts every token until you add its middleware: follow the SDK skill.
- **User auth:** a tool declares `auth_requirements` (`provider`, `scope_bundle`, `required`);
  Opal then sends `auth: { provider, credentials: { access_token, ... } }` in the body. Treat it
  as input: use the token only for the provider named, and never log it. The docs say only Opti
  ID is supported for tool authentication, while the SDK examples show other providers: check
  the provider with the operator.
- `/discovery` must be reachable from the internet; the tool endpoints are public too, so the
  token check is the only gate. Never expose an admin or debug route on the same host.

## Testing

- Test the tool function, and its HTTP route with the framework's test client; assert on the
  discovery JSON too, since a missing description or a wrong `required` flag changes how Opal
  calls the tool.
- Before registering: `curl` the deployed `/discovery`, then `POST` one tool with a sample
  body and the bearer token, and once without it (expect 401).
- In Opal, ask a question that should trigger the tool, and read the agent log (Execution
  Memory) to see the call.

## Deploy and verify

- Deploy, run *Sync* on the registry, and check that the tools appear with the expected
  parameters. Rotate the bearer token by changing it on both sides in one change window.

## Sources

https://docs.optimizely.com/agent-platform/docs (create custom tools, add a custom tool, manage
tools, custom tools FAQ, release notes) and the published SDK packages. The platform moves
fast: check the release notes before you rely on a limit or a UI path.
