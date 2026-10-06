---
name: optimizely-opal-tools-dotnet
description: Opal custom tools in C# with `Optimizely.Opal.Tools` — setup on ASP.NET Core, defining a tool and its parameters, the registry bearer token (and the middleware without which every token passes), user auth, discovery naming quirks, errors, tests. Load when a project references `Optimizely.Opal.Tools`; load `optimizely-opal` too.
---

# Opal tools: .NET

The contract and the Opal side are in `optimizely-opal`. This skill is the C# SDK.

## Detect

- `PackageReference` to `Optimizely.Opal.Tools` (0.7.x, `net8.0`, needs the ASP.NET Core shared
  framework). The legacy `OptimizelyOpal.OpalToolsSDK` is deprecated: move to the new package.

## Setup

```csharp
builder.Services.AddOpalToolService();
builder.Services.AddOpalTool<CalendarTools>();
// ...
app.MapOpalTools();
```

`MapOpalTools()` maps `GET /discovery` and `POST /tools/{name}`. A route prefix must start and
end with `/` (`MapOpalTools("/opal/")` maps `/opal/discovery`); the README's `"opal"` throws at
startup, and discovery still publishes `/tools/...` endpoints, so keep the default unless a
proxy needs the prefix.

## Defining a tool

```csharp
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using Optimizely.Opal.Tools;

public class GetEventsParameters
{
    [Required, Description("Day to list, ISO 8601 date")]
    public string Date { get; set; } = "";

    [Description("Max events, 1-50")]
    public int? Limit { get; set; }
}

public class CalendarTools(ICalendarClient calendar)
{
    [OpalTool(Name = "get_events")]
    [Description("Lists the user's calendar events for one day.")]
    public async Task<object> GetEvents(GetEventsParameters p, OpalToolContext context)
        => await calendar.ListAsync(p.Date, p.Limit ?? 10);
}
```

- Set `Name` explicitly: without it the method name becomes the tool name. The endpoint always
  turns `_` into `-` (`get_events` is served at `/tools/get-events`; `/tools/get_events` is a
  404), so tests read the path from `/discovery`.
- A non-nullable value type is published as `required: true` even with a default: make an
  optional number nullable (`int?`).
- Discovery publishes parameter names as the C# property names (`Date`); requests bind
  case-insensitively and responses serialize camelCase. Keep property names readable to the
  model.
- Constructor injection works; the context parameter is optional.

## Auth

- **Registry token:** the service is open by default. Configure the token (`AddOpalTools` with a
  config also registers the service, so `AddOpalToolService()` is then redundant), *and* add the
  middleware:

  ```csharp
  builder.Services.AddOpalTools(o => o.Config = new SdkConfig
  {
      AuthMode = AuthMode.StaticToken,
      BearerToken = builder.Configuration["Opal:BearerToken"],
  });
  app.UseOpalToolsAuth();
  ```

  Without `UseOpalToolsAuth()` every call passes, with or without a token. Read the token from
  configuration, never a committed `appsettings.json`. `/discovery` stays public; every other
  path returns 401 without the token, health checks included.
- **User auth:** `[OpalAuthorization("provider", "scope_bundle", required)]` on the method, then
  read `context.AuthorizationData`. The SDK does not enforce `required`: when
  `AuthorizationData` is null or names another provider, refuse the call.

## Errors

- A missing `parameters` key or a missing `[Required]` value returns 400 (ProblemDetails). A
  thrown exception returns 500 with a generic message, so the agent learns nothing: catch the
  failures you expect and return a result the agent can act on (what failed, what to try).

## Testing

- Unit-test the tool class directly: construct it with fakes for its dependencies and call the
  method with a parameters object.
- Test the HTTP contract with `WebApplicationFactory` (a top-level `Program` needs
  `public partial class Program {}`): `GET /discovery` (names, `required` flags, endpoints),
  then a call to the published endpoint with the bearer token (200) and one without it (401).

## Deploy and verify

- Host it like any ASP.NET Core app (DXP is not required). After a deploy, `curl` `/discovery`,
  call one tool without the token and expect 401, then *Sync* the registry in Opal.

## Sources

The package README in the `Optimizely.Opal.Tools` nupkg (0.7.8) and its XML docs; the source
repository is not public. Pre-1.0: re-read the README of the version the project pins.
