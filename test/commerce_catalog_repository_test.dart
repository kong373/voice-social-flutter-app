import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/catalog/data/mock_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';

void main() {
  test(
    'platform channels and youth-mode recharge boundary are exact',
    () async {
      final MockCommerceCatalogRepository repository =
          MockCommerceCatalogRepository();
      expect(
        repository.availableChannels(ClientStorePlatform.android),
        const <PaymentChannelType>[
          PaymentChannelType.wechat,
          PaymentChannelType.alipay,
        ],
      );
      expect(
        repository.availableChannels(ClientStorePlatform.ios),
        const <PaymentChannelType>[PaymentChannelType.appleIap],
      );

      final RechargeProduct product = (await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      )).first;
      await expectLater(
        repository.createRechargeOrder(
          account: '13800138000',
          product: product,
          channel: PaymentChannelType.wechat,
          platform: ClientStorePlatform.android,
          youthModeEnabled: true,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('payment return waits for server order confirmation', () async {
    final AppDependencies dependencies = AppDependencies.mock();
    final repository = dependencies.commerceCatalogRepository;
    final RechargeProduct product = (await repository.fetchRechargeProducts(
      platform: ClientStorePlatform.android,
    )).first;
    RechargeOrder order = await repository.createRechargeOrder(
      account: '13800138000',
      product: product,
      channel: PaymentChannelType.alipay,
      platform: ClientStorePlatform.android,
      youthModeEnabled: false,
    );
    expect(order.state, RechargeOrderState.created);
    PaymentOrder projected = (await dependencies.commerceRepository.fetchOrders(
      page: 1,
      pageSize: 20,
    )).items.firstWhere((PaymentOrder item) => item.orderNo == order.orderNo);
    expect(projected.status, PaymentOrderStatus.pending);

    order = await repository.invokePayment(order);
    expect(order.state, RechargeOrderState.confirming);
    projected = (await dependencies.commerceRepository.fetchOrders(
      page: 1,
      pageSize: 20,
    )).items.firstWhere((PaymentOrder item) => item.orderNo == order.orderNo);
    expect(projected.status, PaymentOrderStatus.confirming);
    order = await repository.queryRechargeOrder(order);
    expect(order.state, RechargeOrderState.confirming);
    order = await repository.queryRechargeOrder(order);
    expect(order.state, RechargeOrderState.succeeded);
    projected = (await dependencies.commerceRepository.fetchOrders(
      page: 1,
      pageSize: 20,
    )).items.firstWhere((PaymentOrder item) => item.orderNo == order.orderNo);
    expect(projected.status, PaymentOrderStatus.succeeded);
  });

  test(
    'ordinary gifts and decoration state exclude retired capabilities',
    () async {
      final MockCommerceCatalogRepository repository =
          MockCommerceCatalogRepository();
      final List<GiftCatalogItem> gifts = await repository.fetchGiftCatalog();
      final String names = gifts
          .map((GiftCatalogItem item) => item.name)
          .join(' ');
      for (final String retired in <String>[
        '红包',
        'KTV',
        '点歌',
        '盲盒',
        '魔法球',
        '团子',
        '情书',
      ]) {
        expect(names.contains(retired), isFalse);
      }

      List<DecorationItem> decorations = await repository.fetchDecorations();
      final DecorationItem unowned = decorations.firstWhere(
        (DecorationItem item) => !item.owned,
      );
      await repository.purchaseDecoration(unowned.id);
      await repository.setDecorationEquipped(
        decorationId: unowned.id,
        equipped: true,
      );
      decorations = await repository.fetchDecorations();
      final DecorationItem updated = decorations.firstWhere(
        (DecorationItem item) => item.id == unowned.id,
      );
      expect(updated.owned, isTrue);
      expect(updated.equipped, isTrue);
    },
  );
}
