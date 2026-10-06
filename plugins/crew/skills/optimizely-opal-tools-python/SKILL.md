---
name: optimizely-opal-tools-python
description: Opal custom tools in Python with `optimizely-opal.opal-tools-sdk` (import `opal_tools_sdk`) — FastAPI setup, the @tool decorator with a Pydantic parameters model (handlers must be async), the registry bearer token, user auth (and the @requires_auth trap), the public debug route, errors, pytest tests. Load when a project depends on `optimizely-opal.opal-tools-sdk`; load `optimizely-opal` and `backend-python` too.
---

# Opal tools: Python

The contract and the Opal side are in `optimizely-opal`; packaging and the gate are in
`backend-python`. This skill is the Python SDK.

## Detect

- `optimizely-opal.opal-tools-sdk` in the dependencies, `from opal_tools_sdk import ...` in code.
  It needs Python 3.10+, FastAPI and Pydantic 2. Every release is `.dev`: pin it.

## Setup

```python
import os
from fastapi import FastAPI
from opal_tools_sdk import ToolsService, tool
from opal_tools_sdk.config import SdkConfig

app = FastAPI()
tools = ToolsService(app, config=SdkConfig(
    auth_mode="static_token", bearer_token=os.environ["OPAL_BEARER_TOKEN"]))
```

- Routes: `GET /discovery` and one `POST /tools/{name}` per tool. The service also registers
  `GET /debug-routes`, which lists every route and stays public: block it at the proxy in
  production.
- Without a config (`ToolsService(app)` or `SdkConfig()`), every call runs: always configure
  the token. `static_token` with an empty token fails at startup, which is what you want.
- Create `ToolsService` before any `@tool` runs; otherwise the tool is skipped with only a
  warning.

## Defining a tool

```python
from typing import Optional
from pydantic import BaseModel, Field

class GetEventsParameters(BaseModel):
    date: str = Field(description="Day to list, ISO 8601 date")
    limit: Optional[int] = Field(default=None, description="Max events, 1-50")

@tool("get_events", "Lists the user's calendar events for one day.")
async def get_events(parameters: GetEventsParameters):
    return await list_events(parameters.date, parameters.limit or 10)
```

- **Handlers must be `async def`:** a plain `def` returns 500 ("can't be used in 'await'
  expression").
- The first argument is typed with a Pydantic model; `Field(description=...)` becomes the
  parameter description, and a default or `Optional` makes it not required. Write
  `Optional[int]`, not `int | None`: the SDK publishes a PEP 604 union as `string`. Pydantic
  validates the call: an invalid one returns 400.

## Auth

- **Registry token:** `SdkConfig(auth_mode="static_token", bearer_token=...)` (above);
  `/discovery` stays public.
- **User auth:** declare it in the decorator,
  `@tool(..., auth_requirements=[{"provider": "...", "scope_bundle": "...", "required": True}])`,
  and take a keyword argument named exactly `auth_data`. The SDK does not enforce `required`:
  when `auth_data` is `None` or names another provider, refuse the call. Do not use
  `@requires_auth`: above
  `@tool` the requirement never reaches discovery, and below it every call returns 500.

## Errors

- Other exceptions return 500 `{"detail": str(e)}`, and the text reaches the agent: raise
  messages the agent can act on, never secrets or upstream payloads.
- A request without a `parameters` key is read as the parameters itself: do not rely on it.

## Testing

- pytest, following the SDK's own tests: an autouse fixture that clears the registry
  (`from opal_tools_sdk import _registry`; `_registry.services.clear()`), then build the app in
  a factory that creates `ToolsService(FastAPI(), config=...)` and only then defines the tools,
  for example through a `register_tools()` function (a `@tool` that ran at import time is lost
  after the clear, and importing the module again does not run it again). Call it with
  `TestClient(app).post("/tools/get_events", json={"parameters": {...}})`, and assert on
  `/discovery` and on 401 without the token.
- Unit-test the logic behind the handler without the SDK.

## Deploy and verify

- Run it under an ASGI server (uvicorn) behind HTTPS, without `--reload`. After a deploy,
  `curl` `/discovery`, call one tool without the token and expect 401, check that
  `/debug-routes` is not reachable, then *Sync* the registry in Opal.

## Sources

The PyPI sdist (0.1.50.dev0: README, `opal_tools_sdk/`, `tests/`); the source repository is not
public. Pre-1.0: re-read the README of the version the project pins.
