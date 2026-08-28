import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'voice_social_app/alipay_app_pay_test',
  );

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('disabled adapter fails closed without invoking native code', () async {
    bool invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          invoked = true;
          return <String, Object?>{'status': 'success'};
        });

    final MethodChannelAlipayAppPayAdapter adapter =
        MethodChannelAlipayAppPayAdapter(
          channel: channel,
          enabled: false,
          isAndroid: () => true,
        );

    final AlipayAppPayResult result = await adapter.pay(
      orderNo: 'order-1',
      orderString: 'signed-order-payload',
    );

    expect(result.outcome, AlipayAppPayOutcome.unavailable);
    expect(result.reason, AlipayAppPayReason.disabled);
    expect(result.isProvisional, isTrue);
    expect(invoked, isFalse);
  });

  test(
    'non-Android adapter fails closed without invoking native code',
    () async {
      bool invoked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            invoked = true;
            return <String, Object?>{'status': 'success'};
          });

      final MethodChannelAlipayAppPayAdapter adapter =
          MethodChannelAlipayAppPayAdapter(
            channel: channel,
            enabled: true,
            isAndroid: () => false,
            consentChecker: () async => true,
          );

      final AlipayAppPayResult result = await adapter.pay(
        orderNo: 'order-1',
        orderString: 'signed-order-payload',
      );

      expect(result.outcome, AlipayAppPayOutcome.unavailable);
      expect(result.reason, AlipayAppPayReason.unsupportedPlatform);
      expect(invoked, isFalse);
    },
  );

  test(
    'native payment cannot run before app-owned consent is accepted',
    () async {
      bool invoked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            invoked = true;
            return <String, Object?>{'resultStatus': '9000'};
          });
      final MethodChannelAlipayAppPayAdapter adapter =
          MethodChannelAlipayAppPayAdapter(
            channel: channel,
            enabled: true,
            isAndroid: () => true,
            consentChecker: () async => false,
          );

      final AlipayAppPayResult result = await adapter.pay(
        orderNo: 'consent-order',
        orderString: 'signed-consent-order',
      );

      expect(result.outcome, AlipayAppPayOutcome.unavailable);
      expect(result.reason, AlipayAppPayReason.consentRequired);
      expect(invoked, isFalse);
    },
  );

  test(
    'native status mapping remains provisional for every vendor result',
    () async {
      final List<Object?> statuses = <Object?>[
        '9000',
        '8000',
        '6001',
        '6002',
        '6004',
        '4000',
        'not-a-status',
      ];
      final List<AlipayAppPayOutcome> outcomes = <AlipayAppPayOutcome>[
        AlipayAppPayOutcome.sdkCompleted,
        AlipayAppPayOutcome.processing,
        AlipayAppPayOutcome.userCanceled,
        AlipayAppPayOutcome.networkError,
        AlipayAppPayOutcome.processing,
        AlipayAppPayOutcome.failed,
        AlipayAppPayOutcome.failed,
      ];

      for (int index = 0; index < statuses.length; index += 1) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              expect(call.method, 'pay');
              expect(call.arguments, <String, Object?>{
                'orderStr': 'signed-order-${index + 1}',
                'sandbox': false,
              });
              return <String, Object?>{'resultStatus': statuses[index]};
            });

        final MethodChannelAlipayAppPayAdapter adapter =
            MethodChannelAlipayAppPayAdapter(
              channel: channel,
              enabled: true,
              isAndroid: () => true,
              consentChecker: () async => true,
            );
        final AlipayAppPayResult result = await adapter.pay(
          orderNo: 'order-${index + 1}',
          orderString: 'signed-order-${index + 1}',
        );

        expect(
          result.outcome,
          outcomes[index],
          reason: statuses[index].toString(),
        );
        expect(result.sdkCompleted, statuses[index] == '9000');
        expect(result.resultStatus, statuses[index].toString());
        expect(
          result.isSdkSuccess,
          statuses[index] == '9000',
          reason: statuses[index].toString(),
        );
        expect(result.isProvisional, isTrue);
        expect(result.vendorStatus, isNull);
        expect(result.toString(), isNot(contains(statuses[index].toString())));
      }
    },
  );

  test(
    'native PayResult keeps structured completion and raw result status',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            return <String, Object?>{
              'status': 'success',
              'sdkCompleted': true,
              'resultStatus': '9000',
            };
          });
      final MethodChannelAlipayAppPayAdapter adapter =
          MethodChannelAlipayAppPayAdapter(
            channel: channel,
            enabled: true,
            isAndroid: () => true,
            consentChecker: () async => true,
          );

      final AlipayAppPayResult result = await adapter.pay(
        orderNo: 'structured-result-order',
        orderString: 'signed-structured-result-order',
      );

      expect(result.outcome, AlipayAppPayOutcome.sdkCompleted);
      expect(result.sdkCompleted, isTrue);
      expect(result.resultStatus, '9000');
      expect(result.isSdkSuccess, isTrue);
    },
  );

  test('contradictory native completion evidence fails closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          return <String, Object?>{
            'sdkCompleted': false,
            'resultStatus': '9000',
          };
        });
    final MethodChannelAlipayAppPayAdapter adapter =
        MethodChannelAlipayAppPayAdapter(
          channel: channel,
          enabled: true,
          isAndroid: () => true,
          consentChecker: () async => true,
        );

    final AlipayAppPayResult result = await adapter.pay(
      orderNo: 'inconsistent-result-order',
      orderString: 'signed-inconsistent-result-order',
    );

    expect(result.outcome, AlipayAppPayOutcome.failed);
    expect(result.reason, AlipayAppPayReason.invalidResponse);
    expect(result.resultStatus, '9000');
    expect(result.sdkCompleted, isFalse);
    expect(result.isSdkSuccess, isFalse);
  });

  test(
    'legacy reduced success label cannot stand in for native resultStatus 9000',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            return <String, Object?>{'status': 'success'};
          });
      final MethodChannelAlipayAppPayAdapter adapter =
          MethodChannelAlipayAppPayAdapter(
            channel: channel,
            enabled: true,
            isAndroid: () => true,
            consentChecker: () async => true,
          );

      final AlipayAppPayResult result = await adapter.pay(
        orderNo: 'legacy-success-label-order',
        orderString: 'signed-legacy-success-label-order',
      );

      expect(result.sdkCompleted, isTrue);
      expect(result.resultStatus, 'success');
      expect(result.isSdkSuccess, isFalse);
    },
  );

  test('duplicate order invocation is single-flight', () async {
    int invocationCount = 0;
    final Completer<void> entered = Completer<void>();
    final Completer<Object?> response = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          invocationCount += 1;
          entered.complete();
          return response.future;
        });

    final MethodChannelAlipayAppPayAdapter adapter =
        MethodChannelAlipayAppPayAdapter(
          channel: channel,
          enabled: true,
          isAndroid: () => true,
          consentChecker: () async => true,
        );
    final Future<AlipayAppPayResult> first = adapter.pay(
      orderNo: 'order-1',
      orderString: 'signed-order-payload',
    );
    await entered.future;
    final Future<AlipayAppPayResult> second = adapter.pay(
      orderNo: 'order-1',
      orderString: 'signed-order-payload',
    );
    expect(identical(first, second), isTrue);
    response.complete(<String, Object?>{'status': 'processing'});
    expect((await first).outcome, AlipayAppPayOutcome.processing);
    expect(invocationCount, 1);
  });

  test('explicit sandbox mode is passed as a typed bridge boolean', () async {
    Object? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          arguments = call.arguments;
          return <String, Object?>{'resultStatus': '4000'};
        });

    final MethodChannelAlipayAppPayAdapter adapter =
        MethodChannelAlipayAppPayAdapter(
          channel: channel,
          enabled: true,
          sandbox: true,
          isAndroid: () => true,
          consentChecker: () async => true,
        );

    final AlipayAppPayResult result = await adapter.pay(
      orderNo: 'sandbox-order',
      orderString: 'signed-sandbox-order',
    );

    expect(result.outcome, AlipayAppPayOutcome.failed);
    expect(arguments, <String, Object?>{
      'orderStr': 'signed-sandbox-order',
      'sandbox': true,
    });
    expect(adapter.sandboxMode, isTrue);
  });

  test('same order with a different payload is rejected', () async {
    int invocationCount = 0;
    final Completer<void> entered = Completer<void>();
    final Completer<Object?> response = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          invocationCount += 1;
          entered.complete();
          return response.future;
        });

    final MethodChannelAlipayAppPayAdapter adapter =
        MethodChannelAlipayAppPayAdapter(
          channel: channel,
          enabled: true,
          isAndroid: () => true,
          consentChecker: () async => true,
        );
    final Future<AlipayAppPayResult> first = adapter.pay(
      orderNo: 'order-1',
      orderString: 'signed-order-a',
    );
    await entered.future;

    expect(
      () => adapter.pay(orderNo: 'order-1', orderString: 'signed-order-b'),
      throwsA(isA<ArgumentError>()),
    );
    expect(invocationCount, 1);
    response.complete(<String, Object?>{'status': 'processing'});
    expect((await first).outcome, AlipayAppPayOutcome.processing);
  });

  test(
    'completed SDK outcomes are removed so a cancelled payment can retry',
    () async {
      int invocationCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            invocationCount += 1;
            return <String, Object?>{
              'resultStatus': invocationCount == 1 ? '6001' : '6002',
            };
          });
      final MethodChannelAlipayAppPayAdapter adapter =
          MethodChannelAlipayAppPayAdapter(
            channel: channel,
            enabled: true,
            isAndroid: () => true,
            consentChecker: () async => true,
          );

      final AlipayAppPayResult first = await adapter.pay(
        orderNo: 'order-1',
        orderString: 'signed-order-payload',
      );
      await Future<void>.value();
      final AlipayAppPayResult second = await adapter.pay(
        orderNo: 'order-1',
        orderString: 'signed-order-payload',
      );

      expect(first.outcome, AlipayAppPayOutcome.userCanceled);
      expect(second.outcome, AlipayAppPayOutcome.networkError);
      expect(invocationCount, 2);
    },
  );

  test(
    'native activity errors and in-progress errors are fixed mappings',
    () async {
      final List<Object?> statuses = <Object?>[
        PlatformException(code: 'unavailable'),
        PlatformException(code: 'activity_unavailable'),
        PlatformException(code: 'payment_in_progress'),
      ];
      for (int index = 0; index < statuses.length; index += 1) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              throw statuses[index]!;
            });
        final MethodChannelAlipayAppPayAdapter adapter =
            MethodChannelAlipayAppPayAdapter(
              channel: channel,
              enabled: true,
              isAndroid: () => true,
              consentChecker: () async => true,
            );
        final AlipayAppPayResult result = await adapter.pay(
          orderNo: 'error-order-$index',
          orderString: 'signed-order-$index',
        );
        if (index < 2) {
          expect(result.outcome, AlipayAppPayOutcome.unavailable);
          expect(result.reason, AlipayAppPayReason.nativeUnavailable);
        } else {
          expect(result.outcome, AlipayAppPayOutcome.processing);
          expect(result.reason, AlipayAppPayReason.processing);
        }
      }
    },
  );

  test('native timeout maps to processing and can be retried', () async {
    int invocationCount = 0;
    final Completer<Object?> response = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          invocationCount += 1;
          if (invocationCount == 1) {
            return response.future;
          }
          throw PlatformException(code: 'payment_in_progress');
        });
    final MethodChannelAlipayAppPayAdapter adapter =
        MethodChannelAlipayAppPayAdapter(
          channel: channel,
          enabled: true,
          isAndroid: () => true,
          consentChecker: () async => true,
          nativeTimeout: const Duration(milliseconds: 1),
        );

    final AlipayAppPayResult timedOut = await adapter.pay(
      orderNo: 'order-timeout',
      orderString: 'signed-order-timeout',
    );
    expect(timedOut.outcome, AlipayAppPayOutcome.processing);
    expect(timedOut.reason, AlipayAppPayReason.timeout);
    expect(timedOut.sdkCompleted, isFalse);
    expect(timedOut.resultStatus, isNull);
    await Future<void>.value();
    final AlipayAppPayResult retry = await adapter.pay(
      orderNo: 'order-timeout',
      orderString: 'signed-order-timeout',
    );
    expect(retry.outcome, AlipayAppPayOutcome.processing);
    expect(retry.reason, AlipayAppPayReason.processing);
    expect(invocationCount, 2);
    response.complete(<String, Object?>{'resultStatus': '9000'});
  });

  test('missing plugin and malformed native responses fail closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => null);
    final MethodChannelAlipayAppPayAdapter adapter =
        MethodChannelAlipayAppPayAdapter(
          channel: channel,
          enabled: true,
          isAndroid: () => true,
          consentChecker: () async => true,
        );
    AlipayAppPayResult result = await adapter.pay(
      orderNo: 'order-1',
      orderString: 'signed-order-payload',
    );
    expect(result.outcome, AlipayAppPayOutcome.failed);
    expect(result.reason, AlipayAppPayReason.invalidResponse);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    result = await adapter.pay(
      orderNo: 'order-2',
      orderString: 'signed-order-payload',
    );
    expect(result.outcome, AlipayAppPayOutcome.unavailable);
    expect(result.reason, AlipayAppPayReason.missingPlugin);
  });

  test(
    'invalid order payload is rejected before crossing MethodChannel',
    () async {
      bool invoked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            invoked = true;
            return <String, Object?>{'status': 'success'};
          });
      final MethodChannelAlipayAppPayAdapter adapter =
          MethodChannelAlipayAppPayAdapter(
            channel: channel,
            enabled: true,
            isAndroid: () => true,
            consentChecker: () async => true,
          );

      for (final String payload in <String>['', ' signed', 'signed\norder']) {
        expect(
          () => adapter.pay(
            orderNo: 'order-${payload.length}',
            orderString: payload,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
      expect(invoked, isFalse);
    },
  );
}
