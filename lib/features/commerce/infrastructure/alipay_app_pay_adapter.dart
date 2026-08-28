import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The result of the native Alipay SDK is deliberately not an authoritative
/// payment state.  The backend order endpoint must be queried before the app
/// presents a completed recharge or credits any balance.
enum AlipayAppPayOutcome {
  /// The SDK returned its success code. This is intentionally not named
  /// `success`: only the first-party order endpoint can authorize a payment.
  sdkCompleted,
  processing,
  userCanceled,
  networkError,
  failed,
  unavailable,
}

/// Safe reason values returned by the client-side bridge.
///
/// These are static classifications.  Vendor memo, signed order text and the
/// native result map are never copied into this object or logged.
enum AlipayAppPayReason {
  disabled,
  unsupportedPlatform,
  consentRequired,
  missingPlugin,
  invalidRequest,
  invalidResponse,
  userCanceled,
  network,
  vendorFailed,
  processing,
  timeout,
  nativeUnavailable,
}

/// Bounded, non-sensitive provenance for a native bridge result.
///
/// This is diagnostic evidence only. It never authorizes a payment, a
/// cancellation, or a wallet mutation. In particular, a native watchdog
/// result is intentionally distinct from a [PayTask] return with no usable
/// result status.
enum AlipayAppPayBridgeOutcome {
  payTaskReturned('pay_task_returned'),
  nativeWatchdogTimeout('native_watchdog_timeout'),
  nativeNotInvoked('native_not_invoked'),
  nativeException('native_exception'),
  nativeUnavailable('native_unavailable'),
  dartWatchdogTimeout('dart_watchdog_timeout');

  const AlipayAppPayBridgeOutcome(this.wireName);

  final String wireName;

  static AlipayAppPayBridgeOutcome? fromWire(Object? raw) {
    if (raw is! String) {
      return null;
    }
    for (final AlipayAppPayBridgeOutcome outcome
        in AlipayAppPayBridgeOutcome.values) {
      if (outcome.wireName == raw) {
        return outcome;
      }
    }
    return null;
  }
}

class AlipayAppPayResult {
  const AlipayAppPayResult({
    required this.outcome,
    required this.reason,
    bool? sdkCompleted,
    this.resultStatus,
    this.bridgeOutcome,
  }) : sdkCompleted =
           sdkCompleted ?? outcome == AlipayAppPayOutcome.sdkCompleted;

  final AlipayAppPayOutcome outcome;
  final AlipayAppPayReason reason;

  /// Whether the native SDK reported a completed invocation. This is
  /// structured bridge evidence only; it is never payment authority.
  final bool sdkCompleted;

  /// The native SDK's bounded, non-sensitive result status. The exact value
  /// is retained so an acceptance layer can distinguish a real `9000` from a
  /// cancellation, processing result, timeout, or an old bridge's label.
  final String? resultStatus;

  /// Safe provenance emitted by the native bridge. This value is intentionally
  /// a fixed vocabulary and contains no vendor response text or payment data.
  final AlipayAppPayBridgeOutcome? bridgeOutcome;

  /// Only the native success code is eligible to be paired with an
  /// authoritative backend success. This helper intentionally does not read
  /// or imply any account, wallet, or ledger state.
  bool get isSdkSuccess => sdkCompleted && resultStatus == '9000';

  /// Native results only describe what the SDK reported to the UI.  They are
  /// never sufficient to mark an order paid.
  bool get isProvisional => true;

  /// There is intentionally no vendor status, memo, signed order or amount
  /// on this public result type.
  String? get vendorStatus => null;

  @override
  String toString() =>
      'AlipayAppPayResult(outcome: ${outcome.name}, reason: ${reason.name}, '
      'provisional: true)';
}

abstract interface class AlipayAppPayAdapter {
  /// Whether the feature flag and current platform permit an invocation.
  bool get isAvailable;

  Future<AlipayAppPayResult> pay({
    required String orderNo,
    required String orderString,
  });
}

/// Used for every build where the feature is not explicitly enabled.
class DisabledAlipayAppPayAdapter implements AlipayAppPayAdapter {
  const DisabledAlipayAppPayAdapter();

  @override
  bool get isAvailable => false;

  @override
  Future<AlipayAppPayResult> pay({
    required String orderNo,
    required String orderString,
  }) async => const AlipayAppPayResult(
    outcome: AlipayAppPayOutcome.unavailable,
    reason: AlipayAppPayReason.disabled,
  );
}

/// Thin Dart side of the first-party Android bridge.
///
/// The Android implementation receives only a server-issued `orderStr` and
/// invokes the official `PayTask.payV2` SDK API.  It does not receive an app
/// private key, Alipay public key, amount, or any other credential.
class MethodChannelAlipayAppPayAdapter implements AlipayAppPayAdapter {
  MethodChannelAlipayAppPayAdapter({
    bool enabled = false,
    bool sandbox = false,
    MethodChannel? channel,
    bool Function()? isAndroid,
    Duration nativeTimeout = const Duration(minutes: 2),
    Future<bool> Function()? consentChecker,
  }) : _enabled = enabled,
       _sandbox = sandbox,
       _channel =
           channel ?? const MethodChannel('voice_social_app/alipay_app_pay'),
       _isAndroid = isAndroid ?? _defaultIsAndroid,
       _nativeTimeout = nativeTimeout,
       _consentChecker = consentChecker ?? _denyWithoutConsent {
    if (nativeTimeout <= Duration.zero) {
      throw ArgumentError.value(nativeTimeout, 'nativeTimeout', '必须大于零');
    }
  }

  static const int _maximumOrderStringLength = 64 * 1024;

  final bool _enabled;
  final bool _sandbox;
  final MethodChannel _channel;
  final bool Function() _isAndroid;
  final Duration _nativeTimeout;
  final Future<bool> Function() _consentChecker;
  // Keep only a digest while the native call is active. Retrying a completed
  // cancellation/network/SDK failure is allowed; backend order idempotency
  // remains the authority that prevents duplicate financial effects.
  final Map<String, _PendingPayment> _invocations = <String, _PendingPayment>{};

  @override
  bool get isAvailable => _enabled && _isAndroid();

  /// Whether this adapter requests the official native sandbox environment.
  /// This is a non-secret build/runtime classification only.
  bool get sandboxMode => _sandbox;

  @override
  Future<AlipayAppPayResult> pay({
    required String orderNo,
    required String orderString,
  }) {
    final String normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty || normalizedOrderNo.length > 128) {
      throw ArgumentError('订单号无效');
    }
    _validateOrderString(orderString);

    if (!_enabled) {
      return Future<AlipayAppPayResult>.value(
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.unavailable,
          reason: AlipayAppPayReason.disabled,
        ),
      );
    }
    if (!_isAndroid()) {
      return Future<AlipayAppPayResult>.value(
        const AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.unavailable,
          reason: AlipayAppPayReason.unsupportedPlatform,
        ),
      );
    }

    final String orderDigest = sha256
        .convert(utf8.encode(orderString))
        .toString();
    final _PendingPayment? existing = _invocations[normalizedOrderNo];
    if (existing != null) {
      if (existing.orderDigest != orderDigest) {
        throw ArgumentError('同一订单不能使用不同的服务端签名支付串');
      }
      return existing.future;
    }

    final Future<AlipayAppPayResult> nativeFuture = _invokeNative(orderString);
    late final _PendingPayment pending;
    final Future<AlipayAppPayResult> future = nativeFuture.whenComplete(() {
      if (identical(_invocations[normalizedOrderNo], pending)) {
        _invocations.remove(normalizedOrderNo);
      }
    });
    pending = _PendingPayment(orderDigest: orderDigest, future: future);
    _invocations[normalizedOrderNo] = pending;
    return future;
  }

  Future<AlipayAppPayResult> _invokeNative(String orderString) async {
    bool consentAccepted;
    try {
      consentAccepted = await _consentChecker();
    } catch (_) {
      return const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.unavailable,
        reason: AlipayAppPayReason.consentRequired,
      );
    }
    if (!consentAccepted) {
      return const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.unavailable,
        reason: AlipayAppPayReason.consentRequired,
      );
    }
    try {
      final Object? raw = await _channel
          .invokeMethod<Object?>('pay', <String, Object?>{
            'orderStr': orderString,
            'sandbox': _sandbox,
          })
          .timeout(_nativeTimeout);
      return _parseNativeResult(raw);
    } on TimeoutException {
      // The SDK may still be completing an app switch natively. Treat this as
      // unknown/processing and immediately let the order-status page ask the
      // backend authority; never present a client-side success.
      return const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.processing,
        reason: AlipayAppPayReason.timeout,
        bridgeOutcome: AlipayAppPayBridgeOutcome.dartWatchdogTimeout,
      );
    } on MissingPluginException {
      return const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.unavailable,
        reason: AlipayAppPayReason.missingPlugin,
      );
    } on PlatformException catch (error) {
      return _resultForPlatformError(error.code);
    } catch (_) {
      // Native exceptions are intentionally not reflected in the UI.  The
      // order remains pending until the first-party status endpoint decides.
      return const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.vendorFailed,
      );
    }
  }

  static AlipayAppPayResult _parseNativeResult(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.invalidResponse,
      );
    }
    final bool hasBridgeOutcome = raw.containsKey('bridgeOutcome');
    final AlipayAppPayBridgeOutcome? bridgeOutcome = hasBridgeOutcome
        ? AlipayAppPayBridgeOutcome.fromWire(raw['bridgeOutcome'])
        : null;
    if (hasBridgeOutcome && bridgeOutcome == null) {
      return const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.invalidResponse,
      );
    }
    // Prefer the raw SDK resultStatus when a bridge includes both it and a
    // reduced status label. This keeps the acceptance layer from mistaking
    // an old `status: success` label for proof of native 9000. A null
    // resultStatus is meaningful for a timeout/unavailable classification, so
    // retain that null instead of replacing it with the reduced label.
    final bool hasRawResultStatus =
        raw.containsKey('resultStatus') ||
        raw.containsKey('nativeResultStatus');
    final Object? rawResultStatus = raw.containsKey('resultStatus')
        ? raw['resultStatus']
        : raw['nativeResultStatus'];
    final String? resultStatus = hasRawResultStatus
        ? _safeResultStatus(rawResultStatus)
        : _safeResultStatus(raw['status'] ?? raw['outcome']);
    if (!hasRawResultStatus && resultStatus == null) {
      return const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.invalidResponse,
      );
    }
    if (hasRawResultStatus && rawResultStatus != null && resultStatus == null) {
      return const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.invalidResponse,
      );
    }
    final Object? rawSdkCompleted = raw['sdkCompleted'];
    if (rawSdkCompleted != null && rawSdkCompleted is! bool) {
      return AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.invalidResponse,
        sdkCompleted: false,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      );
    }
    final String? reducedStatus = _safeResultStatus(
      raw['status'] ?? raw['outcome'],
    );
    final String? classificationStatus = resultStatus ?? reducedStatus;
    if (classificationStatus == null) {
      return AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.invalidResponse,
        sdkCompleted: false,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      );
    }
    final String normalizedStatus = classificationStatus.toLowerCase();
    // A marker emitted by the current bridge must match that bridge's exact
    // fixed payload shape. This prevents any impossible provenance/status
    // combination (for example native_exception + 9000) from being treated as
    // SDK evidence. A missing marker remains the bounded legacy compatibility
    // path for bridge builds that predate provenance reporting.
    final bool bridgePayloadCompatible = switch (bridgeOutcome) {
      null => true,
      AlipayAppPayBridgeOutcome.payTaskReturned =>
        hasRawResultStatus && rawSdkCompleted is bool,
      AlipayAppPayBridgeOutcome.nativeWatchdogTimeout =>
        hasRawResultStatus &&
            rawSdkCompleted == false &&
            resultStatus == null &&
            normalizedStatus == 'processing',
      AlipayAppPayBridgeOutcome.nativeNotInvoked =>
        hasRawResultStatus &&
            rawSdkCompleted == false &&
            resultStatus == null &&
            normalizedStatus == 'unavailable',
      AlipayAppPayBridgeOutcome.nativeException =>
        hasRawResultStatus &&
            rawSdkCompleted == false &&
            resultStatus == null &&
            normalizedStatus == 'failed',
      AlipayAppPayBridgeOutcome.nativeUnavailable =>
        hasRawResultStatus &&
            rawSdkCompleted == false &&
            resultStatus == null &&
            normalizedStatus == 'unavailable',
      // This marker is produced by the Dart timeout branch directly and is
      // never a valid value returned over the native MethodChannel.
      AlipayAppPayBridgeOutcome.dartWatchdogTimeout => false,
    };
    if (!bridgePayloadCompatible) {
      return AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.invalidResponse,
        sdkCompleted: false,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      );
    }
    final bool statusImpliesSdkCompletion =
        normalizedStatus == '9000' || normalizedStatus == 'success';
    if (rawSdkCompleted != null &&
        rawSdkCompleted != statusImpliesSdkCompletion) {
      return AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.invalidResponse,
        sdkCompleted: false,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      );
    }
    final bool sdkCompleted =
        (rawSdkCompleted as bool?) ?? statusImpliesSdkCompletion;
    return switch (normalizedStatus) {
      'success' || '9000' => AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.sdkCompleted,
        reason: AlipayAppPayReason.processing,
        sdkCompleted: sdkCompleted,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      ),
      'processing' || '8000' || '6004' => AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.processing,
        reason: AlipayAppPayReason.processing,
        sdkCompleted: sdkCompleted,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      ),
      'payment_in_progress' => AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.processing,
        reason: AlipayAppPayReason.processing,
        sdkCompleted: sdkCompleted,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      ),
      'user_canceled' ||
      'canceled' ||
      'cancelled' ||
      '6001' => AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.userCanceled,
        reason: AlipayAppPayReason.userCanceled,
        sdkCompleted: sdkCompleted,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      ),
      'network_error' || 'network' || '6002' => AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.networkError,
        reason: AlipayAppPayReason.network,
        sdkCompleted: sdkCompleted,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      ),
      'failed' || '4000' => AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.vendorFailed,
        sdkCompleted: sdkCompleted,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      ),
      'unavailable' || 'activity_unavailable' => AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.unavailable,
        reason: AlipayAppPayReason.nativeUnavailable,
        sdkCompleted: sdkCompleted,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      ),
      'timeout' => AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.processing,
        reason: AlipayAppPayReason.timeout,
        sdkCompleted: sdkCompleted,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      ),
      _ => AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.invalidResponse,
        sdkCompleted: false,
        resultStatus: resultStatus,
        bridgeOutcome: bridgeOutcome,
      ),
    };
  }

  static String? _safeResultStatus(Object? raw) {
    final String status = raw?.toString().trim() ?? '';
    if (status.isEmpty ||
        status.length > 32 ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(status)) {
      return null;
    }
    return status;
  }

  static AlipayAppPayResult _resultForPlatformError(String code) {
    return switch (code.trim().toLowerCase()) {
      'user_canceled' || 'canceled' || 'cancelled' => const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.userCanceled,
        reason: AlipayAppPayReason.userCanceled,
      ),
      'network' || 'network_error' => const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.networkError,
        reason: AlipayAppPayReason.network,
      ),
      'payment_in_progress' => const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.processing,
        reason: AlipayAppPayReason.processing,
      ),
      'unavailable' || 'activity_unavailable' => const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.unavailable,
        reason: AlipayAppPayReason.nativeUnavailable,
      ),
      'timeout' => const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.processing,
        reason: AlipayAppPayReason.timeout,
      ),
      _ => const AlipayAppPayResult(
        outcome: AlipayAppPayOutcome.failed,
        reason: AlipayAppPayReason.vendorFailed,
      ),
    };
  }

  static void _validateOrderString(String orderString) {
    if (orderString.isEmpty ||
        orderString.length > _maximumOrderStringLength ||
        orderString.trim() != orderString ||
        orderString.codeUnits.any(_isControlCodeUnit)) {
      throw ArgumentError('服务端支付串无效');
    }
  }

  static bool _isControlCodeUnit(int codeUnit) =>
      codeUnit < 0x20 || codeUnit == 0x7f;

  static bool _defaultIsAndroid() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> _denyWithoutConsent() async => false;
}

class _PendingPayment {
  const _PendingPayment({required this.orderDigest, required this.future});

  final String orderDigest;
  final Future<AlipayAppPayResult> future;
}
