# Alipay App Pay Android bridge

This repository uses a small first-party Flutter plugin at
`packages/alipay_app_pay`. The plugin is Android-only and pins the official
Alipay Android SDK (`com.alipay.sdk:alipaysdk-android:15.8.42`). It exposes one
MethodChannel operation:

```text
channel: voice_social_app/alipay_app_pay
method: pay
arguments: {
  orderStr: <server-issued signed order string>,
  sandbox: <typed boolean>
}
```

The Dart side obtains `orderStr` only from the authenticated first-party
backend order response. Before invoking the bridge, it validates the returned
product ID, integer amount, and total gift-coin amount against the selected
server catalog item. The repository also keeps an opaque, cryptographically
random `X-Request-Id` for each account/product/platform creation intent. The
intent key is a local SHA-256 digest, so ambiguous create responses and
timeouts reuse the same backend idempotency boundary; concurrent calls are
coalesced and a valid create response closes that intent. Neither the key nor
the intent digest contains `orderStr`, and neither is logged. The Android side
calls `PayTask.payV2(orderStr, true)` on
a worker thread and returns a reduced status classification. SDK `memo` and
`result` values are intentionally discarded. The status is always provisional:
the app first calls the authenticated
`POST /app-economy-api/pay/ali/order/reconcile?orderNo=...` route with a stable
`X-Request-Id`, then polls the DB-only
`GET /app-economy-api/pay/ali/order/status?orderNo=...` projection before
showing a successful recharge or changing a balance.

The same recovery sequence is used by `queryRechargeOrder` for a non-terminal
Alipay order, including a manual result-page refresh after an app restart. The
reconcile POST is best effort and is followed by the GET even when it fails;
terminal Alipay orders and non-Alipay orders use only their read-only status
projection.

Both the Dart MethodChannel future and the Android `PayTask` worker have a
two-minute bound. A timeout is classified as unknown/processing and still goes
through explicit reconciliation and then the backend order-status authority;
it is never a client success. A completed native attempt is removed from Dart's
active single-flight map so a cancellation or transport failure can be retried
against the same backend order number. The native side retains its active lock
until a timed-out `PayTask` actually returns, preventing a second native call
while the first one is still running.

The bridge contains no Alipay app private key, public key, certificate, amount
calculation, merchant credential, or callback authority. The feature is
disabled by default and is only wired when `ENABLE_ALIPAY_APP_PAY=true` and
the app is running on Android. Missing plugin, missing Activity, malformed
order strings, unsupported platforms, and a missing app-owned v2 consent
acknowledgement fail closed. The native call cannot cross the MethodChannel
until that consent is accepted.

## Temporary Android host injection

The Flutter checkout intentionally does not track a root `android/` directory.
`tool/live_development.sh` creates a temporary Android host, overlays the
tracked checkout, runs `flutter pub get`, and removes the host when the command
ends. Because `alipay_app_pay` is a path Flutter plugin dependency, Flutter's
plugin loader discovers the plugin and its Android manifest/source
automatically. No source copy, private key, certificate, or Gradle property is
written to the checkout.

After a generated-host build, inspect the Gradle merged manifest (for example
`app/build/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml`):
the official AAR must contribute `H5PayActivity` and its companion activities
with the pinned exported flags. Run
`python3 tool/qa/alipay_android_manifest_contract_test.py --merged-manifest <path>`.
The plugin itself declares only `android.permission.INTERNET`; it does not add
storage, device, or `QUERY_ALL_PACKAGES` permissions.

Use the wrapper with the explicit opt-in only for an authorized Android
development/sandbox run:

```bash
export API_BASE_URL=http://10.0.2.2:18080/
export OAUTH_CLIENT_ID=voice-social-mobile-public
./tool/live_development.sh build-apk \
  --target android-emulator \
  --enable-alipay-app-pay
```

The wrapper accepts no Alipay credential or arbitrary Dart/Gradle define. A
generated host that is built manually must retain the plugin dependency and
official Maven artifact above; do not paste the bridge into `MainActivity` or
add keys to `local.properties`, Gradle arguments, resources, or the APK.

## Provisional status mapping

| SDK `resultStatus` | UI classification | Authority |
| --- | --- | --- |
| `9000` | SDK completed, awaiting confirmation | First-party order status |
| `8000` | processing | First-party order status |
| `6001` | user canceled | First-party order status |
| `6002` | network error | First-party order status |
| `6004` | unknown/processing | First-party order status |
| `4000` or unknown | failed/invalid | First-party order status |

Native bridge errors `unavailable` and `activity_unavailable` stay unavailable;
`payment_in_progress` stays processing. A Dart timeout is also processing with
an explicit timeout reason. None of these classifications authorizes a
balance change.

For an explicitly enabled live local/development build, the Flutter environment
derives `sandbox: true` and passes that typed boolean through the MethodChannel.
The Android bridge accepts no string or numeric truthy values. Before the
official `PayTask.payV2` call it selects `EnvUtils.EnvEnum.SANDBOX`, and only
debuggable host applications may use that mode. Staging and production always
pass `sandbox: false`; the native bridge does not call `setEnv` for those
invocations, so production builds cannot inherit a sandbox opt-in.

The native callback is delivered at most once for an invocation. Dart keeps a
single-flight result per order number and stores only a SHA-256 digest of the
signed order string for duplicate-payload detection. No payment database write
occurs in the Flutter bridge; all order and balance writes belong to the
authenticated backend and its verified provider callback/query flow. The GET
status projection never invokes Alipay or settles an order; only the explicit
reconcile POST may perform provider reconciliation.

No real or sandbox payment is initiated by the bridge tests.
