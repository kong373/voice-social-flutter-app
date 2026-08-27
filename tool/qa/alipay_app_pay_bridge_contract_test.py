#!/usr/bin/env python3
"""Static contract checks for the generated-host Alipay bridge.

The checkout intentionally has no tracked Android host, so Kotlin compilation
is performed by Flutter's temporary host during an authorized Android build.
These checks make the security boundary reviewable without invoking a payment
or requiring an emulator.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT / "packages/alipay_app_pay"
KOTLIN = PLUGIN / "android/src/main/kotlin/com/kong373/alipay_app_pay/AlipayAppPayPlugin.kt"
GRADLE = PLUGIN / "android/build.gradle.kts"
DART = ROOT / "lib/features/commerce/infrastructure/alipay_app_pay_adapter.dart"
COMMERCE_REPOSITORY = ROOT / "lib/features/commerce/catalog/data/backend_commerce_catalog_repository.dart"
COMMERCE_MODELS = ROOT / "lib/features/commerce/catalog/domain/commerce_catalog_models.dart"
ALIPAY_REQUEST_IDS = ROOT / "lib/features/commerce/catalog/domain/alipay_request_id.dart"
PLUGIN_DART = PLUGIN / "lib/alipay_app_pay.dart"
ENVIRONMENT = ROOT / "lib/app/app_environment.dart"
LAUNCHER = ROOT / "tool/live_development.sh"


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"{label}: missing {needle!r}")


def main() -> int:
    kotlin = KOTLIN.read_text(encoding="utf-8")
    gradle = GRADLE.read_text(encoding="utf-8")
    dart = DART.read_text(encoding="utf-8")
    commerce_repository = COMMERCE_REPOSITORY.read_text(encoding="utf-8")
    commerce_models = COMMERCE_MODELS.read_text(encoding="utf-8")
    alipay_request_ids = ALIPAY_REQUEST_IDS.read_text(encoding="utf-8")
    environment = ENVIRONMENT.read_text(encoding="utf-8")
    launcher = LAUNCHER.read_text(encoding="utf-8")

    require(gradle, 'implementation("com.alipay.sdk:alipaysdk-android:15.8.42")', "SDK pin")
    require(kotlin, 'private const val CHANNEL = "voice_social_app/alipay_app_pay"', "channel")
    require(kotlin, 'call.method != "pay"', "method allowlist")
    require(kotlin, 'arguments["orderStr"]', "server order string input")
    require(kotlin, "PayTask(currentActivity).payV2(orderString, true)", "official SDK invocation")
    require(kotlin, "PAY_TIMEOUT_SECONDS = 120L", "bounded PayTask timeout")
    require(kotlin, "timeoutExecutor.schedule", "native timeout enforcement")
    for status in ("9000", "8000", "6001", "6002", "6004", "4000"):
        require(kotlin, f'"{status}"', f"status mapping {status}")
    require(kotlin, 'mapOf("status" to status)', "reduced callback")
    for forbidden in ("result[\"memo\"]", "result[\"result\"]", "result.success(raw)"):
        if forbidden in kotlin:
            raise AssertionError(f"native result leakage: {forbidden}")
    for forbidden in ("privateKey", "publicKey", "secretKey", "merchantId"):
        if forbidden in kotlin or forbidden in dart:
            raise AssertionError(f"client credential boundary: {forbidden}")

    require(environment, "ENABLE_ALIPAY_APP_PAY", "Dart feature flag")
    if not PLUGIN_DART.is_file():
        raise AssertionError(f"plugin package must contain a Dart library: {PLUGIN_DART}")
    require(commerce_repository, "_routes.reconcileAlipayRechargeOrder", "explicit reconcile route")
    require(commerce_repository, "_routes.cancelAlipayRechargeOrder", "explicit cancel route")
    require(commerce_repository, "_routes.createAlipayRechargeOrder", "explicit create route")
    require(commerce_repository, "'X-Request-Id': requestId", "stable create request id")
    require(commerce_repository, "_alipayCreateRequestIds", "retained create idempotency key")
    require(commerce_repository, "_pendingAlipayOrderCreations", "local create single-flight")
    require(commerce_repository, "_alipayReconcileRequestId", "stable reconcile request id")
    require(commerce_repository, "_alipayCancelRequestId", "stable cancel request id")
    require(commerce_repository, "_isTrustedNativeUserCancellation", "trusted local cancellation gate")
    require(commerce_repository, "_hasTrustedNativeCancellationEvidence", "trusted cancellation recovery gate")
    require(commerce_repository, ".withNativeBridgeResult(", "invoke native evidence normalization")
    require(commerce_models, "RechargeNativeCancellationEvidence", "normalized cancellation evidence")
    require(commerce_models, "withNativeBridgeResult", "native evidence normalization")
    require(commerce_models, "nativeCancellationEvidence", "persisted native cancellation evidence")
    require(commerce_models, "outcome == 'userCanceled'", "native cancellation outcome trust")
    require(commerce_models, "reason == 'userCanceled'", "native cancellation reason trust")
    require(commerce_repository, "_queryRechargeOrderStatus", "DB-only cancellation status read")
    require(commerce_repository, "queryRechargeOrder(provisional)", "GET status polling after reconcile")
    for field in ("responseProductId", "responseAmountMinor", "responseGiftCoinAmount"):
        require(commerce_repository, field, f"server order {field} validation")
    require(alipay_request_ids, "Random.secure()", "secure create request id")
    require(dart, "AlipayAppPayOutcome.sdkCompleted", "provisional SDK completion mapping")
    require(dart, "AlipayAppPayOutcome.processing", "provisional processing mapping")
    require(dart, "AlipayAppPayReason.missingPlugin", "missing-plugin fail closed")
    require(dart, "AlipayAppPayReason.consentRequired", "consent gate")
    require(dart, "_denyWithoutConsent", "consent defaults to deny")
    require(dart, "AlipayAppPayReason.nativeUnavailable", "native-unavailable fail closed")
    require(dart, "AlipayAppPayReason.timeout", "bounded native timeout")
    require(dart, ".timeout(_nativeTimeout)", "bounded MethodChannel future")
    require(dart, "sha256", "duplicate payload digest")
    require(launcher, "--enable-alipay-app-pay", "launcher opt-in")
    require(launcher, "--dart-define=ENABLE_ALIPAY_APP_PAY=", "launcher define")

    print("Alipay App Pay bridge contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
