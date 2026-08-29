import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';

const String _runtimePortValue = String.fromEnvironment(
  'M5_ACTION_GATE_PORT',
  defaultValue: '0',
);
final int _runtimePort = int.tryParse(_runtimePortValue) ?? 0;
const String _runtimeTokenPath =
    '/data/user/0/com.kong373.voice_social_app/cache/m5-action-gate-token';
const String _runtimeTokenFallbackPath =
    '/data/data/com.kong373.voice_social_app/cache/m5-action-gate-token';
const String _runId = String.fromEnvironment(
  'M5_ACTION_RUN_ID',
  defaultValue: '',
);
const String _expectedBackendSha = String.fromEnvironment(
  'M5_EXPECTED_BACKEND_SHA',
  defaultValue: '',
);
const String _expectedFlutterSha = String.fromEnvironment(
  'M5_EXPECTED_FLUTTER_SHA',
  defaultValue: '',
);
const String _expectedSerial = String.fromEnvironment(
  'M5_EXPECTED_SERIAL',
  defaultValue: '',
);
const bool _allowExternalPayment = bool.fromEnvironment(
  'M5_ALLOW_EXTERNAL_PAYMENT',
  defaultValue: false,
);
const bool _enableAlipayAppPay = bool.fromEnvironment(
  'ENABLE_ALIPAY_APP_PAY',
  defaultValue: false,
);
const String _paymentConfirmation = String.fromEnvironment(
  'M5_PAYMENT_CONFIRMATION',
  defaultValue: '',
);
const String _successConfirmation = String.fromEnvironment(
  'M5_SUCCESS_CONFIRMATION',
  defaultValue: '',
);
const String _paymentScenario = String.fromEnvironment(
  'M5_ALIPAY_SCENARIO',
  defaultValue: 'none',
);
const Duration _confirmationTimeout = Duration(seconds: 120);
const String _expectedNativeBridgeOutcome = 'pay_task_returned';

final RegExp _sha1Pattern = RegExp(r'^[0-9a-f]{40}$');
final RegExp _runPattern = RegExp(r'^[A-Za-z0-9_.:-]{1,80}$');
final RegExp _serialPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

void _focusedMarker(String stage, String result) {
  debugPrint('M5_ALIPAY_FOCUSED::$stage::$result');
}

void _nativeResultMarker(RechargeOrder order) {
  debugPrint(
    'M5_ALIPAY_NATIVE_RESULT::sdkCompleted='
    '${order.sdkCompleted == true ? 1 : 0}::resultStatus='
    '${order.resultStatus ?? 'none'}',
  );
  debugPrint(
    'M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::'
    '${order.nativeBridgeOutcome ?? 'none'}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Alipay sandbox focused success requires action-time approval',
    (WidgetTester tester) async {
      final AppDependencies dependencies = AppDependencies.fromEnvironment();
      try {
        _validateConfiguration();
        final AuthController auth = dependencies.authController;
        await auth.initialize();
        if (auth.stage != AuthFlowStage.signedIn || auth.session == null) {
          throw TestFailure('A persisted authenticated session is required.');
        }
        final String account = auth.session!.mobile.trim();
        if (account.isEmpty) {
          throw TestFailure('The persisted session has no account identity.');
        }

        final repository = dependencies.commerceCatalogRepository;
        final List<RechargeProduct> products = await repository
            .fetchRechargeProducts(platform: ClientStorePlatform.android);
        if (products.isEmpty || !repository.supportsPaymentChannelInvocation) {
          throw TestFailure('The Alipay catalog is not payment-ready.');
        }
        final RechargeProduct? product = products
            .where(
              (RechargeProduct item) =>
                  item.enabled && (item.amountMinor ?? 0) > 0,
            )
            .fold<RechargeProduct?>(null, (
              RechargeProduct? current,
              RechargeProduct candidate,
            ) {
              if (current == null ||
                  (candidate.amountMinor ?? 0) < (current.amountMinor ?? 0)) {
                return candidate;
              }
              return current;
            });
        if (product == null) {
          throw TestFailure('The Alipay catalog has no safe positive product.');
        }
        _focusedMarker('catalog', 'PASS');

        final RechargeOrder order = await repository.createRechargeOrder(
          account: account,
          product: product,
          channel: PaymentChannelType.alipay,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        );
        final int? orderAmountMinor = order.product.amountMinor;
        if (order.orderNo.trim().isEmpty ||
            order.paymentOrderString?.isNotEmpty != true ||
            order.account != account ||
            order.product.id != product.id ||
            orderAmountMinor == null ||
            orderAmountMinor <= 0 ||
            orderAmountMinor != product.amountMinor ||
            order.product.totalGiftCoins <= 0 ||
            order.product.totalGiftCoins != product.totalGiftCoins ||
            order.channel != PaymentChannelType.alipay ||
            order.state != RechargeOrderState.created) {
          throw TestFailure('The server did not return a usable Alipay order.');
        }
        _focusedMarker('order', 'PASS');

        final Map<String, Object?> identity = await _requestConfirmation(order);
        _focusedMarker('action_confirmation', 'REQUIRED');
        if (!await _waitForConfirmation(identity)) {
          _focusedMarker('action_confirmation', 'FAIL');
          throw TestFailure(
            'Sandbox success action confirmation was not granted.',
          );
        }
        _focusedMarker('action_confirmation', 'GRANTED');

        _focusedMarker('native_launcher', 'START');
        final RechargeOrder result = await repository.invokePayment(order);
        _nativeResultMarker(result);
        final bool nativeSuccess =
            result.sdkCompleted == true &&
            result.resultStatus == '9000' &&
            result.nativeBridgeOutcome == _expectedNativeBridgeOutcome;
        if (!nativeSuccess) {
          _focusedMarker('native_launcher', 'FAIL');
          throw TestFailure('The native PayTask success result was rejected.');
        }
        _focusedMarker('native_launcher', 'PASS');

        if (result.state != RechargeOrderState.succeeded) {
          _focusedMarker('query_reconcile', 'FAIL');
          throw TestFailure('The first-party order did not confirm success.');
        }
        final RechargeOrder repeated = await repository.queryRechargeOrder(
          result.copyWith(state: RechargeOrderState.confirming),
        );
        if (repeated.state != RechargeOrderState.succeeded ||
            repeated.orderNo != result.orderNo) {
          _focusedMarker('query_reconcile', 'FAIL');
          throw TestFailure('The repeated authoritative query mismatched.');
        }
        _focusedMarker('query_reconcile', 'PASS');
        _focusedMarker('settlement', 'NOT_COLLECTED');
        _focusedMarker('complete', 'PASS');
        await tester.pump();
      } catch (_) {
        _focusedMarker('complete', 'FAIL');
        throw TestFailure('Alipay focused success evidence is incomplete.');
      } finally {
        dependencies.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
    skip: !Platform.isAndroid,
  );
}

void _validateConfiguration() {
  if (_runtimePort < 1 ||
      _runtimePort > 65535 ||
      !_runPattern.hasMatch(_runId) ||
      !_sha1Pattern.hasMatch(_expectedBackendSha) ||
      !_sha1Pattern.hasMatch(_expectedFlutterSha) ||
      _expectedSerial != 'emulator-5554' ||
      !_serialPattern.hasMatch(_expectedSerial) ||
      !_allowExternalPayment ||
      !_enableAlipayAppPay ||
      _paymentConfirmation != 'I_UNDERSTAND_SANDBOX_PAYMENT' ||
      _successConfirmation != 'I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT' ||
      _paymentScenario != 'success') {
    throw TestFailure('Alipay focused success configuration is invalid.');
  }
}

Future<String> _readRuntimeToken() async {
  for (int attempt = 0; attempt < 80; attempt += 1) {
    for (final String path in <String>[
      _runtimeTokenPath,
      _runtimeTokenFallbackPath,
    ]) {
      final File file = File(path);
      try {
        if (!await file.exists()) {
          continue;
        }
        final String token = (await file.readAsString()).trim();
        try {
          await file.delete();
        } on FileSystemException {
          // The token is already in memory; a concurrent feeder may remove it.
        }
        if (RegExp(r'^[A-Za-z0-9_-]{64,256}$').hasMatch(token)) {
          return token;
        }
      } on FileSystemException {
        // Retry without logging the token or the filesystem exception.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 125));
  }
  throw TestFailure('The action gate credential was unavailable.');
}

Future<Map<String, Object?>> _requestConfirmation(RechargeOrder order) async {
  final String token = await _readRuntimeToken();
  final int? amountMinor = order.product.amountMinor;
  if (amountMinor == null ||
      amountMinor <= 0 ||
      order.product.totalGiftCoins <= 0 ||
      order.account.trim().isEmpty ||
      order.product.id.trim().isEmpty ||
      order.channel != PaymentChannelType.alipay ||
      order.state != RechargeOrderState.created) {
    throw TestFailure('The authoritative order identity is invalid.');
  }
  final Map<String, Object?> identity = <String, Object?>{
    'runId': _runId,
    'avd': 'AVD-A',
    'serial': _expectedSerial,
    'backendSha': _expectedBackendSha,
    'flutterSha': _expectedFlutterSha,
    'orderNo': order.orderNo,
    'requestId': _actionRequestId(order),
    'account': order.account,
    'productId': order.product.id,
    'amountMinor': amountMinor,
    'giftCoinAmount': order.product.totalGiftCoins,
    'provider': 'ALIPAY',
    'status': 'CREATED',
  };
  final Map<String, Object?> response = await _postGate(
    token,
    '/m5/alipay/action-confirmation/request',
    identity,
  );
  if (response['accepted'] != true || response['status'] != 'PENDING') {
    throw TestFailure('The action gate did not accept the pending order.');
  }
  return <String, Object?>{...identity, '_token': token};
}

String _actionRequestId(RechargeOrder order) {
  final String canonical = <String>[
    'voice-social:alipay-focused-success-action',
    'run=$_runId',
    'serial=$_expectedSerial',
    'backend=$_expectedBackendSha',
    'flutter=$_expectedFlutterSha',
    'order=${order.orderNo}',
    'account=${order.account}',
    'product=${order.product.id}',
    'amount=${order.product.amountMinor}',
    'giftCoin=${order.product.totalGiftCoins}',
    'provider=ALIPAY',
    'status=CREATED',
  ].join('|');
  return 'alipay-action-${sha256.convert(utf8.encode(canonical))}';
}

Future<bool> _waitForConfirmation(Map<String, Object?> identity) async {
  final Object? rawToken = identity.remove('_token');
  if (rawToken is! String) {
    return false;
  }
  final Stopwatch stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < _confirmationTimeout) {
    try {
      final Map<String, Object?> response = await _postGate(
        rawToken,
        '/m5/alipay/action-confirmation/consume',
        identity,
      );
      if (response['approved'] == true) {
        return true;
      }
    } on Object {
      // The gate remains fail-closed while an operator approval is pending.
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

Future<Map<String, Object?>> _postGate(
  String token,
  String path,
  Map<String, Object?> payload,
) async {
  final List<int> encoded = utf8.encode(jsonEncode(payload));
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 3);
  try {
    final HttpClientRequest request = await client
        .post('10.0.2.2', _runtimePort, path)
        .timeout(const Duration(seconds: 3));
    request.followRedirects = false;
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..contentType = ContentType.json;
    request.contentLength = encoded.length;
    request.add(encoded);
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 3),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TestFailure('The action gate is not ready.');
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw TestFailure('The action gate response is invalid.');
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}
