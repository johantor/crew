---
name: optimizely-commerce-configured
description: Optimizely Configured Commerce (formerly Insite Commerce, `Insite.*` namespaces) conventions — the extensions repository, handler chains, pipelines and DI, custom properties and tables, the Spire front end (blueprints, widgets, front-end handlers), integration jobs and the WIS, the LTS/STS cadence and the .NET 8+ move, the library allowlist, payments, Admin and Storefront API auth, PIM, sandbox and production deploys. Load when a project references `Insite.*` namespaces, `InsiteCommerce.Web`, `@insite/client-framework`, `@insite/mobius`, `src/FrontEnd/modules/blueprints/`, `VersionInfo.yaml`, or an `insitesandbox.com` host.
---

# Optimizely Configured Commerce

A hosted B2B platform, Insite before the acquisition. Optimizely owns and hosts the base code; a
partner owns the **Extensions** project and the Spire blueprints, nothing else.

## Detect

- **Repository:** a fork of `InsiteSoftware/insite-commerce-cloud` (often the `upstream` remote)
  with `src/InsiteCommerce.Web`, an `Extensions.csproj`, `src/FrontEnd` (Spire),
  `VersionInfo.yaml`, and `tools/allowedLibraries.json` / `tools/allowedLibraries-netcore.json`.
- **.NET:** `using Insite.*` (`Insite.Core.Services.Handlers`), `HandlerBase<,>`, `IPipe<,>`,
  `[DependencyName]`, `IUnitOfWork`. No public NuGet package: the assemblies come with the repo.
- **Spire:** imports from `@insite/client-framework/...` and `@insite/mobius/...`. A Classic
  (Angular) theme is end-of-life: change it only to keep it running.
- **Hosts:** `<project>.insitesandbox.com` (v1) or `<project>.commerce.insitesandbox.com` (v2/v3)
  for sandbox; `/admin` is the Admin Console, `/contentadmin` the Spire CMS.
- Neighbours: `backend-dotnet`, `frontend-react` (blueprints), `tests-xunit` if the tests use
  it. `EPiServer.Commerce.*` is another product: `optimizely-commerce-customized`.

## Stay on extension points

- Only the Extensions project and blueprint folders deploy as yours. The build ignores edits to
  base code (`InsiteCommerce.Web`, `modules/client-framework`, `modules/shell`), and the next
  upstream merge overwrites them. Never fix a problem in base code: find the handler, pipe,
  plug-in or widget that covers it, or tell the operator there is none.
- **Database:** never alter base tables. Use custom properties, or custom tables in the
  `Extensions` schema from scripts in the Extensions project's `DatabaseScripts/`, built as
  *Embedded Resource*, named `{YYYY.MM.DD}.{NN}.{name}.sql`. A script runs once, ever: a change
  is a new script, never an edit of one that ran.
- **NuGet:** reference only packages in `tools/allowedLibraries.json` (.NET 4.8) or
  `tools/allowedLibraries-netcore.json` (.NET 8+); others must not ship (Polly is listed).

## Handlers and pipelines

- A handler inherits `HandlerBase<TParameter, TResult>`; all handlers with the same two types
  form one chain. `Execute(IUnitOfWork unitOfWork, TParameter parameter, TResult result)` is the
  entry point. `[DependencyName(nameof(MyHandler))]` is required: a new name adds a handler, the
  base handler's name replaces it. A handler cannot be removed, only replaced by a no-op.
- `Order`, lowest first: base chains start at 500 and step by 100. Use 1–499 to run before, a
  gap (550) to run between. Prefer adding after the base handler to replacing it: a copy of base
  logic goes stale on the next release.
- Continue with `return NextHandler.Execute(unitOfWork, parameter, result);`; return `result` to
  stop; return `CreateErrorServiceResult(result, SubCode.X, "message")` to stop with an error the
  API caller sees.
- A pipe implements `IPipe<TParameter, TResult>` (`Order`, same `Execute`) for reusable,
  non-transactional logic such as pricing. Base pipes start at 100, step by 100, and `Order` is
  unique per pipeline. Stop with `result.ResultCode = ResultCode.Error` or
  `result.ExitPipeline = true`, and always return `result`. A pipe with the **same class name**
  replaces the base pipe; you cannot inherit from one.

## Dependency injection

- A class implementing `IDependency` and `IExtension` registers itself, per request by default;
  add `ISingletonLifetime` or `ITransientLifetime` to change that. Several implementations of one
  interface use `IMultiInstanceDependency`, keyed by class name or `[DependencyName]`.
- Use constructor injection; resolve named registrations through an injected
  `IDependencyLocator` in a factory. Do not code against Grace (.NET 8+) or Unity (.NET 4.8).
- Plug-ins (tax, payment gateways, currency, geocoding, rating) are chosen in Admin Console
  settings by `DependencyName`: renaming the class drops it out of that setting.

## Custom properties

- Entities extending `BaseModel` carry `Properties`, a dictionary of **string** keys and values;
  serialize anything complex. In C#, `GetProperty(name, default)` and `SetProperty`.
- Define each property first in *Admin Console > Administration > System > Application
  Dictionary* (no spaces or dashes in the name); an undefined one in a request is rejected.
- They are slow, unindexed and have no cascade delete: queried or large data goes in a custom
  table with its own endpoint.

## Spire

- Work only in `src/FrontEnd/modules/blueprints/<name>/src/` (`Widgets`, `Pages`, `Overrides`,
  handlers). `npm run create-blueprint <name>` and `npm run start <name> <port>` run from
  `src/FrontEnd`. A widget or page that replaces a base one must also be in `Overrides`, or the
  build fails.
- A widget's default export is a `WidgetModule` (`component`, `definition.group`,
  `definition.fieldDefinitions`) from `@insite/client-framework/Types/WidgetModule`.
- Never import `modules/shell`, `client-framework` internals, or anything prefixed `UNSAFE_`; use
  exported selectors such as `getCurrentPage`.
- Change front-end handler chains with `addToStartOfChain`, `addToEndOfChain`,
  `addToChainBefore`, `addToChainAfter` or `replaceInChain` from
  `@insite/client-framework/HandlerCreator`. Naming a handler not in the chain only logs a
  warning: re-check chains after an upgrade. Never replace `RequestDataFromApi` with a no-op.
- npm packages go in the blueprint's own `package.json` (`npm install --save` in the blueprint
  folder), never in `src/FrontEnd/package.json`. One doc page forbids `package.json` changes; the
  npm install page allows the blueprint-level file, and that is the rule.

## Integration

- *Admin Console > Jobs > Job Definitions*: **Refresh** (ERP into Commerce), **Submit** (a
  dataset such as an order to the ERP), **Report**, **Execute** (SQL or a stored procedure).
- A job runs a preprocessor (website, `IJobPreprocessor`), an integration processor (on the WIS,
  `IIntegrationProcessor`), then a postprocessor (website, `IPostprocessor` in the docs; check
  the name in the referenced assembly; `FieldMap` maps to entities). A class named `IntegrationProcessorXyz` shows as `Xyz` in the Admin Console.
- The Windows Integration Service runs in the customer's network, hosted by partner and customer.
  On .NET 8+ it uses the REST endpoints (WCF is gone). ERP connectors get bug fixes only:
  extend with jobs and processors, not by patching a connector.

## Releases and upgrades

- Versions read `5.2.<yymm>.<build>+sts` (monthly) or `+lts` (three a year, about January, May
  and September, hotfixed for four months). The version is pinned in `VersionInfo.yaml` and only
  goes up. Upgrade by merging the upstream version tag into the sandbox branch and testing there.
- **.NET 8+:** `InsiteCommerce.Web` stays `net48`. Extensions targets `net8.0` (or
  `net48;net8.0`) on 5.2.2512–5.2.2604 and `net10.0` (or `net48;net10.0`) from 5.2.2605; guard
  diverging code with `#if NETCOREAPP`. Inject `IHttpContextAccessor`, not `HttpContextBase`; use
  ASP.NET Core controller types (`IActionResult`, explicit `[FromBody]`). Output goes to
  `dist/netcore/Extensions.dll`.

## Security

- **Payments:** Spire uses the Payment Service (Spreedly iframe, *Administration > Payment
  Service*, one gateway per site); Classic uses the TokenEx iframe. Optimizely owns every
  gateway's card part; a partner builds only non-card methods (ACH, eCheck, SEPA). Card data
  never reaches your code: never log or store a PAN or CVV, never edit base payment code.
- **Admin API** (`/api/v1/admin/`, OData): a bearer token from `/identity/connect/token`, Basic
  auth `isc_admin:<secret>`, grant `password`, scope `isc_admin_api offline_access`, as a user
  with Admin Console access. Tokens are short-lived (401 = expired): refresh them. Secret and
  password stay server-side, from configuration, never committed.
- **Storefront API** (`/api/v1/`): client `isc`, scope `iscapi`, as the signed-in user. A handler
  checks the current user and customer before it returns their data; never trust a request ID.
- **PII:** `Properties` reach the browser; keep internal or personal data out of them.

## Testing

- Test a handler or pipe by calling `Execute` with a fake `IUnitOfWork` and asserting on the
  result; the docs publish no platform test harness. Swagger exists only on sandbox
  (`/swagger/ui/index` on .NET 4.8; `/admin/swagger`, `/storefront/swagger`,
  `/integration/swagger` on .NET 8+).

## Deploy and verify

- **Sandbox:** a push to the sandbox branch builds and deploys (Build Service v2 needs its GitHub
  app on the repo) and emails the result. Branch names: 2–30 lowercase letters, digits, hyphens.
- **Production:** never automatic. Push the production branch; the operator requests the deploy
  in Mission Control (v2+) or the Service Desk, after the change passed on sandbox. An
  extensions-only deploy cannot be rolled back: redeploy the old code as a new commit.
- After a sandbox deploy, call the changed endpoint in Swagger, open the changed Spire page, and
  run one changed job and read its history.
- **PIM:** Optimizely PIM feeds products through the *PIM:* job definitions (*Synch Setup Data*,
  *Publish Approved Products*, ...). Point them only at the customer's environment, never at a
  partner test site.

## Sources

https://docs.optimizely.com/configured-commerce/docs (handlers, pipelines, dependency injection,
custom properties, Spire, integration processors, LTS/STS branches, .NET 8.0+ migration,
deployment, third-party library policy), https://docs.optimizely.com/configured-commerce/sdk
(Admin API), and https://docs.optimizely.com/commerce-composable-modules/payment-gateway/configure-payment-service.
Version ranges and target frameworks move each release: re-check them before you rely on one.
