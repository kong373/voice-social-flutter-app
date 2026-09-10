import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

void main() {
  const List<_Viewport> viewports = <_Viewport>[
    _Viewport('390x844', Size(390, 844), 1),
    _Viewport('360x800', Size(360, 800), 1),
    _Viewport('360x800 at 1.3x', Size(360, 800), 1.3),
    _Viewport('390x844 at 1.3x', Size(390, 844), 1.3),
  ];
  for (final _Viewport viewport in viewports) {
    for (final _CommerceTestPage entry in _commercePages) {
      testWidgets('${entry.id} fits ${viewport.label}', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = viewport.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final AppDependencies dependencies = await createQaDependencies();
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.social(),
              builder: (BuildContext context, Widget? child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(viewport.textScale)),
                child: child!,
              ),
              home: entry.builder(dependencies),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: entry.id);
      });
    }
  }

  testWidgets('CM-002 large text keeps every amount visible and selectable', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final AppDependencies dependencies = await createQaDependencies();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const RechargeCatalogPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final price in [6, 30, 68, 198, 648]) {
      final coins = find.text('${price * 10} 礼物币');
      final amount = find.text('¥$price');
      await tester.ensureVisible(coins);
      await tester.pumpAndSettle();
      final card = find
          .ancestor(of: coins, matching: find.byType(InkWell))
          .first;
      final bounds = tester.getRect(card).inflate(0.01);
      for (final field in [coins, amount]) {
        expect(field, findsOneWidget);
        final rect = tester.getRect(field);
        expect(bounds.contains(rect.topLeft), isTrue);
        expect(bounds.contains(rect.bottomRight), isTrue);
      }
      await tester.tap(coins);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.text('选择支付方式'));
    await tester.tap(find.text('选择支付方式'));
    await tester.pumpAndSettle();
    final submission = tester.widget<PaymentSubmissionPage>(
      find.byType(PaymentSubmissionPage),
    );
    expect(submission.product.id, 'recharge-648');
    expect(submission.product.priceCny, 648);
    expect(submission.product.totalGiftCoins, 6480);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    dependencies.dispose();
  });
}

final List<_CommerceTestPage> _commercePages = <_CommerceTestPage>[
  _CommerceTestPage('CM-001', (_) => const WalletPage()),
  _CommerceTestPage('CM-002', (_) => const RechargeCatalogPage()),
  _CommerceTestPage(
    'CM-003',
    (_) => const PaymentSubmissionPage(
      product: qaRechargeProduct,
      platform: ClientStorePlatform.android,
      youthModeEnabled: false,
    ),
  ),
  _CommerceTestPage(
    'CM-004',
    (AppDependencies dependencies) => PaymentResultPage(
      order: qaRechargeOrder(dependencies, succeeded: false),
    ),
  ),
  _CommerceTestPage('CM-005', (_) => const OrdersPage()),
  _CommerceTestPage(
    'CM-006',
    (AppDependencies dependencies) =>
        OrderDetailPage(order: qaPaymentOrder(dependencies)),
  ),
  // CM-007/CM-008: REMOVED_BY_PRODUCT Q15-06, not rendered or counted.
  _CommerceTestPage('CM-009', (_) => const GiftCatalogPage()),
  _CommerceTestPage('CM-010', (_) => const DecorationPage()),
  _CommerceTestPage('CM-011', (_) => const EarningsPage()),
  _CommerceTestPage('CM-012', (_) => const WithdrawalPage()),
];

class _CommerceTestPage {
  const _CommerceTestPage(this.id, this.builder);

  final String id;
  final Widget Function(AppDependencies dependencies) builder;
}

class _Viewport {
  const _Viewport(this.label, this.size, this.textScale);

  final String label;
  final Size size;
  final double textScale;
}
