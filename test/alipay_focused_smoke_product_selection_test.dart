import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/alipay_focused_smoke_selection.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';

void main() {
  test('focused smoke selects the smallest positive amountMinor', () {
    const List<RechargeProduct> products = <RechargeProduct>[
      RechargeProduct(
        id: 'high',
        giftCoins: 300,
        priceCny: 3,
        amountMinor: 300,
      ),
      RechargeProduct(id: 'zero', giftCoins: 1, priceCny: 0.01, amountMinor: 0),
      RechargeProduct(
        id: 'disabled-low',
        giftCoins: 1,
        priceCny: 0.02,
        amountMinor: 2,
        enabled: false,
      ),
      RechargeProduct(id: 'low', giftCoins: 2, priceCny: 0.02, amountMinor: 2),
      RechargeProduct(
        id: 'lowest',
        giftCoins: 1,
        priceCny: 0.01,
        amountMinor: 1,
      ),
    ];

    expect(selectLowestPositiveEnabledRechargeProduct(products)?.id, 'lowest');
  });

  test(
    'focused smoke refuses an enabled product without positive amountMinor',
    () {
      const List<RechargeProduct> products = <RechargeProduct>[
        RechargeProduct(id: 'zero', giftCoins: 1, priceCny: 1, amountMinor: 0),
        RechargeProduct(id: 'missing', giftCoins: 1, priceCny: 1),
      ];

      expect(selectLowestPositiveEnabledRechargeProduct(products), isNull);
    },
  );
}
