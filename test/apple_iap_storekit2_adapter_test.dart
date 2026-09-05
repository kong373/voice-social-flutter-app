import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/apple_iap_storekit2_adapter.dart';

void main() {
  const String productId = 'com.kong373.voiceSocialApp.recharge.60';
  const String appAccountToken = '11111111-1111-4111-8111-111111111111';

  test(
    'native timeout keeps the underlying purchase in flight and publishes its late transaction',
    () async {
      final Completer<Object?> nativeResponse = Completer<Object?>();
      int purchaseCalls = 0;
      final MethodChannelAppleIapStoreKit2Adapter adapter =
          MethodChannelAppleIapStoreKit2Adapter(
            isIos: () => true,
            nativeTimeout: const Duration(milliseconds: 1),
            transactionEventStream: Stream<Object?>.empty(),
            invoker: (String method, Map<String, Object?> arguments) {
              expect(method, 'purchase');
              purchaseCalls += 1;
              return nativeResponse.future;
            },
          );

      final Completer<AppleIapTransaction> lateTransaction =
          Completer<AppleIapTransaction>();
      final StreamSubscription<AppleIapTransaction> transactionSubscription =
          adapter.transactionUpdates.listen((AppleIapTransaction transaction) {
            if (!lateTransaction.isCompleted) {
              lateTransaction.complete(transaction);
            }
          });
      final Future<AppleIapPurchaseResult> firstPurchase = adapter.purchase(
        productId: productId,
        appAccountToken: appAccountToken,
      );
      await expectLater(
        firstPurchase,
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.timeout,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('outcome is unknown'),
              ),
        ),
      );

      final AppleIapPurchaseResult inFlight = await adapter.purchase(
        productId: productId,
        appAccountToken: appAccountToken,
      );
      expect(inFlight.outcome, AppleIapPurchaseOutcome.pending);
      expect(inFlight.reason, 'native_purchase_in_flight');
      expect(
        (await adapter.readRetainedPurchaseOutcome(
          productId: productId,
          appAccountToken: appAccountToken,
        ))?.reason,
        'native_purchase_in_flight',
      );
      expect(purchaseCalls, 1);

      nativeResponse.complete(<String, Object?>{
        'outcome': 'transaction',
        'transaction': _rawTransaction(source: 'purchase'),
      });

      final AppleIapTransaction transaction = await lateTransaction.future;
      expect(transaction.transactionId, '100000000000001');
      expect(transaction.verification, AppleIapVerification.verified);

      final AppleIapPurchaseResult replay = await adapter.purchase(
        productId: productId,
        appAccountToken: appAccountToken,
      );
      expect(replay.outcome, AppleIapPurchaseOutcome.transaction);
      expect(replay.transaction?.transactionId, '100000000000001');
      expect(purchaseCalls, 1);
      expect(
        await adapter.readRetainedPurchaseOutcome(
          productId: productId,
          appAccountToken: appAccountToken,
        ),
        same(replay),
      );

      await transactionSubscription.cancel();
    },
  );

  test(
    'late native cancellation resolves uncertainty without a transaction update',
    () async {
      final Completer<Object?> firstNativeResponse = Completer<Object?>();
      int purchaseCalls = 0;
      final MethodChannelAppleIapStoreKit2Adapter adapter =
          MethodChannelAppleIapStoreKit2Adapter(
            isIos: () => true,
            nativeTimeout: const Duration(milliseconds: 1),
            transactionEventStream: Stream<Object?>.empty(),
            invoker: (String method, Map<String, Object?> arguments) {
              expect(method, 'purchase');
              purchaseCalls += 1;
              return purchaseCalls == 1
                  ? firstNativeResponse.future
                  : Future<Object?>.value(<String, Object?>{
                      'outcome': 'user_cancelled',
                    });
            },
          );
      final List<AppleIapTransaction> transactions = <AppleIapTransaction>[];
      final StreamSubscription<AppleIapTransaction> transactionSubscription =
          adapter.transactionUpdates.listen(transactions.add);
      await expectLater(
        adapter.purchase(
          productId: productId,
          appAccountToken: appAccountToken,
        ),
        throwsA(isA<ApiException>()),
      );

      final AppleIapPurchaseResult inFlight = await adapter.purchase(
        productId: productId,
        appAccountToken: appAccountToken,
      );
      expect(inFlight.outcome, AppleIapPurchaseOutcome.pending);
      expect(inFlight.reason, 'native_purchase_in_flight');

      firstNativeResponse.complete(<String, Object?>{
        'outcome': 'user_cancelled',
      });
      await Future<void>.delayed(Duration.zero);

      final AppleIapPurchaseResult cancellation = await adapter.purchase(
        productId: productId,
        appAccountToken: appAccountToken,
      );
      expect(cancellation.outcome, AppleIapPurchaseOutcome.userCancelled);
      expect(transactions, isEmpty);

      final AppleIapPurchaseResult replay = await adapter.purchase(
        productId: productId,
        appAccountToken: appAccountToken,
      );
      expect(replay.outcome, AppleIapPurchaseOutcome.userCancelled);
      expect(purchaseCalls, 1);

      await transactionSubscription.cancel();
    },
  );

  test(
    'ordinary native pending is retained and cannot start a second purchase',
    () async {
      int purchaseCalls = 0;
      final MethodChannelAppleIapStoreKit2Adapter adapter =
          MethodChannelAppleIapStoreKit2Adapter(
            isIos: () => true,
            transactionEventStream: Stream<Object?>.empty(),
            invoker: (String method, Map<String, Object?> arguments) {
              purchaseCalls += 1;
              return Future<Object?>.value(<String, Object?>{
                'outcome': 'pending',
              });
            },
          );

      final AppleIapPurchaseResult first = await adapter.purchase(
        productId: productId,
        appAccountToken: appAccountToken,
      );
      final AppleIapPurchaseResult second = await adapter.purchase(
        productId: productId,
        appAccountToken: appAccountToken,
      );

      expect(first.outcome, AppleIapPurchaseOutcome.pending);
      expect(first.reason, 'pending');
      expect(second.outcome, AppleIapPurchaseOutcome.pending);
      expect(second.reason, 'pending');
      expect(purchaseCalls, 1);
      expect(
        (await adapter.readRetainedPurchaseOutcome(
          productId: productId,
          appAccountToken: appAccountToken,
        ))?.reason,
        'pending',
      );

      final AppleIapPurchaseResult freshBinding = await adapter.purchase(
        productId: productId,
        appAccountToken: '22222222-2222-4222-8222-222222222222',
      );
      expect(freshBinding.outcome, AppleIapPurchaseOutcome.pending);
      expect(purchaseCalls, 2);
    },
  );

  test(
    'native errors are retained fail-closed and never retried for the same binding',
    () async {
      int purchaseCalls = 0;
      final MethodChannelAppleIapStoreKit2Adapter adapter =
          MethodChannelAppleIapStoreKit2Adapter(
            isIos: () => true,
            transactionEventStream: Stream<Object?>.empty(),
            invoker: (String method, Map<String, Object?> arguments) {
              purchaseCalls += 1;
              return Future<Object?>.error(StateError('native unavailable'));
            },
          );

      await expectLater(
        adapter.purchase(
          productId: productId,
          appAccountToken: appAccountToken,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        adapter.purchase(
          productId: productId,
          appAccountToken: appAccountToken,
        ),
        throwsA(isA<StateError>()),
      );
      expect(purchaseCalls, 1);
      expect(
        (await adapter.readRetainedPurchaseOutcome(
          productId: productId,
          appAccountToken: appAccountToken,
        ))?.reason,
        'native_purchase_unknown',
      );
    },
  );

  test(
    'transaction updates can cancel and relisten when the injected source is single-subscription',
    () async {
      final StreamController<Object?> source = StreamController<Object?>();
      addTearDown(source.close);
      final MethodChannelAppleIapStoreKit2Adapter adapter =
          MethodChannelAppleIapStoreKit2Adapter(
            isIos: () => true,
            transactionEventStream: source.stream,
          );

      final Completer<AppleIapTransaction> firstEvent =
          Completer<AppleIapTransaction>();
      final StreamSubscription<AppleIapTransaction> firstSubscription = adapter
          .transactionUpdates
          .listen((AppleIapTransaction transaction) {
            if (!firstEvent.isCompleted) {
              firstEvent.complete(transaction);
            }
          });
      source.add(_rawTransaction(source: 'updates'));
      expect((await firstEvent.future).transactionId, '100000000000001');
      await firstSubscription.cancel();

      final Completer<AppleIapTransaction> secondEvent =
          Completer<AppleIapTransaction>();
      final StreamSubscription<AppleIapTransaction> secondSubscription = adapter
          .transactionUpdates
          .listen((AppleIapTransaction transaction) {
            if (!secondEvent.isCompleted) {
              secondEvent.complete(transaction);
            }
          });
      source.add(
        _rawTransaction(source: 'updates', transactionId: '100000000000002'),
      );
      expect((await secondEvent.future).transactionId, '100000000000002');
      await secondSubscription.cancel();
    },
  );
}

Map<String, Object?> _rawTransaction({
  required String source,
  String transactionId = '100000000000001',
}) => <String, Object?>{
  'transactionId': transactionId,
  'originalTransactionId': transactionId,
  'productId': 'com.kong373.voiceSocialApp.recharge.60',
  'appAccountToken': '11111111-1111-4111-8111-111111111111',
  'purchaseDate': '2026-09-04T00:00:00.000Z',
  'signedTransaction': 'header.payload.signature',
  'verification': 'verified',
  'source': source,
};
