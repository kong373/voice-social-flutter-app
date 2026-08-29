import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/alipay_focused_smoke_selection.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';

const String _expectedNativeResultStatus = '6001';
const String _expectedBridgeOutcome = 'pay_task_returned';

void _focusedMarker(String stage, String result) {
  // Keep the evidence vocabulary fixed and free of order/account data. The
  // shell harness stores only these markers, never the Flutter tool's raw log.
  debugPrint('M5_ALIPAY_FOCUSED::$stage::$result');
}

void _nativeResultMarker(AlipayAppPayResult result) {
  final String status = result.resultStatus ?? 'none';
  final String bridgeOutcome = result.bridgeOutcome?.wireName ?? 'none';
  debugPrint(
    'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=${result.sdkCompleted ? 1 : 0}::'
    'resultStatus=$status',
  );
  debugPrint('M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::$bridgeOutcome');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Alipay sandbox focused smoke is cancel-only and authority-first',
    (WidgetTester tester) async {
      // This target intentionally starts from the persisted session. It never
      // renders the login gate, sends an SMS, or initializes Tencent IM.
      final AppDependencies dependencies = AppDependencies.fromEnvironment();
      try {
        if (!Platform.isAndroid ||
            !dependencies.environment.isLive ||
            !dependencies.environment.enableAlipayAppPay ||
            !dependencies.environment.useAlipaySandbox) {
          throw TestFailure('Alipay focused smoke configuration is invalid.');
        }

        await dependencies.authController.initialize();
        if (dependencies.authController.stage != AuthFlowStage.signedIn ||
            dependencies.authController.session == null) {
          throw TestFailure('A persisted authenticated session is required.');
        }
        final session = dependencies.authController.session!;
        if (session.mobile.trim().isEmpty) {
          throw TestFailure('The persisted session has no account identity.');
        }

        final repository = dependencies.commerceCatalogRepository;
        final List<RechargeProduct> products = await repository
            .fetchRechargeProducts(platform: ClientStorePlatform.android);
        if (products.isEmpty || !repository.supportsPaymentChannelInvocation) {
          throw TestFailure('The Alipay catalog is not payment-ready.');
        }
        _focusedMarker('catalog', 'PASS');

        final RechargeProduct? product =
            selectLowestPositiveEnabledRechargeProduct(products);
        if (product == null) {
          throw TestFailure(
            'The Alipay catalog has no enabled positive amountMinor product.',
          );
        }
        final RechargeOrder order = await repository.createRechargeOrder(
          account: session.mobile,
          product: product,
          channel: PaymentChannelType.alipay,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        );
        final String? serverOrderString = order.paymentOrderString;
        if (order.orderNo.trim().isEmpty ||
            serverOrderString == null ||
            serverOrderString.isEmpty) {
          throw TestFailure('The server did not return a usable Alipay order.');
        }
        // Do not print, persist, or include the signed order string in an
        // evidence marker. It is held only until the native call below.
        _focusedMarker('order', 'PASS');

        _focusedMarker('native_launcher', 'START');
        final AlipayAppPayResult nativeResult = await dependencies
            .alipayAppPayAdapter
            .pay(orderNo: order.orderNo, orderString: serverOrderString);
        _nativeResultMarker(nativeResult);

        // This is deliberately a cancellation-only lane. A 9000 result,
        // sdkCompleted=true, missing status, timeout, or any other bridge
        // outcome fails closed and is never treated as payment success.
        final bool trustedCancellation =
            nativeResult.sdkCompleted == false &&
            nativeResult.resultStatus == _expectedNativeResultStatus &&
            nativeResult.outcome == AlipayAppPayOutcome.userCanceled &&
            nativeResult.reason == AlipayAppPayReason.userCanceled &&
            nativeResult.bridgeOutcome?.wireName == _expectedBridgeOutcome;
        if (!trustedCancellation) {
          throw TestFailure(
            'The native PayTask cancellation marker was rejected.',
          );
        }
        _focusedMarker('native_launcher', 'PASS');

        final RechargeOrder provisional = order
            .copyWith(state: RechargeOrderState.confirming)
            .withNativeBridgeResult(
              sdkCompleted: nativeResult.sdkCompleted,
              resultStatus: nativeResult.resultStatus,
              outcome: nativeResult.outcome.name,
              reason: nativeResult.reason.name,
              bridgeOutcome: nativeResult.bridgeOutcome?.wireName,
            );
        final RechargeOrder authoritative = await repository.queryRechargeOrder(
          provisional,
        );
        if (authoritative.state != RechargeOrderState.canceled) {
          throw TestFailure(
            'The first-party order status did not confirm cancellation.',
          );
        }
        _focusedMarker('query_reconcile', 'PASS');
        _focusedMarker('complete', 'PASS');
        await tester.pump();
      } catch (_) {
        // Never re-emit vendor/backend exception text: it could contain signed
        // order material. The fixed marker is enough for the shell verdict.
        _focusedMarker('complete', 'FAIL');
        throw TestFailure('Alipay focused smoke evidence is incomplete.');
      } finally {
        dependencies.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
    skip: !Platform.isAndroid,
  );
}
