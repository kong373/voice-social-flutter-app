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
    final entries = await readAll(account);
    return entries.isEmpty ? null : entries.last;
  }

  Future<List<AppleIapJournalEntry>> readAll(String account) async {
    final String? raw = await _store.read(_key(account));
    if (raw == null || raw.isEmpty) {
      return <AppleIapJournalEntry>[];
    }
    if (raw.length > 262144) {
      throw StateError('Apple purchase recovery record is invalid');
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> && decoded['schema'] == 1) {
      return <AppleIapJournalEntry>[AppleIapJournalEntry.decode(raw)];
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['schema'] != 2 ||
        decoded['entries'] is! List<Object?>) {
      throw StateError('Apple purchase recovery record is invalid');
    }
    final rawEntries = decoded['entries'] as List<Object?>;
    if (rawEntries.isEmpty || rawEntries.length > 128) {
      throw StateError('Apple purchase recovery record is invalid');
    }
    final entries = rawEntries
        .map((entry) => AppleIapJournalEntry.decode(jsonEncode(entry)))
        .toList();
    if (entries.map((entry) => entry.binding.orderNo).toSet().length !=
        entries.length) {
      throw StateError('Apple purchase recovery record is invalid');
    }
    return entries;
  }

  Future<void> start(String account, AppleIapOrderBinding binding) =>
      _serialize(() async {
        final entries = await readAll(account);
        if (entries.any(
          (entry) =>
              entry.state == 'ATTEMPTED' &&
              entry.binding.orderNo != binding.orderNo,
        )) {
          throw StateError('An earlier Apple purchase still requires recovery');
        }
        if (entries.any((entry) => entry.binding.orderNo == binding.orderNo)) {
          // A persisted attempt is never rewritten as a fresh attempt.
          return;
        }
        // Delivery is not native cleanup. Keep every un-finished delivery
        // snapshot when a new independent purchase starts.
        entries.removeWhere(
          (entry) =>
              entry.state == 'FINISHED' || entry.state == 'CANCELLED_CONFIRMED',
        );
        if (entries.length >= 128) {
          throw StateError('Apple purchase recovery cleanup is required');
        }
        entries.add(AppleIapJournalEntry(binding: binding, state: 'ATTEMPTED'));
        await _write(account, entries);
      });

  Future<void> markTerminal(
    String account,
    String orderNo,
    String state, {
    required bool Function() stillCurrent,
  }) => _serialize(() async {
    if (!const <String>{
      'CANCELLED_CONFIRMED',
      'DELIVERED',
      'FINISHED',
    }.contains(state)) {
      throw ArgumentError('Invalid Apple recovery terminal category');
    }
    final entries = await readAll(account);
    final index = entries.indexWhere(
      (entry) => entry.binding.orderNo == orderNo,
    );
    if (!stillCurrent() || index < 0) {
      return;
    }
    final previous = entries[index];
    // A late cancel cannot overwrite an already confirmed delivery.
    if (previous.state == 'FINISHED' ||
        (previous.state == 'DELIVERED' && state != 'FINISHED') ||
        (state == 'FINISHED' && previous.state != 'DELIVERED')) {
      return;
    }
    entries[index] = AppleIapJournalEntry(
      binding: previous.binding,
      state: state,
    );
    await _write(account, entries);
  });

  Future<void> _write(String account, List<AppleIapJournalEntry> entries) =>
      _store.write(
        _key(account),
        jsonEncode(<String, Object?>{
          'schema': 2,
          'entries': entries
              .map((entry) => jsonDecode(entry.encode()))
              .toList(),
        }),
      );

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

  String encode() {
    final raw = jsonEncode(<String, Object?>{
      'schema': 1,
      'state': state,
      'orderNo': binding.orderNo,
      'productId': binding.productId,
      'storeProductId': binding.storeProductId,
      'appAccountToken': binding.appAccountToken,
      'amountMinor': binding.amountMinor,
      'giftCoinAmount': binding.giftCoinAmount,
    });
    // Write/read must have identical contracts, including order number syntax.
    decode(raw);
    return raw;
  }

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
          'FINISHED',
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
        orderNo: value('orderNo', RegExp(r'^[A-Za-z0-9._-]{1,80}$')),
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
