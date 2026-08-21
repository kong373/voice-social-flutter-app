import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_status_pages.dart';
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';

void main() {
  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> pumpScoped(
    WidgetTester tester,
    AppDependencies dependencies,
    Widget page,
  ) async {
    await disposePage(tester);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.social(),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void usePhoneViewport(WidgetTester tester) {
    tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('account level-two and level-three actions complete', (
    WidgetTester tester,
  ) async {
    usePhoneViewport(tester);
    final AppDependencies dependencies = await createQaDependencies();

    await pumpScoped(
      tester,
      dependencies,
      const SystemPermissionCenterPage(
        account: '13800138000',
        currentVersion: 5,
        platformType: 1,
      ),
    );
    expect(find.text('尚未请求'), findsOneWidget);
    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();
    expect(find.text('尚未请求'), findsNothing);
    expect(find.text('已允许'), findsNWidgets(2));

    await pumpScoped(
      tester,
      dependencies,
      const RealNamePage(
        account: '13800138000',
        currentVersion: 5,
        platformType: 1,
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), '测试用户');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      '420106199001011234',
    );
    await tester.tap(find.text('提交认证'));
    await tester.pumpAndSettle();
    expect(find.text('已认证'), findsOneWidget);

    await pumpScoped(
      tester,
      dependencies,
      const AccountAppealPage(account: '13800138000'),
    );
    await tester.enterText(find.byType(TextField), '这是用于验证完整申诉提交交互的测试说明。');
    await tester.tap(find.text('提交申诉'));
    await tester.pumpAndSettle();
    expect(find.text('申诉审核中'), findsOneWidget);

    await pumpScoped(
      tester,
      dependencies,
      const YouthModePage(
        account: '13800138000',
        currentVersion: 5,
        platformType: 1,
      ),
    );
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('开启青少年模式'));
    await tester.pumpAndSettle();
    expect(find.text('青少年模式已开启'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposePage(tester);
  });

  testWidgets('recharge selection reaches a server-authoritative result', (
    WidgetTester tester,
  ) async {
    usePhoneViewport(tester);
    final AppDependencies dependencies = await createQaDependencies();

    await pumpScoped(tester, dependencies, const RechargeCatalogPage());
    await tester.tap(find.text('300 礼物币').first);
    await tester.ensureVisible(find.text('选择支付方式'));
    await tester.tap(find.text('选择支付方式'));
    await tester.pumpAndSettle();
    expect(find.text('支付方式与提交'), findsOneWidget);
    expect(find.text('微信支付'), findsOneWidget);

    await tester.ensureVisible(find.text('提交充值订单'));
    await tester.tap(find.text('提交充值订单'));
    await tester.pumpAndSettle();
    expect(find.text('确认充值信息'), findsOneWidget);
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(find.text('支付返回与结果'), findsOneWidget);
    expect(find.text('服务端确认中'), findsOneWidget);
    expect(find.textContaining('会员'), findsNothing);
    expect(find.textContaining('礼物背包'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposePage(tester);
  });

  testWidgets('community guardian and daily check-in update visible state', (
    WidgetTester tester,
  ) async {
    usePhoneViewport(tester);
    final AppDependencies dependencies = await createQaDependencies();

    await pumpScoped(tester, dependencies, const GuardianFanPage());
    await tester.tap(find.text('开通').first);
    await tester.pumpAndSettle();
    expect(find.text('开通七日守护？'), findsOneWidget);
    await tester.tap(find.text('确认开通'));
    await tester.pumpAndSettle();
    expect(find.text('当前守护：七日守护'), findsOneWidget);

    await pumpScoped(tester, dependencies, const TaskCheckInPage());
    expect(find.text('连续签到 3 天'), findsOneWidget);
    await tester.tap(find.text('签到'));
    await tester.pumpAndSettle();
    expect(find.text('连续签到 4 天'), findsOneWidget);
    expect(find.text('已签到'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposePage(tester);
  });

  testWidgets('ordinary room PK invitation completes from opponent selection', (
    WidgetTester tester,
  ) async {
    usePhoneViewport(tester);
    final AppDependencies dependencies = await createQaDependencies();

    await pumpScoped(
      tester,
      dependencies,
      const RoomPkPreparationPage(roomId: '880217', roomTitle: '深夜温柔陪伴'),
    );
    await tester.ensureVisible(find.text('安静音乐电台'));
    await tester.tap(find.text('安静音乐电台'));
    final Finder sendButton = find.text('发送 PK 邀请');
    await tester.scrollUntilVisible(
      sendButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(find.text('PK 邀请已发送，等待对方确认'), findsOneWidget);
    expect(find.text('已邀请 安静音乐电台'), findsOneWidget);
    expect(find.textContaining('会员'), findsNothing);
    expect(find.textContaining('礼物背包'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposePage(tester);
  });
}
