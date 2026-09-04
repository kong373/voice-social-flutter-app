# Alipay App Pay formal-environment boundary

This document records the Flutter-side boundary for a controlled formal
Alipay App Pay verification. It does not contain an App ID, key, account,
signed order string, token, or callback credential, and it does not authorize a
real payment by itself.

## Build contract

The only supported formal build combination is:

```text
BACKEND_MODE=live
APP_ENV=production
ENABLE_ALIPAY_APP_PAY=true
API_BASE_URL=https://<authorized-first-party-host>/
OAUTH_CLIENT_ID=<public client identifier>
```

`AppEnvironment` derives `sandbox: false` for this combination. The Flutter
dependency graph passes that typed boolean to the Android bridge. The bridge
selects `EnvUtils.EnvEnum.ONLINE` immediately before each
`PayTask.payV2(...)` invocation, so a previous development/sandbox call cannot
silently carry over into a formal call. Production requires HTTPS and live
backend mode; `ALLOW_INSECURE_HTTP` is not a valid production override.

## Local formal acceptance lane (debug only)

The Android emulator reaches the host development backend through
`http://10.0.2.2:18080/`, while `APP_ENV=production` requires HTTPS. A single
controlled formal-wallet acceptance against that host may therefore use this
explicit, compile-time debug lane:

```text
BACKEND_MODE=live
APP_ENV=development   # or local
ALLOW_INSECURE_HTTP=true
ENABLE_ALIPAY_APP_PAY=true
ALIPAY_FORMAL_ACCEPTANCE=true
```

`ALIPAY_FORMAL_ACCEPTANCE` defaults to false and is accepted only when the
backend is live, the environment is explicitly local/development, the build
is non-release, and Alipay App Pay is enabled. In that narrow lane it selects
`sandbox: false` so the regular wallet can be exercised; it does not turn a
development backend into a production backend and does not carry any
credential. The flag is rejected in release builds, staging, production, mock
mode, or when Alipay App Pay is disabled. A formal release must use
`APP_ENV=production`, HTTPS, and the approved release backend configuration.

The client receives only the backend-issued signed order string. Alipay
private keys, public-key material used for server verification, merchant
credentials, and callback authority remain on the backend. The native result
is diagnostic/provisional only.

## Wallet boundary

Use the regular production Alipay wallet for a formal verification:

```text
com.eg.android.AlipayGphone
```

The sandbox wallet is a different package and is allowed only for local or
development builds whose bridge argument is `sandbox: true`:

```text
com.eg.android.AlipayGphoneRC
```

Never use the RC sandbox wallet for a formal result, and never use the regular
wallet to claim a sandbox result. The Flutter bridge does not select a wallet
by package name; the acceptance operator must verify the foreground package
and reject a mismatched wallet before any order is created.

## Authority and recovery

The formal payment sequence is:

```text
authenticated first-party catalog
→ first-party order creation
→ native PayTask (provisional result)
→ authenticated POST reconcile
→ DB-only GET order status
→ server-authoritative success/failure UI
```

Only the first-party backend may mark an order `SUCCEEDED`, credit the wallet,
or write the ledger. A native `resultStatus=9000` is never sufficient. The
client must also handle `6001`, processing/timeout, network failure, duplicate
callback, delayed callback, and process interruption by retrying the same
order's authoritative reconcile/status path. The signed `orderStr` must not
be persisted for recovery; an order number is sufficient to locate the
server-owned order.

## Signing and release status

The Flutter repository intentionally does not track a root Android host,
keystore, or signing properties. A debug-signed build can support a controlled
development/verification lane only when its package and certificate are the
ones registered for that lane. It is not a distributable formal release.

Before formal distribution, the release build must use a protected release
signer, and the exact certificate fingerprint must be registered against the
mobile application in the Alipay portal. The release signer must never be
committed, printed in CI logs, or placed in the APK as a secret.

## Minimum formal acceptance gates

1. Flutter format, analyze, and the full test suite pass.
2. A signed release artifact has package
   `com.kong373.voice_social_app`, the expected release certificate, no debug
   signer, no debug-only isolation Activity, and no client credential.
3. The backend reports the Alipay catalog/order capability as ready and its
   HTTPS callback endpoint is reachable.
4. A single explicitly bounded formal payment is performed with the regular
   wallet and an approved test account. The evidence binds one app build, one
   backend SHA, one order number, callback/query/reconcile results, one
   succeeded order, one wallet credit, and one balanced ledger journal.
5. Repeating callback/reconcile and reopening the order do not create a second
   credit. A cancellation or unknown result never creates a credit.

Until those gates are collected for the same artifact and backend candidate,
the status is `FORMAL_SWITCH_WIRED_BUT_PAYMENT_NOT_PROVEN`; this Flutter
change must not be reported as a completed production payment integration.
