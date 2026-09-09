import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/room/application/gift_send_coordinator.dart';
import 'package:voice_social_app/features/room/domain/gift_send_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

void main() {
  test(
    'serialized cold-start journal has no token/name; account and backend partitions do not mix',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.repo.outcomes[20] = const ApiException(
        kind: ApiFailureKind.network,
        message: 'lost',
      );
      await h.submit([20]);
      const key = 'room.gift-journal.v1.local.1';
      final raw = (await h.store.read(key))!;
      final json = jsonDecode(raw) as Map;
      final entry = (json['entries'] as List).single as Map;
      final saved = entry['command'] as Map;
      expect(saved.keys.toSet(), {
        'actorId',
        'requestId',
        'roomId',
        'sessionId',
        'giftId',
        'receiverUserId',
        'quantity',
        'source',
      });
      expect(raw, isNot(contains('Token')));
      final restartedStore = MemoryKeyValueStore({key: raw});
      final restarted = GiftSendCoordinator(
        repository: h.repo,
        store: restartedStore,
        identity: () => h.identity.value,
        identityChanges: h.identity,
      );
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(
        restarted.plan!.command.encodedBody,
        h.repo.sent.single.encodedBody,
      );
      expect(h.repo.sent, hasLength(1)); // restore is never a POST.
      h.identity.value = (2, 1);
      await restarted.restore();
      expect(restarted.plan, isNull);
      final anotherBackend = GiftSendCoordinator(
        repository: h.repo,
        store: restartedStore,
        storageScope: 'another-backend',
        identity: () => (1, 2),
      );
      addTearDown(anotherBackend.dispose);
      await anotherBackend.restore();
      expect(anotherBackend.plan, isNull);
    },
  );

  test(
    'concurrent submit shares work; queued cancellation never touches unknown or successful recipients',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      final gate = Completer<GiftReceipt>();
      h.repo.gate = gate;
      final first = h.submit([20, 30]);
      final second = h.submit([20, 30]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(h.repo.sent, hasLength(1));
      h.identity.value = (1, 1);
      gate.complete(receipt(h.repo.sent.single));
      await Future.wait([first, second]);
      await h.coordinator.cancelUnsent();
      expect(h.coordinator.plan!.entries.map((e) => e.state), [
        GiftSendState.unknown,
        GiftSendState.notSent,
      ]);
      expect(h.repo.sent, hasLength(1));
      await h.coordinator.dismissCompleted();
      expect(h.coordinator.plan, isNotNull);
    },
  );

  test(
    'S09 each recipient is one immutable quantity command; partial success never resends',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.repo.outcomes[30] = const ApiException(
        kind: ApiFailureKind.business,
        httpStatus: 400,
        message: 'off mic',
      );
      h.repo.outcomes[40] = const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'unknown',
      );
      await h.submit([20, 30, 40]);
      expect(h.coordinator.plan!.entries.map((e) => e.state), [
        GiftSendState.succeeded,
        GiftSendState.rejected,
        GiftSendState.unknown,
      ]);
      expect(h.repo.sent.map((c) => c.quantity), [10, 10, 10]);
      expect(h.repo.sent.map((c) => c.requestId).toSet(), hasLength(3));
      final original = h.repo.sent.last;
      h.repo.outcomes.remove(40);
      await h.coordinator.recover(canSend: (_) => true, retryUnknown: true);
      expect(h.repo.sent.map((c) => c.receiverUserId), [20, 30, 40, 40]);
      expect(h.repo.sent.last.requestId, original.requestId);
      expect(h.repo.sent.last.encodedBody, original.encodedBody);
      expect(h.coordinator.plan!.succeeded, 2);
    },
  );

  test(
    'lost response recovers by GET without another POST; mismatched receipt stays unknown',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.repo.outcomes[20] = const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'lost',
      );
      h.repo.query = (c) async => receipt(c);
      await h.submit([20]);
      expect(h.coordinator.plan!.succeeded, 1);
      expect(h.repo.sent, hasLength(1));
      await h.coordinator.dismissCompleted();
      h.repo.query = (c) async => receipt(c, receiver: 99);
      await h.submit([20]);
      expect(h.coordinator.plan!.entries.single.state, GiftSendState.unknown);
    },
  );

  test('unknown then 40903 or 401 cannot authorize a new key', () async {
    final h = Harness();
    addTearDown(h.dispose);
    h.repo.outcomes[20] = const ApiException(
      kind: ApiFailureKind.network,
      message: 'lost',
    );
    await h.submit([20]);
    final key = h.repo.sent.single.requestId;
    for (final error in [
      const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40903,
        message: 'mismatch',
      ),
      const ApiException(
        kind: ApiFailureKind.unauthorized,
        code: 401,
        message: 'auth',
      ),
    ]) {
      h.repo.outcomes[20] = error;
      await h.coordinator.recover(canSend: (_) => true, retryUnknown: true);
      expect(h.coordinator.plan!.entries.single.state, GiftSendState.unknown);
      expect(h.repo.sent.last.requestId, key);
    }
    await h.submit([30]);
    expect(h.repo.sent, hasLength(3));
  });

  test(
    'journal survives coordinator reconstruction; new lease permits GET but never rebinds payload',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.repo.outcomes[20] = const ApiException(
        kind: ApiFailureKind.timeout,
        message: 'lost',
      );
      await h.submit([20]);
      final original = h.repo.sent.single;
      h.coordinator.dispose();
      h.repo.session = 'lease-new';
      h.coordinator = h.build();
      await h.coordinator.restore();
      expect(h.coordinator.plan!.command.encodedBody, original.encodedBody);
      await h.coordinator.recover(canSend: (_) => true, retryUnknown: true);
      expect(h.repo.sent, hasLength(1));
      expect(h.coordinator.plan!.entries.single.state, GiftSendState.unknown);
      h.repo.query = (c) async => receipt(c);
      await h.coordinator.recover(canSend: (_) => false);
      expect(h.coordinator.plan!.succeeded, 1);
      expect(h.repo.sent, hasLength(1));
    },
  );

  test(
    'A-B-A late success is fenced; original key and bytes survive for A',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      final gate = Completer<GiftReceipt>();
      h.repo.gate = gate;
      final work = h.submit([20, 30]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(h.repo.sent, hasLength(1));
      final original = h.repo.sent.single;
      h.identity.value = (2, 1);
      await h.coordinator.restore();
      expect(h.coordinator.plan, isNull);
      h.identity.value = (1, 2);
      gate.complete(receipt(original));
      await work;
      expect(h.coordinator.plan!.entries.first.state, GiftSendState.unknown);
      expect(h.repo.sent, hasLength(1));
      h.repo.query = (c) async => receipt(c);
      await h.coordinator.recover(canSend: (_) => false);
      expect(h.coordinator.plan!.entries.first.state, GiftSendState.succeeded);
      expect(h.coordinator.plan!.command.encodedBody, original.encodedBody);
      expect(h.coordinator.plan!.entries.last.state, GiftSendState.queued);
    },
  );

  test(
    'write-ahead journal failure prevents POST, corrupt journal blocks new commands',
    () async {
      final store = FailingStore();
      final h = Harness(store: store);
      addTearDown(h.dispose);
      store.failWrite = true;
      await h.submit([20]);
      expect(h.repo.sent, isEmpty);
      expect(h.coordinator.error, isNotNull);
      h.coordinator.dispose();
      store.failWrite = false;
      await store.write('room.gift-journal.v1.local.1', '{bad');
      h.coordinator = h.build();
      await h.submit([20]);
      expect(h.repo.sent, isEmpty);
    },
  );

  test(
    'precise preview does not multiply through int or double; duplicate targets reject',
    () async {
      final h = Harness();
      addTearDown(h.dispose);
      const price = 9007199254740991;
      await h.coordinator.submit(
        roomId: 'room',
        giftId: 'gift',
        unitCoins: price,
        quantity: 999,
        receivers: [20, 30, 40],
        canSend: (_) => true,
      );
      expect(
        h.coordinator.plan!.totalCoins,
        BigInt.parse('9007199254740991') * BigInt.from(2997),
      );
      await h.coordinator.dismissCompleted();
      final before = h.repo.sent.length;
      await h.submit([20, 20]);
      expect(h.repo.sent.length, before);
      expect(h.coordinator.plan, isNull);
    },
  );
}

GiftReceipt receipt(GiftSendCommand c, {int? receiver}) => GiftReceipt(
  success: true,
  remainingBalance: null,
  transferId: 'transfer-${c.requestId}',
  roomId: c.roomId,
  senderUserId: c.actorId,
  receiverUserId: receiver ?? c.receiverUserId,
  giftId: c.giftId,
  quantity: c.quantity,
  requestId: c.requestId,
  source: 'WALLET',
  providerInvocation: false,
  reconciled: true,
);

class Harness {
  Harness({KeyValueStore? store}) : store = store ?? MemoryKeyValueStore() {
    coordinator = build();
  }
  final KeyValueStore store;
  final identity = ValueNotifier<(int?, int)>((1, 0));
  final repo = Repository();
  int serial = 0;
  late GiftSendCoordinator coordinator;
  GiftSendCoordinator build() => GiftSendCoordinator(
    repository: repo,
    store: store,
    identity: () => identity.value,
    identityChanges: identity,
    newKey: () => 'gift-${++serial}',
  );
  Future<void> submit(List<int> receivers) => coordinator.submit(
    roomId: 'room',
    giftId: 'gift',
    unitCoins: 99,
    quantity: 10,
    receivers: receivers,
    canSend: (_) => true,
  );
  void dispose() {
    coordinator.dispose();
    identity.dispose();
  }
}

class Repository implements GiftCommandRepository {
  String session = 'lease';
  final sent = <GiftSendCommand>[];
  final queried = <GiftSendCommand>[];
  final outcomes = <int, Object>{};
  Completer<GiftReceipt>? gate;
  Future<GiftReceipt> Function(GiftSendCommand)? query;
  @override
  GiftSendCommand freezeGift({
    required int actorId,
    required String roomId,
    required String giftId,
    required int receiverUserId,
    required int quantity,
    required String requestId,
  }) => GiftSendCommand(
    actorId: actorId,
    requestId: requestId,
    roomId: roomId,
    sessionId: session,
    giftId: giftId,
    receiverUserId: receiverUserId,
    quantity: quantity,
  );
  @override
  Future<GiftReceipt> sendGiftCommand(
    GiftSendCommand c, {
    required void Function() requireIdentity,
  }) async {
    requireIdentity();
    if (c.sessionId != session)
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40937,
        message: 'lease',
      );
    sent.add(c);
    final pending = gate;
    gate = null;
    if (pending != null) return pending.future;
    final error = outcomes[c.receiverUserId];
    if (error != null) throw error;
    return receipt(c);
  }

  @override
  Future<GiftReceipt> queryGiftCommand(GiftSendCommand c) async {
    queried.add(c);
    if (query != null) return query!(c);
    throw const ApiException(
      kind: ApiFailureKind.business,
      code: 404,
      message: 'not found',
    );
  }
}

class FailingStore extends MemoryKeyValueStore {
  bool failWrite = false;
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('storage unavailable');
    await super.write(key, value);
  }
}
