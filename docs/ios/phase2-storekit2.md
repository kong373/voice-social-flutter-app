# iOS Phase 2 — StoreKit 2

## Scope

The iOS gift-coin purchase path uses consumable StoreKit 2 products. Alipay is
not exposed on iOS. The client treats Apple transactions as provisional until
the authenticated first-party backend verifies the signed transaction and
confirms an idempotent wallet/ledger settlement.

Configured product identifiers are frozen to the backend catalog:

- `com.kong373.voiceSocialApp.recharge.60`
- `com.kong373.voiceSocialApp.recharge.300`
- `com.kong373.voiceSocialApp.recharge.980`

## Authority and recovery

1. The backend creates an order and binds its public product, StoreKit product,
   amount, gift-coin amount, and `appAccountToken`.
2. The client loads the exact consumable from StoreKit and checks its decimal
   price and currency against the backend's CNY catalog before enabling the
   catalog or starting a purchase. Unsupported storefronts and mismatched
   prices fail closed before payment. The UI uses StoreKit's localized display
   price, and the price is checked again immediately before purchase.
3. Verified StoreKit transactions are sent as signed JWS to the backend. The
   JWS is never logged or persisted by the Flutter client.
4. `Transaction.finish()` is allowed only after the backend returns a matching
   `DELIVERED` or `ALREADY_DELIVERED` acknowledgement with
   `finishAllowed=true`.
5. Pending, rejected, malformed, timed-out, or unavailable responses leave the
   transaction unfinished. Login, foreground restoration, and explicit order
   recovery replay `Transaction.updates` and `Transaction.unfinished` through
   the same backend-before-finish gate. Automatic retry is bounded; reaching
   that bound never changes payment status into cancelled or failed.

### Interrupted purchase safety

`appAccountToken` is an association, not an Apple request idempotency key.
The same order/product/token must never invoke `Product.purchase` twice.
Before invoking native purchase the coordinator writes a small attempt record
through the existing secure KeyValueStore. Only the original order binding,
amount/coins, and an explicit attempt/terminal category are stored; no JWS,
authentication token, provider credential, or raw SDK error is persisted.

- A Dart timeout does not cancel the native Future. The native single-flight
  guard remains held until the actual purchase call returns. The adapter keeps
  every result, including ordinary Ask to Buy pending and late cancellation.
- A late explicit `userCancelled` result may mark that original attempt
  cancelled and unlock a **new** order/token. It cannot authorize another call
  using the old order/token or overwrite an already delivered record.
- After restart, an attempted order with no retained result and no unfinished
  transaction remains `RECOVERY_UNKNOWN`. Empty unfinished does not prove
  cancellation. The app restores that order and performs read/recovery work;
  it does not create a replacement purchase automatically.
- A complete, matching backend delivery ACK confirms financial delivery even
  if native `finish` is delayed. The result stays delivered with
  `native_finish_deferred`; unfinished recovery retries cleanup. No successful
  native finish is claimed until observed. The per-account recovery journal
  keeps each delivered-but-unfinished order snapshot when a new independent
  purchase starts. Its v2 collection reads the legacy v1 record, retains
  unfinished deliveries, and prunes only explicit cancellation or observed
  native-finished records on a later start. A bounded 128 outstanding-record
  cap fails closed pending cleanup; it never evicts an unfinished purchase.
  No JWS or credential is stored. Without a matching original order snapshot,
  a recovered JWS can still reach the backend but cannot pass the client finish
  gate. Restored/fallback bindings must match account, order, product, token,
  transaction and exact credited coin amount. Order-number write/read syntax
  is identical to the backend response parser, including dots and hyphens.
- Logout/disposal or a changed authentication session invalidates the current
  in-flight handler before it can start payment or finish a late ACK. Apple
  financial POSTs do not retry automatically under a different login.

Residual limitation: a process death after the attempt marker but before a
provable native result can leave recharge blocked pending recovery/support.
This affects new iOS recharge only, not rooms, messaging, or wallet reads. It
must not be cleared on an arbitrary timeout or by treating empty history as a
negative payment proof. No real App Store purchase was performed to validate
this local implementation.

The recovery rules follow Apple's [appAccountToken association](https://developer.apple.com/documentation/storekit/transaction/appaccounttoken),
[pending purchase](https://developer.apple.com/documentation/storekit/product/purchaseresult/pending),
and [unfinished transaction](https://developer.apple.com/documentation/storekit/transaction/unfinished)
semantics. The paired ChatGPT review accepted this contract, not the final code;
independent code review and current-SHA verification remain required.

Native purchase success is not wallet authority. The wallet and double-entry
ledger remain server-owned and idempotent.

## Local and CI verification

`ios/RunnerTests/VoiceSocial.storekit` contains local consumables only.
The dedicated `RunnerStoreKitTests` scheme verifies catalog loading, an unfinished consumable, and Ask to Buy
decline behavior without App Store credentials. Flutter tests cover strict API
contracts, order/catalog binding, duplicate delivery, unfinished recovery, and
platform fail-closed behavior. The iOS workflow has read-only permissions and
must not commit, push, upload to App Store Connect, or mutate repository files.

The local `.storekit` file is bundled only in RunnerTests, not the release app.
The ordinary `Runner` scheme has no local StoreKit configuration. Debug
simulator builds alone use `RunnerDebug.entitlements` (`get-task-allow`);
Profile/Release and device builds never select that file. Tests run serially
with simulator ad-hoc signing enabled so embedded vendor frameworks can load.
Do not use `CODE_SIGNING_ALLOWED=NO` for the XCTest host.

If StoreKitTest's localhost service returns proxy 502, check loopback proxy
bypass entries rather than changing payment configuration. On the development
Mac, separate `localhost`, `127.0.0.1`, and `::1` exceptions were added while
preserving the existing proxy and its other rules.

## Release boundary

- `APPLE_IAP_TRANSACTION_UPDATES=IMPLEMENTED_IN_SOURCE`
- `APPLE_IAP_REAL_DEVICE_PURCHASE=EXTERNAL_BLOCKED`

The real-device purchase remains blocked until a production Bundle ID, Apple
Developer Team, distribution certificate, provisioning profile, App Store
Connect application, agreements/tax/banking state, and matching consumable
products exist. Sandbox/TestFlight evidence must bind the app build, backend
SHA, product IDs, transaction ID, one wallet credit, and one balanced ledger
journal before iOS can receive a Release Go decision.

The following accepted project exemptions are unchanged:

- `CHUANGLAN_DELIVERY_RECEIPT=EXEMPT_NOT_COMPLETED`
- `ALIPAY_ASYNC_CALLBACK=EXEMPT_NOT_COMPLETED`
- `ALIPAY_REFUND=EXEMPT_NOT_COMPLETED`
