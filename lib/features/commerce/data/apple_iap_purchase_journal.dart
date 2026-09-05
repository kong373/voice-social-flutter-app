import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';

/// Durable client attempt bookkeeping, never a payment/finish authority.
/// Contains no JWS, access token, provider credential, or error payload.
class AppleIapPurchaseJournal {
  AppleIapPurchaseJournal(this._store);

  final KeyValueStore _store;
  Future<void> _writes = Future<void>.value();

  static String _key(String account) =>
      'apple_iap.attempt.v1.${sha256.convert(utf8.encode(account))}';

  Future<AppleIapJournalEntry?> read(String account) async {
    final String? raw = await _store.read(_key(account));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    if (raw.length > 8192) {
      throw StateError('Apple purchase recovery record is invalid');
    }
    return AppleIapJournalEntry.decode(raw);
  }

  Future<void> start(String account, AppleIapOrderBinding binding) =>
      _serialize(() async {
        final AppleIapJournalEntry? previous = await read(account);
        if (previous?.state == 'ATTEMPTED' &&
            previous!.binding.orderNo != binding.orderNo) {
          throw StateError('An earlier Apple purchase still requires recovery');
        }
        if (previous?.binding.orderNo == binding.orderNo) {
          // A persisted attempt is never rewritten as a fresh attempt.
          return;
        }
        await _store.write(
          _key(account),
          AppleIapJournalEntry(binding: binding, state: 'ATTEMPTED').encode(),
        );
      });

  Future<void> markTerminal(
    String account,
    String orderNo,
    String state, {
    required bool Function() stillCurrent,
  }) => _serialize(() async {
    if (!const <String>{'CANCELLED_CONFIRMED', 'DELIVERED'}.contains(state)) {
      throw ArgumentError('Invalid Apple recovery terminal category');
    }
    final AppleIapJournalEntry? previous = await read(account);
    if (!stillCurrent() ||
        previous == null ||
        previous.binding.orderNo != orderNo) {
      return;
    }
    // A late cancel cannot overwrite an already confirmed delivery.
    if (previous.state == 'DELIVERED') {
      return;
    }
    await _store.write(
      _key(account),
      AppleIapJournalEntry(binding: previous.binding, state: state).encode(),
    );
  });

  Future<void> _serialize(Future<void> Function() operation) {
    final Future<void> next = _writes.then((_) => operation());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}

class AppleIapJournalEntry {
  const AppleIapJournalEntry({required this.binding, required this.state});

  final AppleIapOrderBinding binding;
  final String state;

  String encode() => jsonEncode(<String, Object?>{
    'schema': 1,
    'state': state,
    'orderNo': binding.orderNo,
    'productId': binding.productId,
    'storeProductId': binding.storeProductId,
    'appAccountToken': binding.appAccountToken,
    'amountMinor': binding.amountMinor,
    'giftCoinAmount': binding.giftCoinAmount,
  });

  static AppleIapJournalEntry decode(String raw) {
    final Object? decoded = jsonDecode(raw);
    const fields = <String>{
      'schema',
      'state',
      'orderNo',
      'productId',
      'storeProductId',
      'appAccountToken',
      'amountMinor',
      'giftCoinAmount',
    };
    if (decoded is! Map<String, Object?> ||
        decoded.length != fields.length ||
        !decoded.keys.every(fields.contains) ||
        decoded['schema'] != 1 ||
        !const <String>{
          'ATTEMPTED',
          'CANCELLED_CONFIRMED',
          'DELIVERED',
        }.contains(decoded['state'])) {
      throw StateError('Apple purchase recovery record is invalid');
    }
    String value(String key, RegExp pattern) {
      final Object? text = decoded[key];
      if (text is! String || !pattern.hasMatch(text)) {
        throw StateError('Apple purchase recovery binding is invalid');
      }
      return text;
    }

    int amount(String key) {
      final Object? number = decoded[key];
      if (number is! int || number <= 0 || number > 99999999999) {
        throw StateError('Apple purchase recovery amount is invalid');
      }
      return number;
    }

    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return AppleIapJournalEntry(
      state: decoded['state']! as String,
      binding: AppleIapOrderBinding(
        orderNo: value('orderNo', RegExp(r'^[A-Za-z0-9_:-]{1,80}$')),
        productId: value('productId', uuid),
        storeProductId: value(
          'storeProductId',
          RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$'),
        ),
        appAccountToken: value('appAccountToken', uuid),
        amountMinor: amount('amountMinor'),
        giftCoinAmount: amount('giftCoinAmount'),
        environment: '',
        status: 'CONFIRMING',
        createdAt: null,
      ),
    );
  }
}
