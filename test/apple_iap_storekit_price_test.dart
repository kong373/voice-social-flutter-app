import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/infrastructure/apple_iap_storekit2_adapter.dart';

void main() {
  test(
    'StoreKit prices reject missing, floating, and imprecise values',
    () async {
      for (final Object? invalid in <Object?>[
        null,
        6.0,
        'NaN',
        '-6',
        '0',
        '6.0001',
        '1e3',
        '99999999999999999',
      ]) {
        final adapter = MethodChannelAppleIapStoreKit2Adapter(
          isIos: () => true,
          invoker: (method, arguments) async => <Object?>[
            <String, Object?>{
              'id': 'com.kong373.voiceSocialApp.recharge.60',
              'displayName': '60 Gift Coins',
              'description': 'Consumable',
              'displayPrice': '¥6.00',
              'productType': 'consumable',
              'price': invalid,
              'currencyCode': 'CNY',
            },
          ],
        );
        await expectLater(
          adapter.loadProducts(<String>[
            'com.kong373.voiceSocialApp.recharge.60',
          ]),
          throwsA(isA<ApiException>()),
          reason: 'Invalid price must not reach a purchase: $invalid',
        );
      }
    },
  );
}
