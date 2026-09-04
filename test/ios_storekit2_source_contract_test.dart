import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Runner owns a StoreKit 2 bridge with durable update recovery', () {
    final String swift = read('ios/Runner/AppDelegate.swift');

    expect(swift, contains('import StoreKit'));
    expect(swift, contains('Transaction.updates'));
    expect(swift, contains('Transaction.unfinished'));
    expect(swift, contains('.appAccountToken(appAccountToken)'));
    expect(swift, contains('verification.jwsRepresentation'));
    expect(swift, contains('StoreKit 2 requires iOS 15 or later'));

    final String beforeFinish =
        swift.split('func finish(transactionId: UInt64)')[0];
    expect(
      beforeFinish,
      isNot(contains('.finish()')),
      reason: 'purchase or update handling must not finish before backend ACK',
    );
    expect(swift, contains('This is the only native location'));
  });

  test('local StoreKit configuration contains consumables only', () {
    final File config = File('ios/RunnerTests/VoiceSocial.storekit');
    expect(config.existsSync(), isTrue);
    final Map<String, Object?> json =
        jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
    final List<Object?> products = json['products']! as List<Object?>;

    expect(products, isNotEmpty);
    for (final Object? raw in products) {
      final Map<String, Object?> item = raw! as Map<String, Object?>;
      expect(item['type'], 'Consumable');
      expect(
        item['productID']! as String,
        startsWith('com.kong373.voiceSocial.giftcoins.'),
      );
    }
    expect(json['subscriptionGroups'], isEmpty);
  });

  test('StoreKitTest automates product and Ask to Buy scenarios', () {
    final String tests = read('ios/RunnerTests/RunnerTests.swift');

    expect(tests, contains('import StoreKitTest'));
    expect(tests, contains('SKTestSession(contentsOf:'));
    expect(tests, contains('Product.products(for:'));
    expect(tests, contains('askToBuyEnabled = true'));
    expect(tests, contains('declineAskToBuyTransaction'));
    expect(tests, contains('clearTransactions()'));
  });

  test('Dart coordinator gates finish on authoritative backend ACK', () {
    final String coordinator = read(
      'lib/features/commerce/application/'
      'apple_iap_purchase_coordinator.dart',
    );

    final String models = read(
      'lib/features/commerce/domain/apple_iap_models.dart',
    );
    expect(models, contains('AppleIapDeliveryState.alreadyDelivered'));
    expect(
      coordinator,
      contains('if (ack.delivered && ack.finishAllowed)'),
    );
    expect(
      coordinator,
      contains('await _storeKit.finish(transaction.transactionId)'),
    );
    expect(
      coordinator,
      contains('Never finish on an ambiguous backend outcome'),
    );
  });

  test('iOS workflow is read-only and runs Phase 2 StoreKit gates', () {
    final String workflow = read('.github/workflows/m5-ios-client.yml');

    expect(workflow, contains('codex/m5-ios-phase2'));
    expect(workflow, contains('contents: read'));
    expect(workflow, isNot(contains('contents: write')));
    expect(workflow, isNot(contains('git push')));
    expect(workflow, isNot(contains('git commit')));
    expect(workflow, contains('ios_storekit2_source_contract_test.dart'));
    expect(workflow, contains('xcodebuild test'));
    expect(workflow, contains('VoiceSocial.storekit'));
  });

  test('Apple IAP does not weaken explicit phase exemptions', () {
    final String document = read('docs/ios/phase2-storekit2.md');

    expect(
      document,
      contains('CHUANGLAN_DELIVERY_RECEIPT=EXEMPT_NOT_COMPLETED'),
    );
    expect(
      document,
      contains('ALIPAY_ASYNC_CALLBACK=EXEMPT_NOT_COMPLETED'),
    );
    expect(
      document,
      contains('ALIPAY_REFUND=EXEMPT_NOT_COMPLETED'),
    );
    expect(
      document,
      contains('APPLE_IAP_TRANSACTION_UPDATES=IMPLEMENTED_IN_SOURCE'),
    );
    expect(
      document,
      contains('APPLE_IAP_REAL_DEVICE_PURCHASE=EXTERNAL_BLOCKED'),
    );
  });
}
