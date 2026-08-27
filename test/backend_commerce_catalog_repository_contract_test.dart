import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';

void main() {
  test(
    'recharge catalog uses platform query and parses authoritative money',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'platform': request.query['platform'],
          'list': request.query['platform'] == 'ANDROID'
              ? <Object?>[
                  <String, Object?>{
                    'productId': '00000000-0000-0000-0000-000000001001',
                    'title': '60礼物币',
                    'amountMinor': 600,
                    'amount': 6.00,
                    'giftCoinAmount': 60,
                    'bonusGiftCoin': 5,
                  },
                ]
              : <Object?>[],
          'total': request.query['platform'] == 'ANDROID' ? 1 : 0,
          'orderCreationStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);
      final BackendCommerceCatalogRepository repository = harness.repository;

      expect(repository.supportsRechargeCatalog, isTrue);
      expect(repository.supportsPaymentChannelInvocation, isFalse);
      final List<RechargeProduct> android = await repository
          .fetchRechargeProducts(platform: ClientStorePlatform.android);
      final List<RechargeProduct> ios = await repository.fetchRechargeProducts(
        platform: ClientStorePlatform.ios,
      );

      expect(android, hasLength(1));
      expect(android.single.id, '00000000-0000-0000-0000-000000001001');
      expect(android.single.priceCny, 6);
      expect(android.single.giftCoins, 60);
      expect(android.single.bonusGiftCoins, 5);
      expect(android.single.label, '60礼物币');
      expect(ios, isEmpty);
      expect(harness.requests[0].method, 'GET');
      expect(harness.requests[0].query, <String, String>{
        'platform': 'ANDROID',
      });
      expect(harness.requests[1].query, <String, String>{'platform': 'IOS'});
    },
  );

  test(
    'recharge catalog rejects contract drift instead of hiding it',
    () async {
      final Map<String, Object?> validProduct = <String, Object?>{
        'productId': '00000000-0000-0000-0000-000000001001',
        'title': '60礼物币',
        'amountMinor': 600,
        'amount': 6.00,
        'giftCoinAmount': 60,
        'bonusGiftCoin': 5,
      };
      final List<Map<String, Object?>> payloads = <Map<String, Object?>>[
        <String, Object?>{
          'platform': 'IOS',
          'list': <Object?>[validProduct],
          'total': 1,
          'orderCreationStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        },
        <String, Object?>{
          'platform': 'ANDROID',
          'list': <Object?>[validProduct, 'malformed'],
          'total': 2,
          'orderCreationStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        },
        <String, Object?>{
          'platform': 'ANDROID',
          'list': <Object?>[validProduct],
          'total': 2,
          'orderCreationStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        },
        <String, Object?>{
          'platform': 'ANDROID',
          'list': <Object?>[validProduct],
          'total': 1,
          'orderCreationStatus': 'NOT_READY',
          'providerInvocation': false,
        },
        <String, Object?>{
          'platform': 'ANDROID',
          'list': <Object?>[
            <String, Object?>{...validProduct, 'amount': 7.00},
          ],
          'total': 1,
          'orderCreationStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        },
      ];

      for (final Map<String, Object?> payload in payloads) {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(payload),
        );
        await expectLater(
          harness.repository.fetchRechargeProducts(
            platform: ClientStorePlatform.android,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        await harness.close();
      }
    },
  );

  test('formal payment remains fail-closed without writing an order', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return _Response.ok(<String, Object?>{
        'orderNo': 'order-1',
        'bool': true,
        'status': 'SUCCEEDED',
      });
    });
    addTearDown(harness.close);
    final BackendCommerceCatalogRepository repository = harness.repository;
    const RechargeProduct product = RechargeProduct(
      id: '00000000-0000-0000-0000-000000001001',
      giftCoins: 60,
      priceCny: 6,
    );

    final RechargeEligibility youth = await repository.checkRechargeEligibility(
      youthModeEnabled: true,
    );
    final RechargeEligibility vendorBlocked = await repository
        .checkRechargeEligibility(youthModeEnabled: false);
    expect(youth.allowed, isFalse);
    expect(youth.message, contains('青少年模式'));
    expect(vendorBlocked.allowed, isFalse);
    expect(vendorBlocked.message, contains('支付'));
    await expectLater(
      repository.createRechargeOrder(
        account: 'user-1',
        product: product,
        channel: PaymentChannelType.wechat,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      ),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.configuration,
        ),
      ),
    );
    await expectLater(
      repository.invokePayment(
        RechargeOrder(
          orderNo: 'order-1',
          account: 'user-1',
          product: product,
          channel: PaymentChannelType.wechat,
          state: RechargeOrderState.created,
          createdAt: DateTime(2026),
        ),
      ),
      throwsA(isA<ApiException>()),
    );
    expect(harness.requests, isEmpty);

    final RechargeOrder result = await repository.queryRechargeOrder(
      RechargeOrder(
        orderNo: 'order-1',
        account: 'user-1',
        product: product,
        channel: PaymentChannelType.wechat,
        state: RechargeOrderState.confirming,
        createdAt: DateTime(2026),
      ),
    );
    expect(result.state, RechargeOrderState.succeeded);
    expect(harness.requests.single.query, <String, String>{
      'orderNo': 'order-1',
    });
  });

  test(
    'recharge status requires matching order and consistent authority',
    () async {
      const RechargeProduct product = RechargeProduct(
        id: '00000000-0000-0000-0000-000000001001',
        giftCoins: 60,
        priceCny: 6,
      );
      final RechargeOrder order = RechargeOrder(
        orderNo: 'order-1',
        account: 'user-1',
        product: product,
        channel: PaymentChannelType.wechat,
        state: RechargeOrderState.confirming,
        createdAt: DateTime(2026),
      );
      final List<Object?> malformed = <Object?>[
        true,
        <String, Object?>{'bool': true, 'status': 'SUCCEEDED'},
        <String, Object?>{
          'orderNo': 'order-2',
          'bool': true,
          'status': 'SUCCEEDED',
        },
        <String, Object?>{
          'orderNo': 'order-1',
          'bool': true,
          'status': 'FAILED',
        },
        <String, Object?>{
          'orderNo': 'order-1',
          'bool': false,
          'status': 'UNKNOWN',
        },
        <String, Object?>{'orderNo': 'order-1', 'status': 'CONFIRMING'},
      ];

      for (final Object? data in malformed) {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(data),
        );
        try {
          await expectLater(
            harness.repository.queryRechargeOrder(order),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'gift catalog retains UUID and accepts only approved first-party data',
    () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'giftId': '00000000-0000-0000-0000-000000002001',
              'giftName': '星光',
              'category': 'NORMAL',
              'price': 10,
              'unitCostGiftCoin': 10,
              'creatorIncomeMinor': 5,
              'charmValue': 1,
              'assetKey': 'gift/star-light',
              'animationKey': 'gift/star-light.json',
            },
          ],
          'total': 1,
          'retiredCategoriesPresent': false,
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);

      final List<GiftCatalogItem> gifts = await harness.repository
          .fetchGiftCatalog();
      expect(gifts, hasLength(1));
      expect(gifts.single.id, '00000000-0000-0000-0000-000000002001');
      expect(gifts.single.price, 10);
      expect(gifts.single.category, GiftCatalogCategory.companionship);
      expect(gifts.single.assetUrl, 'gift/star-light');
      expect(harness.requests.single.method, 'GET');
      expect(harness.requests.single.query, isEmpty);
      expect(
        harness.requests.any(
          (RequestRecord item) => item.path.contains('userPackGift'),
        ),
        isFalse,
      );
    },
  );

  test(
    'gift category mapping is exact and unknown categories fail closed',
    () async {
      final _Harness popularHarness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'giftId': '00000000-0000-0000-0000-000000002009',
              'giftName': '热榜礼物',
              'category': 'POPULAR',
              'price': 10,
              'unitCostGiftCoin': 10,
            },
          ],
          'total': 1,
          'retiredCategoriesPresent': false,
          'providerInvocation': false,
        }),
      );
      addTearDown(popularHarness.close);
      final List<GiftCatalogItem> popular = await popularHarness.repository
          .fetchGiftCatalog();
      expect(popular.single.category, GiftCatalogCategory.popular);

      final _Harness celebrationHarness = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'giftId': '00000000-0000-0000-0000-000000002010',
              'giftName': '庆祝礼物',
              'category': 'CELEBRATION',
              'price': 10,
              'unitCostGiftCoin': 10,
            },
          ],
          'total': 1,
          'retiredCategoriesPresent': false,
          'providerInvocation': false,
        }),
      );
      addTearDown(celebrationHarness.close);
      await expectLater(
        celebrationHarness.repository.fetchGiftCatalog(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test(
    'gift catalog fails closed on malformed, retired, or inconsistent server data',
    () async {
      final Map<String, Object?> validGift = <String, Object?>{
        'giftId': '00000000-0000-0000-0000-000000002001',
        'giftName': '星光',
        'category': 'NORMAL',
        'price': 10,
        'unitCostGiftCoin': 10,
        'creatorIncomeMinor': 5,
        'charmValue': 1,
        'assetKey': 'gift/star-light',
        'animationKey': 'gift/star-light.json',
      };
      final List<Map<String, Object?>> payloads = <Map<String, Object?>>[
        <String, Object?>{
          'list': <Object?>[validGift, 'malformed'],
          'total': 2,
          'retiredCategoriesPresent': false,
          'providerInvocation': false,
        },
        <String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              ...validGift,
              'giftId': '00000000-0000-0000-0000-000000002002',
              'giftName': '月度会员礼物',
              'category': 'MEMBERSHIP',
            },
          ],
          'total': 1,
          'retiredCategoriesPresent': true,
          'providerInvocation': false,
        },
        <String, Object?>{
          'list': <Object?>[validGift],
          'total': 2,
          'retiredCategoriesPresent': false,
          'providerInvocation': false,
        },
        <String, Object?>{
          'list': <Object?>[validGift],
          'total': 1,
          'retiredCategoriesPresent': false,
          'providerInvocation': true,
        },
      ];

      for (final Map<String, Object?> payload in payloads) {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(payload),
        );
        await expectLater(
          harness.repository.fetchGiftCatalog(),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        await harness.close();
      }
    },
  );

  test('decoration list uses GET and parses backend string types', () async {
    final _Harness harness = await _Harness.start((RequestRecord request) {
      return _Response.ok(<String, Object?>{
        'list': <Object?>[
          <String, Object?>{
            'decorationId': '00000000-0000-0000-0000-000000004001',
            'name': '星环头像框',
            'type': 'AVATAR_FRAME',
            'giftCoinCost': 520,
            'assetKey': 'decoration/star-ring-frame',
            'owned': true,
            'equipped': true,
            'expiresAt': '2026-09-21T10:00:00Z',
          },
          <String, Object?>{
            'decorationId': '00000000-0000-0000-0000-000000004002',
            'name': '流光进场',
            'type': 'ROOM_ENTRY',
            'giftCoinCost': 999,
            'owned': false,
            'equipped': false,
          },
          <String, Object?>{
            'decorationId': '00000000-0000-0000-0000-000000004003',
            'name': '陪伴徽章',
            'type': 'PROFILE_BADGE',
            'giftCoinCost': 1880,
            'owned': false,
            'equipped': false,
          },
          <String, Object?>{
            'decorationId': '00000000-0000-0000-0000-000000004004',
            'name': '星光昵称',
            'type': 'NICKNAME',
            'giftCoinCost': 320,
            'owned': false,
            'equipped': false,
          },
          <String, Object?>{
            'decorationId': '00000000-0000-0000-0000-000000004005',
            'name': '银河声波',
            'type': 'VOICE_WAVE',
            'giftCoinCost': 460,
            'owned': false,
            'equipped': false,
          },
        ],
        'total': 5,
        'providerInvocation': false,
      });
    });
    addTearDown(harness.close);

    final List<DecorationItem> items = await harness.repository
        .fetchDecorations();
    expect(items.map((DecorationItem item) => item.kind), <DecorationKind>[
      DecorationKind.avatarFrame,
      DecorationKind.entrance,
      DecorationKind.profileCard,
      DecorationKind.nickname,
      DecorationKind.voiceWave,
    ]);
    expect(items.first.priceGiftCoins, 520);
    expect(items.first.assetUrl, 'decoration/star-ring-frame');
    expect(items.first.expiresAt, DateTime.parse('2026-09-21T10:00:00Z'));
    expect(harness.requests.single.method, 'GET');
    expect(harness.requests.single.body, isNull);
  });

  test(
    'decoration catalog rejects malformed items and inconsistent metadata',
    () async {
      final Map<String, Object?> validDecoration = <String, Object?>{
        'decorationId': '00000000-0000-0000-0000-000000004001',
        'name': '星环头像框',
        'type': 'AVATAR_FRAME',
        'giftCoinCost': 520,
        'durationDays': 30,
        'assetKey': 'decoration/star-ring-frame',
        'owned': true,
        'equipped': true,
        'expiresAt': '2026-09-21T10:00:00Z',
      };
      final List<Map<String, Object?>> payloads = <Map<String, Object?>>[
        <String, Object?>{
          'list': <Object?>[validDecoration, 7],
          'total': 2,
          'providerInvocation': false,
        },
        <String, Object?>{
          'list': <Object?>[validDecoration],
          'total': 0,
          'providerInvocation': false,
        },
        <String, Object?>{
          'list': <Object?>[validDecoration],
          'total': 1,
          'providerInvocation': true,
        },
      ];

      for (final Map<String, Object?> payload in payloads) {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(payload),
        );
        await expectLater(
          harness.repository.fetchDecorations(),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );
        await harness.close();
      }
    },
  );

  test('catalog list aliases must agree when repeated', () async {
    Map<String, Object?> decoration(String id) => <String, Object?>{
      'decorationId': id,
      'name': '星环头像框',
      'type': 'AVATAR_FRAME',
      'giftCoinCost': 520,
      'owned': false,
      'equipped': false,
    };
    final _Harness harness = await _Harness.start(
      (RequestRecord request) => _Response.ok(<String, Object?>{
        'list': <Object?>[decoration('00000000-0000-0000-0000-000000004001')],
        'items': <Object?>[decoration('00000000-0000-0000-0000-000000004002')],
        'total': 1,
        'providerInvocation': false,
      }),
    );
    addTearDown(harness.close);

    await expectLater(
      harness.repository.fetchDecorations(),
      throwsA(
        isA<ApiException>().having(
          (ApiException error) => error.kind,
          'kind',
          ApiFailureKind.protocol,
        ),
      ),
    );
  });

  test(
    'decoration writes use UUID bodies and coalesce double submit',
    () async {
      const String decorationId = '00000000-0000-0000-0000-000000004001';
      int purchases = 0;
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        if (request.path == '/app-api/mall/userBuyOrGiveGoods') {
          purchases += 1;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _Response.ok(<String, Object?>{
            'decorationId': decorationId,
            'owned': true,
            'equipped': false,
          });
        }
        if (request.path == '/app-api/user/userDecorations/putOn') {
          return _Response.ok(<String, Object?>{
            'decorationId': decorationId,
            'type': 'AVATAR_FRAME',
            'equipped': true,
          });
        }
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'decorationId': decorationId,
              'name': '星环头像框',
              'type': 'AVATAR_FRAME',
              'giftCoinCost': 520,
              'owned': true,
              'equipped': request.method == 'GET' && purchases > 0,
            },
          ],
          'total': 1,
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);

      final List<DecorationItem> purchased =
          await Future.wait<DecorationItem>(<Future<DecorationItem>>[
            harness.repository.purchaseDecoration(decorationId),
            harness.repository.purchaseDecoration(decorationId),
          ]);
      expect(purchased, hasLength(2));
      expect(purchases, 1);
      final DecorationItem equipped = await harness.repository
          .setDecorationEquipped(decorationId: decorationId, equipped: true);
      expect(equipped.equipped, isTrue);

      final RequestRecord purchase = harness.requests.first;
      expect(purchase.method, 'POST');
      expect(purchase.body, <String, Object?>{'decorationId': decorationId});
      expect(purchase.requestId, startsWith('flutter-decoration-purchase-'));
      expect(purchase.requestId.length, lessThanOrEqualTo(80));
      final RequestRecord equip = harness.requests.firstWhere(
        (RequestRecord item) => item.path.endsWith('/putOn'),
      );
      expect(equip.method, 'POST');
      expect(equip.body, <String, Object?>{
        'decorationId': decorationId,
        'equipped': true,
      });
      expect(equip.requestId, startsWith('flutter-'));
    },
  );

  test(
    'decoration purchase does not reconcile a pre-owned item after response loss',
    () async {
      const String decorationId = '00000000-0000-0000-0000-000000004010';
      int economicWrites = 0;
      final Set<String> committedRequestIds = <String>{};
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        if (request.path == '/app-api/mall/userBuyOrGiveGoods') {
          if (committedRequestIds.add(request.requestId)) {
            economicWrites += 1;
          }
          return _Response(
            statusCode: 500,
            code: 50001,
            message: 'committed but response lost',
            data: null,
          );
        }
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'decorationId': decorationId,
              'name': '流星进场',
              'type': 'ROOM_ENTRY',
              'giftCoinCost': 188,
              'owned': economicWrites > 0,
              'equipped': false,
            },
          ],
          'total': 1,
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.purchaseDecoration(decorationId),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.server,
          ),
        ),
      );
      expect(economicWrites, 1);
      expect(
        harness.requests
            .where(
              (RequestRecord item) =>
                  item.path == '/app-api/mall/userBuyOrGiveGoods',
            )
            .length,
        1,
      );
    },
  );

  test(
    'decoration purchase and equip reject negative write authority',
    () async {
      const String decorationId = '00000000-0000-0000-0000-000000004014';

      Future<void> expectPurchaseRejected(Map<String, Object?> response) async {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(response),
        );
        try {
          await expectLater(
            harness.repository.purchaseDecoration(decorationId),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
          expect(harness.requests, hasLength(1));
          expect(harness.requests.single.path, contains('userBuyOrGiveGoods'));
        } finally {
          await harness.close();
        }
      }

      await expectPurchaseRejected(<String, Object?>{
        'decorationId': decorationId,
        'success': false,
        'owned': true,
      });
      await expectPurchaseRejected(<String, Object?>{
        'decorationId': decorationId,
        'status': 'FAILED',
        'owned': true,
      });
      await expectPurchaseRejected(<String, Object?>{
        'decorationId': decorationId,
        'owned': true,
        'providerInvocation': true,
      });

      Future<void> expectEquipRejected(Map<String, Object?> response) async {
        final _Harness harness = await _Harness.start(
          (RequestRecord request) => _Response.ok(response),
        );
        try {
          await expectLater(
            harness.repository.setDecorationEquipped(
              decorationId: decorationId,
              equipped: true,
            ),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
          expect(harness.requests, hasLength(1));
          expect(harness.requests.single.path, contains('/putOn'));
        } finally {
          await harness.close();
        }
      }

      await expectEquipRejected(<String, Object?>{
        'decorationId': decorationId,
        'success': false,
        'equipped': true,
      });
      await expectEquipRejected(<String, Object?>{
        'decorationId': decorationId,
        'state': 'FAILED',
        'equipped': true,
      });
      await expectEquipRejected(<String, Object?>{
        'decorationId': decorationId,
        'equipped': true,
        'providerInvocation': true,
      });
    },
  );

  test(
    'decoration purchase ambiguous retry reuses the same request id until success',
    () async {
      const String decorationId = '00000000-0000-0000-0000-000000004011';
      int purchaseAttempts = 0;
      int economicWrites = 0;
      final Set<String> committedRequestIds = <String>{};
      bool owned = false;
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        if (request.path == '/app-api/mall/userBuyOrGiveGoods') {
          purchaseAttempts += 1;
          if (committedRequestIds.add(request.requestId)) {
            economicWrites += 1;
          }
          if (purchaseAttempts == 1) {
            return _Response(
              statusCode: 500,
              code: 50001,
              message: 'response lost before confirmation',
              data: null,
            );
          }
          owned = true;
          return _Response.ok(<String, Object?>{'accepted': true});
        }
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'decorationId': decorationId,
              'name': '流星进场',
              'type': 'ROOM_ENTRY',
              'giftCoinCost': 188,
              'owned': owned,
              'equipped': false,
            },
          ],
          'total': 1,
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.purchaseDecoration(decorationId),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.server,
          ),
        ),
      );
      final DecorationItem purchased = await harness.repository
          .purchaseDecoration(decorationId);
      expect(purchased.owned, isTrue);

      final List<String> requestIds = harness.requests
          .where(
            (RequestRecord item) =>
                item.path == '/app-api/mall/userBuyOrGiveGoods',
          )
          .map((RequestRecord item) => item.requestId)
          .toList(growable: false);
      expect(requestIds, hasLength(2));
      expect(requestIds[0], requestIds[1]);
      expect(economicWrites, 1);
    },
  );

  test(
    'decoration purchase rotates request id after definitive 40903 conflict',
    () async {
      const String decorationId = '00000000-0000-0000-0000-000000004012';
      int purchaseAttempts = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path == '/app-api/mall/userBuyOrGiveGoods') {
          purchaseAttempts += 1;
          if (purchaseAttempts == 1) {
            return _Response(
              statusCode: 409,
              code: 40903,
              message: 'request fingerprint mismatch',
              data: null,
            );
          }
        }
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'decorationId': decorationId,
              'name': '流星进场',
              'type': 'ROOM_ENTRY',
              'giftCoinCost': 188,
              'owned': false,
              'equipped': false,
            },
          ],
          'total': 1,
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.purchaseDecoration(decorationId),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.code,
            'code',
            40903,
          ),
        ),
      );
      await expectLater(
        harness.repository.purchaseDecoration(decorationId),
        throwsA(isA<ApiException>()),
      );

      final List<String> requestIds = harness.requests
          .where(
            (RequestRecord item) =>
                item.path == '/app-api/mall/userBuyOrGiveGoods',
          )
          .map((RequestRecord item) => item.requestId)
          .toList(growable: false);
      expect(requestIds, hasLength(2));
      expect(requestIds[0], isNot(requestIds[1]));
    },
  );

  test(
    'opposite decoration intents are serialized so stale work cannot win',
    () async {
      const String decorationId = '00000000-0000-0000-0000-000000004002';
      bool equippedState = false;
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        if (request.path.endsWith('/putOn')) {
          final bool target =
              (request.body! as Map<String, Object?>)['equipped']! as bool;
          if (target) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          equippedState = target;
          return _Response.ok(<String, Object?>{
            'decorationId': decorationId,
            'type': 'ROOM_ENTRY',
            'equipped': target,
          });
        }
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'decorationId': decorationId,
              'name': '流光进场',
              'type': 'ROOM_ENTRY',
              'giftCoinCost': 999,
              'owned': true,
              'equipped': equippedState,
            },
          ],
          'total': 1,
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);

      final List<DecorationItem> results =
          await Future.wait<DecorationItem>(<Future<DecorationItem>>[
            harness.repository.setDecorationEquipped(
              decorationId: decorationId,
              equipped: true,
            ),
            harness.repository.setDecorationEquipped(
              decorationId: decorationId,
              equipped: false,
            ),
          ]);
      expect(results.first.equipped, isTrue);
      expect(results.last.equipped, isFalse);
      expect(
        (await harness.repository.fetchDecorations()).single.equipped,
        isFalse,
      );
    },
  );

  test(
    'decoration equip retains its request id while backend processing is pending',
    () async {
      const String decorationId = '00000000-0000-0000-0000-000000004013';
      int equipAttempts = 0;
      bool equippedState = false;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/putOn')) {
          equipAttempts += 1;
          if (equipAttempts == 1) {
            return _Response(
              statusCode: 409,
              code: 40902,
              message: 'request still in progress',
              data: null,
            );
          }
          equippedState = true;
          return _Response.ok(<String, Object?>{
            'decorationId': decorationId,
            'type': 'ROOM_ENTRY',
            'equipped': true,
          });
        }
        return _Response.ok(<String, Object?>{
          'list': <Object?>[
            <String, Object?>{
              'decorationId': decorationId,
              'name': '星轨进场',
              'type': 'ROOM_ENTRY',
              'giftCoinCost': 188,
              'owned': true,
              'equipped': equippedState,
            },
          ],
          'total': 1,
          'providerInvocation': false,
        });
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.setDecorationEquipped(
          decorationId: decorationId,
          equipped: true,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.code,
            'code',
            40902,
          ),
        ),
      );
      final DecorationItem result = await harness.repository
          .setDecorationEquipped(decorationId: decorationId, equipped: true);

      expect(result.equipped, isTrue);
      final List<String> requestIds = harness.requests
          .where((RequestRecord item) => item.path.endsWith('/putOn'))
          .map((RequestRecord item) => item.requestId)
          .toList(growable: false);
      expect(requestIds, hasLength(2));
      expect(requestIds[0], isNotEmpty);
      expect(requestIds[1], requestIds[0]);
    },
  );

  test(
    'decoration equip rejects wrong identity, reverse state, and stale refresh',
    () async {
      const String decorationId = '00000000-0000-0000-0000-000000004003';

      Future<void> expectRejected({
        required Map<String, Object?> postResponse,
        required String refreshId,
        required bool refreshEquipped,
      }) async {
        final _Harness harness = await _Harness.start((RequestRecord request) {
          if (request.path.endsWith('/putOn')) {
            return _Response.ok(postResponse);
          }
          return _Response.ok(<String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'decorationId': refreshId,
                'name': '星轨进场',
                'type': 'ROOM_ENTRY',
                'giftCoinCost': 188,
                'owned': true,
                'equipped': refreshEquipped,
              },
            ],
            'total': 1,
            'providerInvocation': false,
          });
        });
        try {
          await expectLater(
            harness.repository.setDecorationEquipped(
              decorationId: decorationId,
              equipped: true,
            ),
            throwsA(
              isA<ApiException>().having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        } finally {
          await harness.close();
        }
      }

      await expectRejected(
        postResponse: <String, Object?>{
          'decorationId': '00000000-0000-0000-0000-000000004099',
          'type': 'ROOM_ENTRY',
          'equipped': true,
        },
        refreshId: decorationId,
        refreshEquipped: true,
      );
      await expectRejected(
        postResponse: <String, Object?>{
          'decorationId': decorationId,
          'type': 'ROOM_ENTRY',
          'equipped': false,
        },
        refreshId: decorationId,
        refreshEquipped: true,
      );
      await expectRejected(
        postResponse: <String, Object?>{
          'decorationId': decorationId,
          'type': 'ROOM_ENTRY',
          'equipped': true,
        },
        refreshId: decorationId,
        refreshEquipped: false,
      );
    },
  );

  for (final (int, ApiFailureKind) failure in <(int, ApiFailureKind)>[
    (400, ApiFailureKind.validation),
    (403, ApiFailureKind.forbidden),
    (409, ApiFailureKind.conflict),
    (422, ApiFailureKind.validation),
    (500, ApiFailureKind.server),
  ]) {
    test('catalog preserves ${failure.$1} error envelope', () async {
      final _Harness harness = await _Harness.start((RequestRecord request) {
        return _Response(
          statusCode: failure.$1,
          code: failure.$1,
          message: 'catalog-${failure.$1}',
          data: null,
        );
      });
      addTearDown(harness.close);
      await expectLater(
        harness.repository.fetchGiftCatalog(),
        throwsA(
          isA<ApiException>()
              .having((ApiException error) => error.kind, 'kind', failure.$2)
              .having(
                (ApiException error) => error.httpStatus,
                'httpStatus',
                failure.$1,
              ),
        ),
      );
    });
  }

  test(
    'payment invocation requires both server READY and a local Alipay bridge',
    () async {
      final Map<String, Object?> validProduct = <String, Object?>{
        'productId': '00000000-0000-0000-0000-000000001001',
        'title': '60礼物币',
        'amountMinor': 600,
        'amount': 6.00,
        'giftCoinAmount': 60,
        'bonusGiftCoin': 0,
      };
      final _Harness serverReady = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'platform': 'ANDROID',
          'list': <Object?>[validProduct],
          'total': 1,
          'orderCreationStatus': 'READY',
          'providerInvocation': false,
        }),
      );
      final BackendCommerceCatalogRepository serverReadyLocalDisabled =
          serverReady.repository;
      await serverReadyLocalDisabled.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      expect(
        serverReadyLocalDisabled.supportsPaymentChannelInvocation,
        isFalse,
      );
      await serverReady.close();

      final _Harness localReady = await _Harness.start(
        (RequestRecord request) => _Response.ok(<String, Object?>{
          'platform': 'ANDROID',
          'list': <Object?>[validProduct],
          'total': 1,
          'orderCreationStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        }),
        alipayAppPayAdapter: _AvailableAlipayAdapter(),
      );
      await localReady.repository.fetchRechargeProducts(
        platform: ClientStorePlatform.android,
      );
      expect(localReady.repository.supportsPaymentChannelInvocation, isFalse);
      await localReady.close();
    },
  );
}

class _Harness {
  _Harness._(
    this.server,
    this.requests, {
    AlipayAppPayAdapter? alipayAppPayAdapter,
  }) : repository = BackendCommerceCatalogRepository(
         apiClient: ApiClient(
           baseUri: Uri.parse(
             'http://${server.address.address}:${server.port}/',
           ),
           clientType: 'Android',
           clientInnerVersion: '6',
           authorizationProvider: () => 'Bearer contract-test',
         ),
         routes: const BackendRouteCatalog(),
         alipayAppPayAdapter: alipayAppPayAdapter,
       );

  final HttpServer server;
  final List<RequestRecord> requests;
  final BackendCommerceCatalogRepository repository;

  static Future<_Harness> start(
    FutureOr<_Response> Function(RequestRecord) handler, {
    AlipayAppPayAdapter? alipayAppPayAdapter,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<RequestRecord> requests = <RequestRecord>[];
    final _Harness harness = _Harness._(
      server,
      requests,
      alipayAppPayAdapter: alipayAppPayAdapter,
    );
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? decodedBody = rawBody.trim().isEmpty
          ? null
          : jsonDecode(rawBody);
      final RequestRecord record = RequestRecord(
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        authorization: captureContractAuthorization(request),
        requestId: request.headers.value('X-Request-Id') ?? '',
        body: decodedBody is Map
            ? Map<String, Object?>.from(decodedBody)
            : decodedBody,
      );
      requests.add(record);
      final _Response response = await handler(record);
      request.response.statusCode = response.statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': response.code,
          'message': response.message,
          'data': response.data,
        }),
      );
      await request.response.close();
    });
    return harness;
  }

  Future<void> close() => server.close(force: true);
}

class _AvailableAlipayAdapter implements AlipayAppPayAdapter {
  @override
  bool get isAvailable => true;

  @override
  Future<AlipayAppPayResult> pay({
    required String orderNo,
    required String orderString,
  }) async {
    return const AlipayAppPayResult(
      outcome: AlipayAppPayOutcome.processing,
      reason: AlipayAppPayReason.processing,
    );
  }
}

class RequestRecord {
  const RequestRecord({
    required this.method,
    required this.path,
    required this.query,
    required this.authorization,
    required this.requestId,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final String authorization;
  final String requestId;
  final Object? body;
}

class _Response {
  const _Response({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.data,
  });

  const _Response.ok(Object? data)
    : statusCode = 200,
      code = 200,
      message = 'OK',
      data = data;

  final int statusCode;
  final int code;
  final String message;
  final Object? data;
}
