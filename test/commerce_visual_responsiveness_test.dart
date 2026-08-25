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
  _CommerceTestPage(
    'CM-007',
    (_) => const RefundListPage(account: '13800138000'),
  ),
  _CommerceTestPage(
    'CM-008',
    (_) => const RefundApplicationPage(account: '13800138000'),
  ),
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
