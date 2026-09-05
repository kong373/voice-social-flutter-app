import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/commerce/data/apple_iap_purchase_journal.dart';
import 'package:voice_social_app/features/commerce/application/apple_iap_purchase_coordinator.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/apple_iap_storekit2_adapter.dart';

final Object _testSession = Object();

void main() {
  group('AppleIapPurchaseCoordinator', () {
    test(
      'loaded journal still fences account switch or disposal before create POST',
      () async {
        for (final bool dispose in <bool>[false, true]) {
          Object session = Object();
          String account = 'account-a';
          final backend = _FakeBackend();
          final coordinator = AppleIapPurchaseCoordinator(
            purchaseStore: MemoryKeyValueStore(),
            authenticatedAccount: () => account,
            authenticatedSession: () => session,
            storeKit: _FakeStoreKit(),
            backend: backend,
          );
          await coordinator.recoverUnfinished();
          final pending = coordinator.createOrder(
            productId: _binding.productId,
            requestId: 'journal-fast-path',
          );
          final rejection = expectLater(
            pending,
            throwsA(dispose ? isA<StateError>() : isA<ApiException>()),
          );
          if (dispose) {
            await coordinator.dispose();
          } else {
            account = 'account-b';
            session = Object();
          }
          await rejection;
          expect(backend.createCalls, 0);
          await coordinator.dispose();
        }
      },
    );

    test(
      'late retained cancellation unlocks recovery without another native call',
      () async {
        final store = MemoryKeyValueStore();
        final native = _RecoverableFakeStoreKit();
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: store,
          authenticatedAccount: () => 'test-account',
          authenticatedSession: () => _testSession,
          storeKit: native,
          backend: _FakeBackend(),
        );
        expect(
          (await _purchase(coordinator)).state,
          AppleIapPurchaseFlowState.awaitingBackend,
        );
        native.retained = const AppleIapPurchaseResult(
          outcome: AppleIapPurchaseOutcome.userCancelled,
        );
        expect((await coordinator.recoverUnfinished()).deferred, 0);
        expect(
          (await AppleIapPurchaseJournal(store).read('test-account'))?.state,
          'CANCELLED_CONFIRMED',
        );
        expect(native.purchaseCalls, 1);
        await coordinator.dispose();
      },
    );

    test(
      'restart with an attempted purchase never repeats native purchase',
      () async {
        final store = MemoryKeyValueStore();
        await AppleIapPurchaseJournal(store).start('test-account', _binding);
        final native = _FakeStoreKit();
        final backend = _FakeBackend();
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: store,
          authenticatedAccount: () => 'test-account',
          authenticatedSession: () => _testSession,
          storeKit: native,
          backend: backend,
        );
        final recovery = await coordinator.recoverUnfinished();
        expect(recovery.deferred, greaterThan(0));
        final order = await coordinator.createOrder(
          productId: _binding.productId,
          requestId: 'after-restart',
        );
        final flow = await coordinator.purchase(order);
        expect(flow.state, AppleIapPurchaseFlowState.awaitingBackend);
        expect(backend.createCalls, 0);
        expect(native.purchaseCalls, 0);
        expect(
          (await AppleIapPurchaseJournal(store).read('test-account'))?.state,
          'ATTEMPTED',
        );
        await coordinator.dispose();
      },
    );

    test(
      'storage failure prevents native purchase before any charge attempt',
      () async {
        final native = _FakeStoreKit();
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: _FailingWriteStore(),
          authenticatedAccount: () => 'test-account',
          authenticatedSession: () => _testSession,
          storeKit: native,
          backend: _FakeBackend(),
        );
        await expectLater(_purchase(coordinator), throwsStateError);
        expect(native.purchaseCalls, 0);
        await coordinator.dispose();
      },
    );

    test(
      'explicit cancellation is durable before the order is unlocked',
      () async {
        final store = MemoryKeyValueStore();
        final native = _FakeStoreKit(
          purchaseResult: const AppleIapPurchaseResult(
            outcome: AppleIapPurchaseOutcome.userCancelled,
          ),
        );
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: store,
          authenticatedAccount: () => 'test-account',
          authenticatedSession: () => _testSession,
          storeKit: native,
          backend: _FakeBackend(),
        );
        expect(
          (await _purchase(coordinator)).state,
          AppleIapPurchaseFlowState.userCancelled,
        );
        expect(
          (await AppleIapPurchaseJournal(store).read('test-account'))?.state,
          'CANCELLED_CONFIRMED',
        );
        await coordinator.purchase(_binding);
        expect(native.purchaseCalls, 1);
        await coordinator.dispose();
      },
    );

    test(
      'delivered ACK remains delivered when native finish is deferred',
      () async {
        final store = MemoryKeyValueStore();
        final native = _FakeStoreKit(
          purchaseResult: AppleIapPurchaseResult(
            outcome: AppleIapPurchaseOutcome.transaction,
            transaction: _transaction(),
          ),
          finishResults: <bool>[false],
        );
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: store,
          authenticatedAccount: () => 'test-account',
          authenticatedSession: () => _testSession,
          storeKit: native,
          backend: _FakeBackend(),
        );
        final result = await _purchase(coordinator);
        expect(result.state, AppleIapPurchaseFlowState.delivered);
        expect(result.reason, 'native_finish_deferred');
        expect(
          (await AppleIapPurchaseJournal(store).read('test-account'))?.state,
          'DELIVERED',
        );
        await coordinator.dispose();
      },
    );

    test(
      'unknown native outcome retains one order instead of another POST',
      () async {
        Object session = Object();
        String account = 'account-a';
        final storeKit = _FakeStoreKit(
          purchaseError: TimeoutException('native unknown'),
        );
        final backend = _FakeBackend();
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: MemoryKeyValueStore(),
          authenticatedAccount: () => account,
          authenticatedSession: () => session,
          storeKit: storeKit,
          backend: backend,
        );
        expect(
          (await _purchase(coordinator)).state,
          AppleIapPurchaseFlowState.awaitingBackend,
        );
        final retained = await coordinator.createOrder(
          productId: _binding.productId,
          requestId: 'must-not-create-second-order',
        );
        expect(retained.orderNo, _binding.orderNo);
        expect(backend.createCalls, 1);
        session = Object(); // Same account token refresh/relogin may recover.
        expect(
          (await coordinator.createOrder(
            productId: _binding.productId,
            requestId: 'same-account-recovery',
          )).orderNo,
          _binding.orderNo,
        );
        expect(backend.createCalls, 1);
        account = 'account-b';
        session = Object();
        await expectLater(
          coordinator.createOrder(
            productId: _binding.productId,
            requestId: 'different-account-must-not-reuse',
          ),
          throwsA(isA<ApiException>()),
        );
        expect(backend.createCalls, 1);
        await coordinator.dispose();
      },
    );

    test(
      'overlapping recovery triggers share the same delivery and finish',
      () async {
        final ack = Completer<AppleIapDeliveryAck>();
        final backend = _FakeBackend(pendingAck: ack.future);
        final storeKit = _FakeStoreKit(
          recovered: <AppleIapTransaction>[_transaction()],
        );
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: MemoryKeyValueStore(),
          authenticatedAccount: () => 'test-account',
          authenticatedSession: () => _testSession,
          storeKit: storeKit,
          backend: backend,
        );
        final first = coordinator.recoverUnfinished();
        await backend.firstDelivery;
        final second = coordinator.recoverUnfinished();
        expect(storeKit.recoveryCalls, 1);
        ack.complete(backend.deliveryAck);
        expect((await first).finished, 1);
        expect((await second).finished, 1);
        expect(storeKit.finished, hasLength(1));
        expect(backend.deliveries, hasLength(1));
        await coordinator.dispose();
      },
    );
    test('an order created by A cannot start native purchase as B', () async {
      Object? session = Object();
      final storeKit = _FakeStoreKit();
      final coordinator = AppleIapPurchaseCoordinator(
        purchaseStore: MemoryKeyValueStore(),
        authenticatedAccount: () => 'test-account',
        authenticatedSession: () => session,
        storeKit: storeKit,
        backend: _FakeBackend(),
      );
      await coordinator.createOrder(
        productId: _binding.productId,
        requestId: 'create-before-switch',
      );
      session = Object();
      await expectLater(
        coordinator.purchase(_binding),
        throwsA(isA<ApiException>()),
      );
      expect(storeKit.purchaseCalls, 0);
      await coordinator.dispose();
    });

    test(
      'logout or account switch while awaiting ACK never finishes',
      () async {
        for (final bool logout in <bool>[true, false]) {
          Object? session = Object();
          final ack = Completer<AppleIapDeliveryAck>();
          final storeKit = _FakeStoreKit(
            purchaseResult: AppleIapPurchaseResult(
              outcome: AppleIapPurchaseOutcome.transaction,
              transaction: _transaction(),
            ),
          );
          final backend = _FakeBackend(pendingAck: ack.future);
          final coordinator = AppleIapPurchaseCoordinator(
            purchaseStore: MemoryKeyValueStore(),
            authenticatedAccount: () => 'test-account',
            authenticatedSession: () => session,
            storeKit: storeKit,
            backend: backend,
          );
          final result = _purchase(coordinator);
          await backend.firstDelivery;
          final rejection = expectLater(result, throwsA(isA<ApiException>()));
          session = logout ? null : Object();
          ack.complete(backend.deliveryAck);
          await rejection;
          expect(storeKit.finished, isEmpty);
          await coordinator.dispose();
        }
      },
    );

    test(
      'failed native finish is retried through unfinished authority',
      () async {
        final storeKit = _FakeStoreKit(
          recovered: <AppleIapTransaction>[
            _transaction(source: AppleIapTransactionSource.unfinished),
          ],
          finishResults: <bool>[false, true],
        );
        final backend = _FakeBackend();
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: MemoryKeyValueStore(),
          authenticatedAccount: () => 'test-account',
          authenticatedSession: () => _testSession,
          storeKit: storeKit,
          backend: backend,
        );
        final first = await coordinator.recoverUnfinished();
        expect(first.deferred, 1);
        expect(first.finished, 0);
        final second = await coordinator.recoverUnfinished();
        expect(second.deferred, 0);
        expect(second.finished, 1);
        expect(backend.deliveries, hasLength(2));
        await coordinator.dispose();
      },
    );
    test(
      'disposing during delivery cannot finish a late backend ACK',
      () async {
        final ack = Completer<AppleIapDeliveryAck>();
        final storeKit = _FakeStoreKit(
          purchaseResult: AppleIapPurchaseResult(
            outcome: AppleIapPurchaseOutcome.transaction,
            transaction: _transaction(),
          ),
        );
        final backend = _FakeBackend(pendingAck: ack.future);
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: MemoryKeyValueStore(),
          authenticatedAccount: () => 'test-account',
          authenticatedSession: () => _testSession,
          storeKit: storeKit,
          backend: backend,
        );
        final result = _purchase(coordinator);
        await backend.firstDelivery;
        final rejection = expectLater(result, throwsStateError);
        await coordinator.dispose();
        ack.complete(backend.deliveryAck);
        await rejection;
        expect(storeKit.finished, isEmpty);
      },
    );

    test('wrong credited amount cannot finish the selected order', () async {
      final storeKit = _FakeStoreKit(
        purchaseResult: AppleIapPurchaseResult(
          outcome: AppleIapPurchaseOutcome.transaction,
          transaction: _transaction(),
        ),
      );
      final coordinator = AppleIapPurchaseCoordinator(
        purchaseStore: MemoryKeyValueStore(),
        authenticatedAccount: () => 'test-account',
        authenticatedSession: () => _testSession,
        storeKit: storeKit,
        backend: _FakeBackend(
          deliveryAck: const AppleIapDeliveryAck(
            orderNo: 'vs_apple_order_1',
            transactionId: '100000000000001',
            deliveryState: AppleIapDeliveryState.delivered,
            creditedGiftCoins: 1,
            finishAllowed: true,
          ),
        ),
      );
      await expectLater(_purchase(coordinator), throwsA(isA<ApiException>()));
      expect(storeKit.finished, isEmpty);
      await coordinator.dispose();
    });
    test('currency or price mismatch blocks before native purchase', () async {
      for (final (String, int) price in <(String, int)>[
        ('USD', 6000),
        ('CNY', 7000),
        ('CNY', 0),
      ]) {
        final _FakeStoreKit storeKit = _FakeStoreKit(
          currencyCode: price.$1,
          priceMilliunits: price.$2,
        );
        final _FakeBackend backend = _FakeBackend();
        final coordinator = AppleIapPurchaseCoordinator(
          purchaseStore: MemoryKeyValueStore(),
          authenticatedAccount: () => 'test-account',
          authenticatedSession: () => _testSession,
          storeKit: storeKit,
          backend: backend,
        );
        await expectLater(_purchase(coordinator), throwsA(isA<ApiException>()));
        expect(storeKit.purchaseCalls, 0);
        expect(backend.deliveries, isEmpty);
        expect(storeKit.finished, isEmpty);
        await coordinator.dispose();
      }
    });
    test('finishes only after an authoritative delivered ACK', () async {
      final _FakeStoreKit storeKit = _FakeStoreKit(
        purchaseResult: AppleIapPurchaseResult(
          outcome: AppleIapPurchaseOutcome.transaction,
          transaction: _transaction(),
        ),
      );
      final _FakeBackend backend = _FakeBackend();
      final AppleIapPurchaseCoordinator coordinator =
          AppleIapPurchaseCoordinator(
            purchaseStore: MemoryKeyValueStore(),
            authenticatedAccount: () => 'test-account',
            authenticatedSession: () => _testSession,
            storeKit: storeKit,
            backend: backend,
          );

      final AppleIapPurchaseFlow result = await _purchase(coordinator);

      expect(result.state, AppleIapPurchaseFlowState.delivered);
      expect(backend.deliveries, hasLength(1));
      expect(backend.deliveries.single.orderNo, _binding.orderNo);
      expect(storeKit.finished, <String>['100000000000001']);
      await coordinator.dispose();
    });

    test(
      'pending and user cancellation never reach backend delivery',
      () async {
        for (final AppleIapPurchaseOutcome outcome in <AppleIapPurchaseOutcome>[
          AppleIapPurchaseOutcome.pending,
          AppleIapPurchaseOutcome.userCancelled,
        ]) {
          final _FakeStoreKit storeKit = _FakeStoreKit(
            purchaseResult: AppleIapPurchaseResult(outcome: outcome),
          );
          final _FakeBackend backend = _FakeBackend();
          final AppleIapPurchaseCoordinator coordinator =
              AppleIapPurchaseCoordinator(
                purchaseStore: MemoryKeyValueStore(),
                authenticatedAccount: () => 'test-account',
                authenticatedSession: () => _testSession,
                storeKit: storeKit,
                backend: backend,
              );

          final AppleIapPurchaseFlow result = await _purchase(coordinator);

          expect(
            result.state,
            outcome == AppleIapPurchaseOutcome.pending
                ? AppleIapPurchaseFlowState.pending
                : AppleIapPurchaseFlowState.userCancelled,
          );
          expect(backend.deliveries, isEmpty);
          expect(storeKit.finished, isEmpty);
          await coordinator.dispose();
        }
      },
    );

    test('product or account-token mismatch fails before delivery', () async {
      for (final AppleIapTransaction transaction in <AppleIapTransaction>[
        _transaction(productId: 'com.kong373.voiceSocialApp.recharge.300'),
        _transaction(appAccountToken: '22222222-2222-4222-8222-222222222222'),
      ]) {
        final _FakeStoreKit storeKit = _FakeStoreKit(
          purchaseResult: AppleIapPurchaseResult(
            outcome: AppleIapPurchaseOutcome.transaction,
            transaction: transaction,
          ),
        );
        final _FakeBackend backend = _FakeBackend();
        final AppleIapPurchaseCoordinator coordinator =
            AppleIapPurchaseCoordinator(
              purchaseStore: MemoryKeyValueStore(),
              authenticatedAccount: () => 'test-account',
              authenticatedSession: () => _testSession,
              storeKit: storeKit,
              backend: backend,
            );

        await expectLater(_purchase(coordinator), throwsA(isA<ApiException>()));
        expect(backend.deliveries, isEmpty);
        expect(storeKit.finished, isEmpty);
        await coordinator.dispose();
      }
    });

    test(
      'pending backend ACK deliberately leaves transaction unfinished',
      () async {
        final _FakeStoreKit storeKit = _FakeStoreKit(
          purchaseResult: AppleIapPurchaseResult(
            outcome: AppleIapPurchaseOutcome.transaction,
            transaction: _transaction(),
          ),
        );
        final _FakeBackend backend = _FakeBackend(
          deliveryAck: const AppleIapDeliveryAck(
            orderNo: 'vs_apple_order_1',
            transactionId: '100000000000001',
            deliveryState: AppleIapDeliveryState.pending,
            creditedGiftCoins: 0,
            finishAllowed: false,
          ),
        );
        final AppleIapPurchaseCoordinator coordinator =
            AppleIapPurchaseCoordinator(
              purchaseStore: MemoryKeyValueStore(),
              authenticatedAccount: () => 'test-account',
              authenticatedSession: () => _testSession,
              storeKit: storeKit,
              backend: backend,
            );

        final AppleIapPurchaseFlow result = await _purchase(coordinator);

        expect(result.state, AppleIapPurchaseFlowState.awaitingBackend);
        expect(storeKit.finished, isEmpty);
        await coordinator.dispose();
      },
    );

    test(
      'backend failure leaves transaction unfinished for recovery',
      () async {
        final _FakeStoreKit storeKit = _FakeStoreKit(
          purchaseResult: AppleIapPurchaseResult(
            outcome: AppleIapPurchaseOutcome.transaction,
            transaction: _transaction(),
          ),
        );
        final _FakeBackend backend = _FakeBackend(
          deliveryError: StateError('offline'),
        );
        final AppleIapPurchaseCoordinator coordinator =
            AppleIapPurchaseCoordinator(
              purchaseStore: MemoryKeyValueStore(),
              authenticatedAccount: () => 'test-account',
              authenticatedSession: () => _testSession,
              storeKit: storeKit,
              backend: backend,
            );

        await expectLater(_purchase(coordinator), throwsStateError);
        expect(storeKit.finished, isEmpty);
        await coordinator.dispose();
      },
    );

    test(
      'unfinished recovery deduplicates one transaction and finishes it',
      () async {
        final AppleIapTransaction transaction = _transaction(
          source: AppleIapTransactionSource.unfinished,
        );
        final _FakeStoreKit storeKit = _FakeStoreKit(
          recovered: <AppleIapTransaction>[transaction, transaction],
        );
        final _FakeBackend backend = _FakeBackend();
        final AppleIapPurchaseCoordinator coordinator =
            AppleIapPurchaseCoordinator(
              purchaseStore: MemoryKeyValueStore(),
              authenticatedAccount: () => 'test-account',
              authenticatedSession: () => _testSession,
              storeKit: storeKit,
              backend: backend,
            );

        final AppleIapRecoveryResult result = await coordinator
            .recoverUnfinished();

        expect(result.observed, 2);
        expect(result.delivered, 1);
        expect(result.finished, 1);
        expect(result.deferred, 0);
        expect(backend.deliveries, hasLength(1));
        expect(backend.deliveries.single.orderNo, isNull);
        expect(storeKit.finished, <String>['100000000000001']);
        await coordinator.dispose();
      },
    );

    test(
      'transaction updates use the same backend-before-finish gate',
      () async {
        final StreamController<AppleIapTransaction> updates =
            StreamController<AppleIapTransaction>.broadcast();
        final _FakeStoreKit storeKit = _FakeStoreKit(updates: updates.stream);
        final _FakeBackend backend = _FakeBackend();
        final AppleIapPurchaseCoordinator coordinator =
            AppleIapPurchaseCoordinator(
              purchaseStore: MemoryKeyValueStore(),
              authenticatedAccount: () => 'test-account',
              authenticatedSession: () => _testSession,
              storeKit: storeKit,
              backend: backend,
            );
        coordinator.startListening();

        updates.add(_transaction(source: AppleIapTransactionSource.updates));
        await backend.firstDelivery.timeout(const Duration(seconds: 1));
        await storeKit.firstFinish.timeout(const Duration(seconds: 1));

        expect(backend.deliveries.single.orderNo, isNull);
        expect(storeKit.finished, <String>['100000000000001']);
        await updates.close();
        await coordinator.dispose();
      },
    );
  });
}

Future<AppleIapPurchaseFlow> _purchase(
  AppleIapPurchaseCoordinator coordinator,
) async {
  await coordinator.createOrder(
    productId: _binding.productId,
    requestId: 'test-order-create',
  );
  return coordinator.purchase(_binding);
}

const AppleIapOrderBinding _binding = AppleIapOrderBinding(
  orderNo: 'vs_apple_order_1',
  productId: '00000000-0000-0000-0000-000000001101',
  storeProductId: 'com.kong373.voiceSocialApp.recharge.60',
  appAccountToken: '11111111-1111-4111-8111-111111111111',
  amountMinor: 600,
  giftCoinAmount: 60,
  environment: 'Sandbox',
  status: 'CONFIRMING',
  createdAt: null,
);

AppleIapTransaction _transaction({
  String productId = 'com.kong373.voiceSocialApp.recharge.60',
  String? appAccountToken = '11111111-1111-4111-8111-111111111111',
  AppleIapTransactionSource source = AppleIapTransactionSource.purchase,
}) => AppleIapTransaction(
  transactionId: '100000000000001',
  originalTransactionId: '100000000000001',
  productId: productId,
  appAccountToken: appAccountToken,
  purchaseDate: DateTime.utc(2026, 9, 4),
  signedTransaction: 'header.payload.signature',
  verification: AppleIapVerification.verified,
  source: source,
);

class _FakeStoreKit implements AppleIapStoreKit2Adapter {
  _FakeStoreKit({
    this.currencyCode = 'CNY',
    this.priceMilliunits = 6000,
    this.purchaseResult = const AppleIapPurchaseResult(
      outcome: AppleIapPurchaseOutcome.failed,
    ),
    this.recovered = const <AppleIapTransaction>[],
    this.finishResults,
    this.purchaseError,
    Stream<AppleIapTransaction>? updates,
  }) : _updates = updates ?? const Stream<AppleIapTransaction>.empty();

  final AppleIapPurchaseResult purchaseResult;
  final String currencyCode;
  final int priceMilliunits;
  int purchaseCalls = 0;
  int recoveryCalls = 0;
  final Object? purchaseError;
  final List<AppleIapTransaction> recovered;
  final List<bool>? finishResults;
  final Stream<AppleIapTransaction> _updates;
  final List<String> finished = <String>[];
  final Completer<void> _firstFinish = Completer<void>();

  Future<void> get firstFinish => _firstFinish.future;

  @override
  bool get isPlatformSupported => true;

  @override
  Stream<AppleIapTransaction> get transactionUpdates => _updates;

  @override
  Future<AppleIapAvailabilityStatus> availability() async =>
      const AppleIapAvailabilityStatus(state: AppleIapAvailability.available);

  @override
  Future<List<AppleStoreProduct>> loadProducts(List<String> productIds) async =>
      productIds
          .map(
            (String id) => AppleStoreProduct(
              id: id,
              displayName: 'Gift coins',
              description: 'Consumable',
              displayPrice: '¥6.00',
              priceMilliunits: priceMilliunits,
              currencyCode: currencyCode,
              productType: 'consumable',
            ),
          )
          .toList(growable: false);

  @override
  Future<AppleIapPurchaseResult> purchase({
    required String productId,
    required String appAccountToken,
  }) async {
    purchaseCalls += 1;
    if (purchaseError case final Object error) {
      throw error;
    }
    return purchaseResult;
  }

  @override
  Future<List<AppleIapTransaction>> recoverUnfinished({
    bool synchronizeStore = false,
  }) async {
    recoveryCalls += 1;
    return recovered;
  }

  @override
  Future<bool> finish(String transactionId) async {
    finished.add(transactionId);
    if (!_firstFinish.isCompleted) {
      _firstFinish.complete();
    }
    return finishResults?.isNotEmpty == true
        ? finishResults!.removeAt(0)
        : true;
  }
}

class _FailingWriteStore extends MemoryKeyValueStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('storage unavailable');
}

class _RecoverableFakeStoreKit extends _FakeStoreKit
    implements AppleIapPendingPurchaseRecovery {
  _RecoverableFakeStoreKit()
    : super(purchaseError: TimeoutException('unknown'));
  AppleIapPurchaseResult? retained;
  @override
  Future<AppleIapPurchaseResult?> readRetainedPurchaseOutcome({
    required String productId,
    required String appAccountToken,
  }) async => retained;
}

class _DeliveryCall {
  const _DeliveryCall({required this.orderNo, required this.transaction});

  final String? orderNo;
  final AppleIapTransaction transaction;
}

class _FakeBackend implements AppleIapBackendPort {
  _FakeBackend({
    this.deliveryAck = const AppleIapDeliveryAck(
      orderNo: 'vs_apple_order_1',
      transactionId: '100000000000001',
      deliveryState: AppleIapDeliveryState.delivered,
      creditedGiftCoins: 60,
      finishAllowed: true,
    ),
    this.deliveryError,
    this.pendingAck,
  });

  final AppleIapDeliveryAck deliveryAck;
  final Object? deliveryError;
  final Future<AppleIapDeliveryAck>? pendingAck;
  final List<_DeliveryCall> deliveries = <_DeliveryCall>[];
  int createCalls = 0;
  final Completer<void> _firstDelivery = Completer<void>();

  Future<void> get firstDelivery => _firstDelivery.future;

  @override
  Future<AppleIapOrderBinding> createOrder({
    required String productId,
    required String requestId,
  }) async {
    createCalls += 1;
    return _binding;
  }

  @override
  Future<AppleIapDeliveryAck> deliverTransaction({
    required String? orderNo,
    required AppleIapTransaction transaction,
    required String requestId,
  }) async {
    deliveries.add(_DeliveryCall(orderNo: orderNo, transaction: transaction));
    if (!_firstDelivery.isCompleted) {
      _firstDelivery.complete();
    }
    if (deliveryError case final Object error) {
      throw error;
    }
    return pendingAck ?? deliveryAck;
  }

  @override
  Future<AppleIapOrderStatus> readOrderStatus(String orderNo) async =>
      const AppleIapOrderStatus(
        orderNo: 'vs_apple_order_1',
        status: 'SUCCEEDED',
        creditedGiftCoins: 60,
        transactionId: '100000000000001',
        finishAllowed: true,
      );
}
