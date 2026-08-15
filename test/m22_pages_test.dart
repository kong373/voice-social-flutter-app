import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_compliance_pages.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  Future<void> pumpScoped(
    WidgetTester tester,
    Widget page,
    AppDependencies dependencies,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(theme: AppTheme.dark(), home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AC-005 through AC-012 are reachable from account hub', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock();
    await pumpScoped(
      tester,
      const AccountComplianceHubPage(
        account: '13800138000',
        currentVersion: 3,
        platformType: 1,
      ),
      dependencies,
    );

    expect(find.text('系统权限中心'), findsOneWidget);
    expect(find.text('实名认证'), findsOneWidget);
    expect(find.text('登录设备与会话'), findsOneWidget);
    expect(find.text('处罚申诉'), findsOneWidget);
    expect(find.text('账号注销'), findsOneWidget);
    expect(find.text('版本升级'), findsOneWidget);
    expect(find.text('青少年模式'), findsOneWidget);
  });

  testWidgets('US personal center exposes social, support, and account routes', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock();
    await pumpScoped(
      tester,
      PersonalCenterPage(
        session: null,
        onSignOut: () async {},
      ),
      dependencies,
    );

    expect(find.text('编辑个人资料'), findsOneWidget);
    expect(find.text('关注、粉丝与好友'), findsOneWidget);
    expect(find.text('好友请求'), findsOneWidget);
    expect(find.text('访客记录'), findsOneWidget);
    expect(find.text('隐私与黑名单'), findsOneWidget);
    expect(find.text('帮助与客服'), findsOneWidget);
    expect(find.text('钱包、订单与收益'), findsOneWidget);
  });

  testWidgets('CM hub exposes ledger, orders, account refund, earnings, and withdrawal', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock();
    await pumpScoped(
      tester,
      const CommerceHubPage(account: '13900139000'),
      dependencies,
    );

    expect(find.text('钱包与流水'), findsOneWidget);
    expect(find.text('充值订单'), findsOneWidget);
    expect(find.text('退款申请'), findsOneWidget);
    expect(find.text('主播收益'), findsOneWidget);

    final Finder withdrawalEntry = find.text('结算与提现');
    await tester.scrollUntilVisible(
      withdrawalEntry,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(withdrawalEntry, findsOneWidget);

    final Finder paymentBoundary =
        find.textContaining('微信支付、支付宝和 Apple IAP');
    await tester.scrollUntilVisible(
      paymentBoundary,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(paymentBoundary, findsOneWidget);
  });
}
