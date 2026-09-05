import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/commerce/data/apple_iap_purchase_journal.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';

void main() {
  test(
    'journal persists only bounded recovery metadata under a hashed key',
    () async {
      final store = _RecordingStore();
      final journal = AppleIapPurchaseJournal(store);
      await journal.start('private-account-label', _binding('order_one'));
      expect(store.lastKey, startsWith('apple_iap.attempt.v1.'));
      expect(store.lastKey, isNot(contains('private-account-label')));
      final data = jsonDecode(store.lastValue!) as Map<String, dynamic>;
      expect(data.keys.toSet(), <String>{
        'schema',
        'state',
        'orderNo',
        'productId',
        'storeProductId',
        'appAccountToken',
        'amountMinor',
        'giftCoinAmount',
      });
      expect(
        (await journal.read('private-account-label'))!.binding.orderNo,
        'order_one',
      );
      expect(await journal.read('other-account'), isNull);
    },
  );

  test(
    'unresolved attempt blocks another order, even with concurrent writes',
    () async {
      final journal = AppleIapPurchaseJournal(MemoryKeyValueStore());
      final first = journal.start('a', _binding('order_one'));
      final second = journal.start('a', _binding('order_two'));
      await expectLater(second, throwsStateError);
      await first;
      expect((await journal.read('a'))!.binding.orderNo, 'order_one');
    },
  );

  test('stale session or wrong order cannot clear another attempt', () async {
    final journal = AppleIapPurchaseJournal(MemoryKeyValueStore());
    await journal.start('a', _binding('order_one'));
    await journal.markTerminal(
      'a',
      'order_one',
      'DELIVERED',
      stillCurrent: () => false,
    );
    await journal.markTerminal(
      'a',
      'order_other',
      'DELIVERED',
      stillCurrent: () => true,
    );
    expect((await journal.read('a'))!.state, 'ATTEMPTED');
  });

  test('delivery cannot be overwritten by a late cancellation', () async {
    final journal = AppleIapPurchaseJournal(MemoryKeyValueStore());
    await journal.start('a', _binding('order_one'));
    await journal.markTerminal(
      'a',
      'order_one',
      'DELIVERED',
      stillCurrent: () => true,
    );
    await journal.markTerminal(
      'a',
      'order_one',
      'CANCELLED_CONFIRMED',
      stillCurrent: () => true,
    );
    expect((await journal.read('a'))!.state, 'DELIVERED');
    await journal.start('a', _binding('order_two'));
    expect((await journal.read('a'))!.binding.orderNo, 'order_two');
  });

  test('invalid or expanded records fail closed', () {
    final valid =
        jsonDecode(
              AppleIapJournalEntry(
                binding: _binding('order_one'),
                state: 'ATTEMPTED',
              ).encode(),
            )
            as Map<String, dynamic>;
    for (final invalid in <Map<String, dynamic>>[
      {...valid, 'signedTransaction': 'must-not-persist'},
      {...valid, 'state': 'TIMEOUT_IS_CANCELLED'},
      {...valid, 'amountMinor': 0},
      {...valid, 'giftCoinAmount': -1},
      {...valid, 'appAccountToken': 'invalid'},
      {...valid}..remove('productId'),
    ]) {
      expect(
        () => AppleIapJournalEntry.decode(jsonEncode(invalid)),
        throwsStateError,
      );
    }
  });
}

AppleIapOrderBinding _binding(String orderNo) => AppleIapOrderBinding(
  orderNo: orderNo,
  productId: '00000000-0000-0000-0000-000000001101',
  storeProductId: 'com.kong373.voiceSocialApp.recharge.60',
  appAccountToken: '11111111-1111-4111-8111-111111111111',
  amountMinor: 600,
  giftCoinAmount: 60,
  environment: 'Sandbox',
  status: 'CONFIRMING',
  createdAt: null,
);

class _RecordingStore extends MemoryKeyValueStore {
  String? lastKey;
  String? lastValue;
  @override
  Future<void> write(String key, String value) async {
    lastKey = key;
    lastValue = value;
    await super.write(key, value);
  }
}
