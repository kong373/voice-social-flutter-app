import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import '../domain/gift_send_models.dart';

/// App-owned, account-partitioned journal. No widget/controller owns the only
/// copy of an unknown command. Storage must finish before any financial POST.
class GiftSendCoordinator extends ChangeNotifier {
  GiftSendCoordinator({
    required this.repository,
    required KeyValueStore store,
    required (int?, int) Function() identity,
    Listenable? identityChanges,
    this.storageScope = 'local',
    String Function()? newKey,
  }) : _store = store,
       _identity = identity,
       _identityChanges = identityChanges,
       _newKey = newKey ?? _randomKey {
    _identityChanges?.addListener(_changed);
  }
  final GiftCommandRepository repository;
  final KeyValueStore _store;
  final (int?, int) Function() _identity;
  final Listenable? _identityChanges;
  final String storageScope;
  final String Function() _newKey;
  final Map<int, GiftSendPlan?> _plans = {};
  final Map<(int?, int), Future<void>> _running = {};
  Future<void> _storageTail = Future.value();
  bool _disposed = false;
  String? error;
  GiftSendPlan? get plan => _plans[_identity().$1];
  bool get busy => _running.containsKey(_identity());
  String _key(int actor) => 'room.gift-journal.v1.$storageScope.$actor';
  void _changed() {
    error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _require((int?, int) identity) {
    if (_disposed || identity.$1 == null || _identity() != identity) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '身份已变化，原送礼结果仍保留在原账号',
      );
    }
  }

  Future<T> _storage<T>(Future<T> Function() action) {
    final next = _storageTail.then((_) => action());
    _storageTail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  Future<void> restore() async {
    final identity = _identity();
    if (identity.$1 == null || _plans.containsKey(identity.$1)) return;
    try {
      final raw = await _storage(() => _store.read(_key(identity.$1!)));
      _require(identity);
      _plans.putIfAbsent(
        identity.$1!,
        () => raw == null ? null : GiftSendPlan.decode(raw, identity.$1!),
      );
      error = null;
    } catch (_) {
      if (_identity() == identity) error = '原送礼记录读取失败，暂不能新赠送';
    }
    _notify();
  }

  Future<void> _save(GiftSendPlan plan) =>
      _storage(() => _store.write(_key(plan.command.actorId), plan.encode()));

  Future<void> submit({
    required String roomId,
    required String giftId,
    required int unitCoins,
    required int quantity,
    required List<int> receivers,
    required bool Function(int receiver) canSend,
  }) {
    return _run((identity) async {
      await restore();
      _require(identity);
      if (!_plans.containsKey(identity.$1) || plan != null) return;
      final ids = receivers.toSet().toList();
      if (ids.isEmpty ||
          ids.length != receivers.length ||
          ids.any((id) => !canSend(id))) {
        error = '收礼人已离开麦位，请重新选择并确认';
        return;
      }
      final created = GiftSendPlan(
        unitCoins: BigInt.from(unitCoins),
        entries: [
          for (final id in ids)
            GiftSendEntry(
              repository.freezeGift(
                actorId: identity.$1!,
                roomId: roomId,
                giftId: giftId,
                receiverUserId: id,
                quantity: quantity,
                requestId: _newKey(),
              ),
            ),
        ],
      );
      await _save(created);
      _plans[identity.$1!] = created;
      _require(identity);
      await _dispatch(created, identity, canSend);
    });
  }

  Future<void> recover({
    required bool Function(int) canSend,
    bool retryUnknown = false,
  }) => _run((identity) async {
    await restore();
    _require(identity);
    final current = plan;
    if (current == null) return;
    for (final entry in current.entries) {
      _require(identity);
      if (entry.state != GiftSendState.unknown) continue;
      final recovered = await _query(current, entry, identity);
      _require(identity);
      if (!recovered &&
          entry.state == GiftSendState.unknown &&
          retryUnknown &&
          canSend(entry.command.receiverUserId) &&
          _sameLease(entry.command)) {
        await _send(current, entry, identity, canSend);
      }
    }
    // Queued items have never been sent. Recovery is an explicit user
    // action, but transport still refuses a changed original sessionId.
    if (retryUnknown) await _dispatch(current, identity, canSend);
  });

  Future<void> _dispatch(
    GiftSendPlan plan,
    (int?, int) identity,
    bool Function(int) canSend,
  ) async {
    for (final entry in plan.entries) {
      _require(identity);
      if (entry.state != GiftSendState.queued) continue;
      if (!canSend(entry.command.receiverUserId) ||
          !_sameLease(entry.command)) {
        entry.state = GiftSendState.notSent;
        await _save(plan);
        _notify();
        continue;
      }
      await _send(plan, entry, identity, canSend);
    }
  }

  bool _sameLease(GiftSendCommand command) {
    try {
      final current = repository.freezeGift(
        actorId: command.actorId,
        roomId: command.roomId,
        giftId: command.giftId,
        receiverUserId: command.receiverUserId,
        quantity: command.quantity,
        requestId: command.requestId,
      );
      return current.encodedBody == command.encodedBody;
    } catch (_) {
      return false;
    }
  }

  Future<void> _send(
    GiftSendPlan plan,
    GiftSendEntry entry,
    (int?, int) identity,
    bool Function(int) canSend,
  ) async {
    final previouslyUnknown = entry.state == GiftSendState.unknown;
    entry.state = GiftSendState.unknown;
    await _save(plan);
    _require(identity);
    _notify();
    try {
      final receipt = await repository.sendGiftCommand(
        entry.command,
        requireIdentity: () {
          _require(identity);
          if (!canSend(entry.command.receiverUserId)) {
            throw const ApiException(
              kind: ApiFailureKind.conflict,
              message: '麦位或房间权限已变化，原请求保持待确认',
            );
          }
        },
      );
      _require(identity);
      entry.command.validateReceipt(receipt);
      entry.state = GiftSendState.succeeded;
      entry.transferId = receipt.transferId;
      await _save(plan);
    } catch (failure) {
      _require(identity);
      // After an ambiguous attempt, a later auth/lease/validation rejection
      // cannot establish whether the ORIGINAL write committed.
      if (!previouslyUnknown &&
          failure is ApiException &&
          failure.httpStatus != null &&
          failure.httpStatus! >= 400 &&
          failure.httpStatus! < 500 &&
          failure.httpStatus != 409 &&
          {
            ApiFailureKind.validation,
            ApiFailureKind.business,
            ApiFailureKind.unauthorized,
            ApiFailureKind.forbidden,
          }.contains(failure.kind)) {
        entry.state = GiftSendState.rejected;
        await _save(plan);
      } else if (entry.state != GiftSendState.succeeded) {
        await _query(plan, entry, identity);
      }
    }
    _notify();
  }

  Future<bool> _query(
    GiftSendPlan plan,
    GiftSendEntry entry,
    (int?, int) identity,
  ) async {
    try {
      final receipt = await repository.queryGiftCommand(entry.command);
      _require(identity);
      entry.command.validateReceipt(receipt, queried: true);
      entry.state = GiftSendState.succeeded;
      entry.transferId = receipt.transferId;
      await _save(plan);
      _notify();
      return true;
    } catch (_) {
      _require(identity);
      return false; // 404 is not proof that an in-flight POST cannot commit.
    }
  }

  Future<void> dismissCompleted() async {
    final identity = _identity();
    final current = plan;
    if (busy || current == null || !current.terminal) return;
    try {
      await _storage(() => _store.delete(_key(current.command.actorId)));
      _require(identity);
      if (identical(_plans[identity.$1], current)) _plans[identity.$1!] = null;
    } catch (_) {
      if (_identity() == identity) error = '送礼记录保存失败，请重试';
    }
    _notify();
  }

  Future<void> cancelUnsent() => _run((identity) async {
    final current = plan;
    if (current == null) return;
    for (final entry in current.entries) {
      if (entry.state == GiftSendState.queued)
        entry.state = GiftSendState.notSent;
    }
    await _save(current);
    _require(identity);
  });
  Future<void> _run(Future<void> Function((int?, int)) action) {
    final identity = _identity();
    final existing = _running[identity];
    if (existing != null) return existing;
    if (identity.$1 == null || _disposed) return Future.value();
    // Schedule after registration, preventing re-entrant double submissions.
    final future = Future<void>(() async {
      try {
        _require(identity);
        error = null;
        await action(identity);
      } catch (_) {
        if (_identity() == identity) error = '送礼结果未确认，请查询原记录；不会自动重新扣款';
      }
    });
    _running[identity] = future;
    _notify();
    return future.whenComplete(() {
      if (identical(_running[identity], future)) _running.remove(identity);
      _notify();
    });
  }

  static final _random = Random.secure();
  static String _randomKey() =>
      'gift-${List.generate(32, (_) => _random.nextInt(16).toRadixString(16)).join()}';
  @override
  void dispose() {
    _disposed = true;
    _identityChanges?.removeListener(_changed);
    super.dispose();
  }
}
