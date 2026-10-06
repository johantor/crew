---
name: frontend-razor
description: Razor view (`.cshtml`) conventions for ASP.NET Core MVC — layouts and sections, partials and view components, tag helpers, encoding and XSS, antiforgery, view models, compilation — plus the Optimizely CMS 12/13 view rules (PropertyFor and epi-property, ContentArea and display options, XhtmlString, client resources, edit-mode checks, Visual Builder tag helpers). Load when a .NET project's server-rendered views are `.cshtml`, for the markup (frontend) or the server-side parts of a view (backend).
---

# Razor views

Razor views render the HTML of an ASP.NET Core MVC site. In server-rendered mode the markup
(structure, classes, ARIA) is `frontend`'s and the server-side parts (`@model`, binding, control
flow over data) are `backend`'s; change the view-model contract together, not each other's half.

## Views and layouts

- One strongly typed view model per view (`@model`), built in the controller or component.
  Never pass entities or data-access services to a view, and keep `ViewData`/`ViewBag` for the
  odd layout value: they are not type-checked.
- `_ViewImports.cshtml` holds directives only (`@using`, `@addTagHelper`, `@removeTagHelper`,
  `@tagHelperPrefix`, `@inject`, `@model`, `@inherits`, `@namespace`), never functions or
  sections; it applies to its folder and below. `_ViewStart.cshtml` runs before every full view, not
  before layouts or partials.
- A layout calls `@RenderBody()` and renders sections with `@RenderSection("Scripts", required:
  false)`. A section a view defines must be rendered by its layout (or `IgnoreSection`), and
  sections reach only the immediate layout: a partial or view component cannot define one.

## Partials and view components

- Render a partial with `<partial name="_Card" model="item" />` or
  `@await Html.PartialAsync(...)`. Never `Html.Partial` or `Html.RenderPartial`: they can
  deadlock and are slated for removal. A partial gets a copy of the parent's `ViewData` and no
  `_ViewStart`.
- A view component pairs logic with a view: `InvokeAsync` returns the view. MVC looks in
  `Views/<Controller>/Components/<Name>/` first, then `Views/Shared/Components/<Name>/`
  (`Default.cshtml` unless named): edit the one the project already uses. Call it with
  `@await Component.InvokeAsync("Name", new { ... })` or `<vc:name-in-kebab-case />`, which
  needs `@addTagHelper *, <the component's assembly>`.

## Encoding and forms

- `@value` HTML-encodes. `Html.Raw`, `HtmlString` and any `IHtmlContent` are written as-is:
  never with input a visitor or an editor without HTML rights supplied.
- Pass data to scripts through `data-` attributes, or `@Json.Serialize(model)`, which is
  HTML-safe; never concatenate values into inline JavaScript or into a URL path.
- A `<form method="post">` tag helper (or `Html.BeginForm`) adds the antiforgery token. Validate
  it on the action: `[AutoValidateAntiforgeryToken]`, globally for a non-API site.
- Use the tag helpers (`asp-for`, `asp-action`, `asp-route-*`) instead of hand-built names and
  URLs, and `asp-append-version="true"` on local scripts and styles.

## Compilation

- Views compile at build and publish, so `dotnet build` is the view gate: a type error in a
  view fails the build. Runtime compilation (`AddRazorRuntimeCompilation`) is obsolete on .NET
  10; use Hot Reload, and never enable runtime compilation outside development.

## Optimizely views (CMS 12 and 13)

Applies when the project references `EPiServer.CMS*`. Version-specific APIs are marked; the
content model is `optimizely-cms12` / `optimizely-cms13`.

- **Render every CMS property through the CMS**, so on-page editing and personalization work:
  `<div epi-property="@Model.Heading" />` (tag helper; CMS 13 recommends it) or
  `@Html.PropertyFor(m => m.Heading)`. The tag helper needs `services.AddCmsTagHelpers()` and
  `@addTagHelper *, EPiServer.Cms.AspNetCore.TagHelpers`. An element with content inside keeps
  that content as the rendering.
- **Custom markup that must stay editable**: put `@Html.EditAttributes(m => m.Heading)` on the
  element; it renders nothing outside edit mode.
- **`XhtmlString`** (rich text) goes through `epi-property` or `PropertyFor`, never
  `Html.Raw(... .ToHtmlString())`: on CMS 13 that drops the blocks and personalization inside
  it, and on both versions the raw string carries no edit attributes.
- **ContentArea:** `<div epi-property="@Model.MainArea"><div epi-property-item /></div>`, or
  `@Html.PropertyFor(m => m.MainArea, new { CssClass = "row", ChildrenCssClass = "col" })`.
  Display options (`services.Configure<DisplayOptions>(...)`) set a tag that picks the item
  template. Customize item markup in the `epi-property-item` element (or `epi-on-item-rendered`)
  with the tag helper; a `ContentAreaRenderer` subclass changes only the `PropertyFor` path.
- **Never loop over `ContentArea.Items` to render it:** `Items` is unfiltered, so visitors would
  see unpublished, access-restricted and personalized-out blocks. Render through `epi-property`
  or `PropertyFor`, or apply `IContentAreaItemsRenderingFilter` when code must walk the items.
- **Blocks:** a partial view named after the block type in `Views/Shared`, or a
  `BlockComponent<T>` / `AsyncBlockComponent<T>` when the block needs logic. On CMS 13 a
  tag-specific view is `{Type}.{Tag}.cshtml`.
- **Client resources:** every layout renders `@Html.RequiredClientResources("Header")` in
  `<head>` and `("Footer")` before `</body>` (or `<required-client-resources area="..." />`);
  the CMS requires both, and on-page editing loads its scripts through them.
- **Edit mode:** `@inject IContextModeResolver ContextModeResolver` with `@using EPiServer.Web`,
  then branch on `ContextModeResolver.CurrentMode.EditOrPreview()`; not
  `PageEditing.PageIsInEditMode` (obsolete in 12, removed in 13). Never hide content from
  editors that visitors see.
- **Links:** `Html.ContentLink(...)` and `Url.ContentUrl(contentLink)`, never a hardcoded path.
- **Visual Builder (CMS 13):** render an experience with
  `<epi-outline experience="@Model.CurrentPage">` (the expression must reach the
  `ExperienceData`, not a wrapping view model), then `<epi-grid>`, `<epi-row>`, `<epi-column>`
  and `<epi-component />`; only `epi-` elements may be direct children of `<epi-outline>`. They
  add the edit attributes themselves.
- **Changed in CMS 13:** `ContentArea.FilteredItems` is obsolete (render through the helpers,
  as above); the C# render-setting constants `CustomTag` / `ChildrenCustomTag` are gone (use
  `RenderSettings.CustomTagName` / `ChildrenCustomTagName`), while an anonymous
  `new { CustomTag = "span" }` key still works (`CustomTagName` as a key does not);
  `ClientResources.Render` is removed.

## Testing

- Test what decides the output (the view model, the component's `InvokeAsync`) with unit
  tests; the build checks the view's types.
- Markup, accessibility and on-page editing are checked in the browser: the e2e and
  visual-review lanes for markup, and an editor opening the page in edit mode for Optimizely.

## Sources

https://learn.microsoft.com/aspnet/core/mvc/views/overview (layouts, partials, view components,
compilation), https://learn.microsoft.com/aspnet/core/security/cross-site-scripting and
.../anti-request-forgery, and https://docs.optimizely.com/cms-12/docs and
https://docs.optimizely.com/cms-13/docs (rendering, content templates, client resources).
