import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/commerce/catalog/data/mock_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

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

  test(
    'popular gift tab filters by category without truncating the catalog',
    () {
      const List<GiftCatalogItem> gifts = <GiftCatalogItem>[
        GiftCatalogItem(
          id: 'normal-1',
          name: '普通一',
          price: 1,
          category: GiftCatalogCategory.companionship,
        ),
        GiftCatalogItem(
          id: 'popular-1',
          name: '热门一',
          price: 1,
          category: GiftCatalogCategory.popular,
        ),
        GiftCatalogItem(
          id: 'popular-2',
          name: '热门二',
          price: 2,
          category: GiftCatalogCategory.popular,
        ),
        GiftCatalogItem(
          id: 'popular-3',
          name: '热门三',
          price: 3,
          category: GiftCatalogCategory.popular,
        ),
        GiftCatalogItem(
          id: 'celebration-1',
          name: '庆祝一',
          price: 4,
          category: GiftCatalogCategory.celebration,
        ),
      ];

      final List<GiftCatalogItem> visible = filterGiftCatalogItems(
        gifts: gifts,
        category: GiftCatalogCategory.popular,
      );
      expect(visible.map((GiftCatalogItem item) => item.id), <String>[
        'popular-1',
        'popular-2',
        'popular-3',
      ]);
    },
  );

  test('QA catalog keeps the reviewed eight-item popular grid explicit', () {
    final List<GiftCatalogItem> popular = filterGiftCatalogItems(
      gifts: qaReviewedPopularGiftCatalog,
      category: GiftCatalogCategory.popular,
    );

    expect(popular, hasLength(8));
    expect(popular.map((GiftCatalogItem item) => item.id), <String>[
      'mock-gift-101',
      'mock-gift-102',
      'mock-gift-103',
      'mock-gift-104',
      'mock-gift-105',
      'mock-gift-106',
      'mock-gift-107',
      'mock-gift-108',
    ]);
  });
}
