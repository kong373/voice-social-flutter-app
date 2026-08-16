import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

import 'm2_4_test_support.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'seeded QA detail pages use their authoritative repository instances',
    (WidgetTester tester) async {
      final AppDependencies dependencies = await createQaDependencies();

      await _pumpAuthorityPage(
        tester,
        dependencies,
        SupportTicketPage(initialTicket: qaSupportTicket(dependencies)),
      );
      expect(find.text('工单详情与处理进度'), findsOneWidget);
      await tester.tap(find.byType(IconButton).last);
      await tester.pumpAndSettle();
      expect(find.text('处理中'), findsOneWidget);
      expect(find.textContaining('不存在'), findsNothing);
      await captureQaScreenshot(
        tester,
        binding,
        'P1-M24-EMU-009-US-010-authoritative-ticket-$qaAvdId',
      );

      await _pumpAuthorityPage(
        tester,
        dependencies,
        PaymentResultPage(
          order: qaRechargeOrder(dependencies, succeeded: false),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('支付返回与结果'), findsOneWidget);
      expect(find.textContaining('充值订单不存在'), findsNothing);
      final Finder rechargeRefresh = find.text('刷新订单状态');
      if (rechargeRefresh.evaluate().isNotEmpty) {
        await tester.tap(rechargeRefresh);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('充值订单不存在'), findsNothing);
      await captureQaScreenshot(
        tester,
        binding,
        'P1-M24-EMU-009-CM-004-authoritative-recharge-$qaAvdId',
      );

      await _pumpAuthorityPage(
        tester,
        dependencies,
        OrderDetailPage(order: qaPaymentOrder(dependencies)),
      );
      await tester.tap(find.text('刷新并补单核验'));
      await tester.pumpAndSettle();
      expect(find.textContaining('订单不存在'), findsNothing);
      expect(find.text('QA-ORDER-001'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'P1-M24-EMU-009-CM-006-authoritative-order-$qaAvdId',
      );

      await _pumpAuthorityPage(
        tester,
        dependencies,
        RefundResultPage(
          application: qaRefundApplication(dependencies),
        ),
      );
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.textContaining('退款申请不存在'), findsNothing);
      expect(find.text('QA-REFUND-001'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'P1-M24-EMU-009-CM-008-authoritative-refund-$qaAvdId',
      );

      await _pumpAuthorityPage(
        tester,
        dependencies,
        RoomPkBattlePage(
          roomId: '880217',
          initialBattle: qaRoomPkBattle(dependencies, completed: false),
        ),
      );
      await tester.tap(find.byTooltip('刷新比分'));
      await tester.pumpAndSettle();
      expect(find.textContaining('PK 对战不存在'), findsNothing);
      expect(find.text('PK 对战与结算'), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'P1-M24-EMU-009-RM-014-authoritative-pk-$qaAvdId',
      );

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _pumpAuthorityPage(
  WidgetTester tester,
  AppDependencies dependencies,
  Widget page,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(theme: AppTheme.dark(), home: page),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull);
}
