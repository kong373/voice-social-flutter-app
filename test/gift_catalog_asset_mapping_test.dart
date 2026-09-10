import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/catalog/data/backend_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';

import 'support/media_http_fakes.dart';

const _assets = [
  'assets/runtime/gift-whale.png',
  'assets/runtime/gift-blossom.png',
  'assets/runtime/gift-ticket.png',
  'assets/runtime/gift-celebration-banner.png',
];

void main() {
  for (final sheet in [true, false]) {
    final surface = sheet ? 'GiftSheet' : 'GiftCatalogPage';
    for (final asset in _assets) {
      testWidgets(
        '$surface renders backend assetKey $asset for the same UUID',
        (tester) async {
          final fixture = _Fixture(asset);
          await _mount(tester, fixture, sheet: sheet);
          _expectAsset(tester, asset);
          fixture.expectOnlyCatalogRead();
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets(
      '$surface retains legacy UUID fallback and never loads unknown paths',
      (tester) async {
        for (final key in <String?>[
          null,
          '',
          'gift/star-light',
          'gift/cloud',
          'gift/bouquet',
          'gift/shining-moment',
          'https://external.invalid/gift-whale.png',
          '//external.invalid/gift-whale.png',
          'file:///tmp/gift-whale.png',
          'assets/runtime/../runtime/gift-whale.png',
          'assets/runtime/gift-whale.png?remote=1',
          'assets/runtime/gift-unknown.png',
          'assets/runtime/GIFT-WHALE.png',
        ]) {
          final fixture = _Fixture(key);
          await _mount(tester, fixture, sheet: sheet);
          // Frozen pre-change fallbacks for UUID ...778 differ by surface.
          // Adding server-selected assets must not remap old symbolic catalogs.
          _expectAsset(
            tester,
            sheet
                ? 'assets/runtime/gift-blossom.png'
                : 'assets/runtime/gift-ticket.png',
          );
          fixture.expectOnlyCatalogRead();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}

void _expectAsset(WidgetTester tester, String expected) {
  final finder = find.descendant(
    of: find.byType(GridView),
    matching: find.byType(Image),
  );
  expect(finder, findsOneWidget);
  final provider = tester.widget<Image>(finder).image;
  expect(provider, isA<AssetImage>());
  expect((provider as AssetImage).assetName, expected);
  expect(
    tester.widgetList<Image>(find.byType(Image)).map((image) => image.image),
    everyElement(isNot(isA<NetworkImage>())),
  );
  expect(tester.takeException(), isNull);
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  required bool sheet,
}) async {
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: fixture,
      child: MaterialApp(
        home: sheet
            ? Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 390,
                    height: 490,
                    child: GiftSheet(
                      balance: 1200,
                      account: 'contract-account',
                      targets: const [GiftTarget(userId: 20, name: 'Alice')],
                      onSend: (_) async => throw StateError('Must not send'),
                      onRechargeReturn: () async =>
                          throw StateError('Must not recharge'),
                    ),
                  ),
                ),
              )
            : const GiftCatalogPage(),
      ),
    ),
  );
  // Complete real HTTP stream cancellation as well as fake-clock UI frames.
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text('目录测试礼物').evaluate().isNotEmpty) return;
  }
  fail('Catalog did not render');
}

class _Fixture extends Fake implements AppDependencies {
  _Fixture(String? assetKey) {
    http = MediaFakeHttp((request) {
      expect(request.method, 'GET');
      expect(request.uri.path, const BackendRouteCatalog().normalGiftCatalog);
      return MediaFakeResponse.json({
        'list': [
          {
            'giftId': '00000000-0000-0000-0000-000000000778',
            'giftName': '目录测试礼物',
            'category': 'POPULAR',
            'unitCostGiftCoin': 10,
            'price': 10,
            'assetKey': assetKey,
          },
        ],
        'total': 1,
        'retiredCategoriesPresent': false,
        'providerInvocation': false,
      });
    });
    commerceCatalogRepository = BackendCommerceCatalogRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('https://configured.backend.test'),
        clientType: 'test',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer contract-test',
        httpClient: http,
      ),
      routes: const BackendRouteCatalog(),
    );
  }

  late final MediaFakeHttp http;
  @override
  late final BackendCommerceCatalogRepository commerceCatalogRepository;
  @override
  final commerceRepository = MockCommerceRepository();

  void expectOnlyCatalogRead() {
    expect(http.requests, hasLength(1));
    expect(http.requests.single.method, 'GET');
    expect(http.requests.single.uri.host, 'configured.backend.test');
  }
}
