import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/commerce/catalog/data/mock_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

void main() {
  testWidgets(
    'WALLET-01 Alipay result returns to catalog and refreshes wallet balance',
    (WidgetTester tester) async {
      final AppDependencies dependencies = AppDependencies.mock();
      addTearDown(dependencies.dispose);
      final MockCommerceRepository wallet =
          dependencies.commerceRepository as MockCommerceRepository;
      expect(
        dependencies.commerceCatalogRepository,
        isA<MockCommerceCatalogRepository>(),
      );
      final String before = (await wallet.fetchWalletSummary()).giftCoinText;
      final _RouteProbe routes = _RouteProbe();

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            navigatorObservers: <NavigatorObserver>[routes],
            home: const CommerceHubPage(account: '13800138000'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(before), findsOneWidget);

      await tester.tap(find.text('充值'));
      await tester.pumpAndSettle();
      expect(find.text('充值商品目录'), findsOneWidget);
      expect(find.text(before), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('选择支付方式'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('选择支付方式'));
      await tester.pumpAndSettle();
      expect(find.text('支付方式与提交'), findsOneWidget);
      await tester.tap(find.text('支付宝'));
      await tester.pump();
      await tester.tap(find.text('提交充值订单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();

      expect(find.text('支付返回与结果'), findsOneWidget);
      expect(find.text('服务端确认中'), findsOneWidget);
      await tester.tap(find.text('刷新订单状态'));
      await tester.pumpAndSettle();
      expect(find.text('充值成功'), findsOneWidget);

      final String after = (await wallet.fetchWalletSummary()).giftCoinText;
      expect(after, '2360');
      expect(after, isNot(before));

      await tester.tap(find.text('返回钱包'));
      await tester.pumpAndSettle();

      expect(routes.pageReplacements, 0);
      expect(routes.pagePops, 2);
      expect(find.byType(PaymentResultPage), findsNothing);
      expect(find.byType(PaymentSubmissionPage), findsNothing);
      expect(find.text('充值商品目录'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(find.text('当前礼物币余额'), findsOneWidget);
      expect(find.text(after), findsOneWidget);
    },
  );
}

class _RouteProbe extends NavigatorObserver {
  int pageReplacements = 0;
  int pagePops = 0;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PageRoute<dynamic> || oldRoute is PageRoute<dynamic>) {
      pageReplacements++;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute<dynamic>) {
      pagePops++;
    }
  }
}
