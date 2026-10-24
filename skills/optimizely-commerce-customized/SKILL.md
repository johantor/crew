---
name: optimizely-commerce-customized
description: Optimizely Commerce Connect (formerly Customized Commerce and Episerver Commerce) on CMS 12 and 13 — versions 14 and 15, catalog content types and MetaDataPlus, markets, prices, inventory, carts and orders with the processor APIs, promotions, payment and shipping plugins, Graph and Search & Navigation for the catalog, the ODP export, PCI and PII, testing, upgrades and deploys. Load when a project references `EPiServer.Commerce*`, `Mediachase.Commerce*`, `Optimizely.Graph.Commerce`, `EPiServer.Find.Commerce`, or an `EcfSqlConnection` connection string.
---

# Optimizely Commerce Connect

Commerce Connect is the .NET commerce add-on to Optimizely CMS; the code and docs still say
Customized Commerce, Episerver Commerce, ECF and `Mediachase.*`. Configured Commerce is another
product: load `optimizely-commerce-configured` for it.

## Detect

- **Packages** (feed `nuget.optimizely.com`): `EPiServer.Commerce` (metapackage of Core, UI,
  UI.Admin, UI.CustomerService, ODP), `EPiServer.ServiceApi.Commerce`, `EPiServer.Commerce.Azure`.
- **The version decides the platform:** `EPiServer.Commerce.Core` 14.x runs on CMS 12 (14.46.x
  targets .NET 8); 15.x on CMS 13 and .NET 10 (GA 20 July 2026), with Opti ID and Graph.
- **Config:** connection strings `EcfSqlConnection` (Commerce) and `EPiServerDB` (CMS): two
  databases. Catalog search in a `SearchOptions` section (`DefaultSearchProvider`).
- Neighbours: `optimizely-cms12` (Commerce 14), `optimizely-cms13` (Commerce 15),
  `optimizely-cms-upgrade` (the CMS half of 14 to 15), `optimizely-graph`, `optimizely-odp`,
  `optimizely-search-navigation`, `optimizely-ocp`, `backend-dotnet`, `tests-xunit`.

## Catalog

- Inherit `VariationContent`, `ProductContent`, `BundleContent`, `PackageContent`, `NodeContent`
  or `CatalogContent`. Never inherit `EntryContentBase`, `NodeContentBase` or `RootContent`.
- `[CatalogContentType(GUID = "...", MetaClassName = "...")]` binds the model to a meta-class.
  Set both: without `MetaClassName`, a class rename adds a new meta-class and leaves the old one.
- Models sync to MetaDataPlus with limits: a property type change throws, a rename adds a field
  and leaves the old one, a removed property stays. Plan each as a manual step.
- Meta-fields are shared across meta-classes: two properties with the same name on different
  classes must have the same definition (type, `[CultureSpecific]`, and so on). Commerce-only
  types (`[BackingType(typeof(PropertyDictionarySingle))]` and the like) do not work in blocks.
- Use `IContentLoader` / `IContentRepository`, not the `ICatalogSystem` DTO reads (removed in
  15). Node and entry IDs overlap: convert ECF IDs with `ReferenceConverter.GetContentLink(...)`.

## Markets, prices, inventory

- A multi-market site registers its own `ICurrentMarket` and disables `MarketId.Default` (never
  deletes it). Carts belong to customer + name + market. `IOrderGroup.Market` is gone in 15: use
  `IMarketService.GetMarket(orderGroup.MarketId)`.
- **Prices:** `IPriceService` (optimized, cached) for the site and order processing;
  `IPriceDetailService` for edit UIs only, never on the public site.
  - `SetCatalogEntryPrices` replaces every price of the given entries; an empty list clears
    them. Edit single prices through `IPriceDetailService.Save`.
  - A default price has `MinQuantity` 0, not 1 (quantities can be fractional). The lowest
    matching price wins. There is no automatic currency conversion.
- **Inventory:** `IInventoryService`. `Save` upserts, `Insert` throws on an existing record,
  `Update` throws on a missing one, `Adjust` adds deltas, `Request` is transactional. `List()`
  (loads everything) is removed in 15: use `QueryByEntry` / `QueryByWarehouse`.
- A custom price or inventory service must raise `CatalogKeyEventBroadcaster.OnPriceUpdated` /
  `OnInventoryUpdated`, or the search index keeps the old values.

## Carts and orders

- Use `IOrderRepository` (`LoadOrCreateCart<ICart>`, `Save`, `SaveAsPurchaseOrder`) and
  `IOrderGroupFactory` (`cart.CreateLineItem(code, factory)`), not the concrete classes. On 15,
  prefer the async forms (`LoadAsync`, `SaveAsync`, `SaveAsPurchaseOrderAsync`).
- Calculators count only line items in a shipment: `cart.AddLineItem(lineItem, factory)` puts
  the item in the first shipment.
- Before checkout, re-check the cart on the server: `ValidateOrRemoveLineItems`,
  `UpdatePlacedPriceOrRemoveLineItems`, `UpdateInventoryOrRemoveLineItems`, then
  `ApplyDiscounts`, then `ProcessPayments(paymentProcessor, orderGroupCalculator)`. Pass the
  `ValidationIssue` callback and show the issues. Never take a price from the client.
- The workflow engine (`RunWorkflow`, `OrderGroupWorkflowManager`, `ActivityFlow`) is removed in
  15; on 14, add no new uses. Use `IPurchaseOrderProcessor`, `IShipmentProcessor` and the rest.
- The docs disagree on processor names (`CancelOrder`/`CompleteShipment` vs `Cancel`/`Complete`)
  and on validation (`OrderValidationService.ValidateOrder(cart)` vs `cart.ValidateOrder()`):
  check the installed assembly. `ICartService` is only in the 15 breaking-change notes: grep the
  project for it first.
- Serializable carts are on by default. Custom `Properties` on a cart copy to the purchase order
  by name only, so the purchase order meta-class must have a matching meta-field.

## Promotions

- Inherit `EntryPromotion`, `OrderPromotion` or `ShippingPromotion` (`[ContentType(GUID = ...)]`),
  never `PromotionData`. The processor inherits `EntryPromotionProcessorBase<T>` (or the Order /
  Shipping base) and returns a `RewardDescription` from `Evaluate`.
- Add coupon codes to the `IOrderForm` before `ApplyDiscounts`. The legacy
  `Mediachase.Commerce.Orders.Discount` classes are gone in 15: use `GetDiscountTotal()` and
  `IOrderForm.Promotions`.

## Payments and shipping

- No payment providers ship. A new gateway implements `IPaymentPlugin` (`PaymentProcessingResult
  ProcessPayment(IOrderGroup, IPayment)`), not the older `IPaymentGateway`. The `IPaymentMethod`
  and the Commerce Admin payment share one `SystemKeyword`, fixed once created.
- Shipping rates: implement `IShippingPlugin` (`ShippingRate GetRate(Guid methodId, IShipment
  shipment, ref string message)`) and register it as `IShippingPlugin`.
- **Payment Service** is Optimizely's Spreedly integration (`PaymentServicePayment` /
  `PaymentServiceGateway`, namespace `EPiServer.Commerce.PaymentService`): the Spreedly iFrame
  tokenizes the card in the browser, with optional 3DS. Optimizely provisions it; its docs are
  partly for Configured Commerce, so check each step against the version in use.

## Search, Graph, ODP, PIM

- **Graph:** `Optimizely.Graph.Commerce`, `services.AddCommerceGraph()`. 1.x is for Commerce 14
  (with `Optimizely.ContentGraph.Cms`, after `AddContentDeliveryApi()` and `AddContentGraph()`);
  15.x is for Commerce 15. The Graph full and delta sync jobs index catalogs, nodes, entries and
  dynamic packages. Keys, schema and queries: `optimizely-graph`.
- **Catalog search provider** (Commerce Admin, catalog panel, Add Line Item): on 14, the
  separate `Optimizely.Commerce.GraphSearchProvider`; v1.0.0 ignores `[IncludeInDefaultSearch]`
  and searches every string. On 15 it ships in `Optimizely.Graph.Commerce`. Lucene still works.
- **Search & Navigation:** `EPiServer.Find.Commerce` 12.3.1 needs Commerce Core 14.46 or later
  and below 15. Commerce 15 drops it. The move to Graph is in `optimizely-search-navigation`.
- **ODP:** `EPiServer.Commerce.ODP` (in the metapackage) runs the *Export data to ODP* job from
  `ODPJobOptions`; its access and S3 keys go in configuration. See `optimizely-odp`.
- **PIM:** Optimizely PIM is documented and connected under Configured Commerce only. A Commerce
  Connect site imports product data through the Service API (`/episerverapi/commerce/...`) or,
  on 15, CMS 13 External Content over OCP (`optimizely-ocp`).

## Security

- Never store a card number, CVV or expiry. Commerce 15 removes `ICreditCardPayment`,
  `CreditCardPayment` and `CreditCard` for PCI DSS. On 14 they still exist: do not use them.
  Let the gateway's hosted fields or the Payment Service iFrame tokenize the card, and keep only
  the token and the provider transaction ID in `IPayment.Properties`. Never log payment
  requests, responses or tokens.
- Orders, carts and customer contacts hold PII. Keep it in the Commerce database; do not copy it
  to custom tables, logs or analytics. Mark sensitive meta-fields `[Encrypted]`.
- Gateway, Payment Service (`AppKey`, `SecretKey`, `SigningSecret`), Service API and ODP
  credentials are server-side configuration, never committed.
- Change the default admin login of a new install before the first deploy.

## Testing

- Inject `IOrderRepository`, `IOrderGroupFactory`, the processors and the calculators (the
  extension methods take them as arguments), never `ServiceLocator`. Unit-test a promotion's
  `Evaluate` and a plugin's `ProcessPayment` on a fake order group, the gateway behind an interface.
- Run the full order flow (cart, discount, payment, purchase order, inventory) against the
  gateway's sandbox with its test cards only, in a non-production environment.

## Deploy and verify

- Back up both databases before a Commerce upgrade. The schema update runs at startup only when
  `EPiServer:Cms:DataAccess:UpdateDatabaseSchema` is `true`; otherwise run it with the
  `EPiServer.Net.Cli` tool. From 13, upgrade to 14 and run its migrations before 15. Commerce 15
  ships with CMS 13: plan both breaking-change lists together.
- Commerce Manager is gone since 14 (Commerce Admin in the CMS replaces it): skip DXP deploy
  steps for a Commerce Manager site. DXP smooth (zero-downtime) deployment is for CMS only.
- After a deploy, run the Graph sync (and rebuild the catalog index for a search-provider
  change), open Commerce Admin, and place one sandbox order end to end.

## Sources

https://docs.optimizely.com/commerce-connect-15/docs (start at *New in Commerce Connect 15*),
https://docs.optimizely.com/commerce-connect-14/docs,
https://docs.optimizely.com/commerce-composable-modules/payment-gateway/configure-payment-service,
https://docs.optimizely.com/configured-commerce/pim, and the `nuget.optimizely.com` listings.
Versions move fast after the 15 release: re-check them before you rely on one.
