import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

void main() {
  test(
    'QA page fixtures are queryable from their scoped mock repositories',
    () async {
      final AppDependencies dependencies = await createQaDependencies();

      final SupportTicket ticket = qaSupportTicket(dependencies);
      expect(
        identical(
          await dependencies.socialRepository.fetchSupportTicket(ticket.id),
          ticket,
        ),
        isTrue,
      );

      final RechargeOrder confirmingOrder = qaRechargeOrder(
        dependencies,
        succeeded: false,
      );
      expect(
        identical(
          await dependencies.commerceCatalogRepository.queryRechargeOrder(
            confirmingOrder,
          ),
          confirmingOrder,
        ),
        isTrue,
      );
      final RechargeOrder succeededOrder = qaRechargeOrder(
        dependencies,
        succeeded: true,
      );
      expect(
        identical(
          await dependencies.commerceCatalogRepository.queryRechargeOrder(
            succeededOrder,
          ),
          succeededOrder,
        ),
        isTrue,
      );

      final PaymentOrder paymentOrder = qaPaymentOrder(dependencies);
      final PaymentOrder refreshedPayment = await dependencies
          .commerceRepository
          .queryOrderStatus(paymentOrder);
      expect(refreshedPayment.orderNo, paymentOrder.orderNo);
      expect(refreshedPayment.status, PaymentOrderStatus.succeeded);

      final RefundApplication refund = qaRefundApplication(dependencies);
      expect(
        identical(
          await dependencies.commerceRepository.fetchRefundResult(refund.id),
          refund,
        ),
        isTrue,
      );

      final RoomPkBattle activeBattle = qaRoomPkBattle(
        dependencies,
        completed: false,
      );
      expect(
        identical(
          await dependencies.roomPkRepository.fetchActiveBattle(
            roomId: '880217',
          ),
          activeBattle,
        ),
        isTrue,
      );
      final RoomPkBattle completedBattle = qaRoomPkBattle(
        dependencies,
        completed: true,
      );
      expect(
        identical(
          await dependencies.roomPkRepository.fetchActiveBattle(
            roomId: '880217',
          ),
          completedBattle,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'ordinary owner RoomPage opens canonical incoming PK and active battle',
    (WidgetTester tester) async {
      final AppDependencies dependencies = await createQaDependencies();
      seedQaRoomEntryRole(dependencies, RoomRole.owner);
      await _pumpRoom(tester, dependencies);

      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('房间 PK'), findsOneWidget);

      await tester.tap(find.text('房间 PK'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomPkPreparationPage), findsOneWidget);
      expect(find.text('收到的邀请'), findsOneWidget);
      expect(find.text('接受并准备'), findsOneWidget);

      await tester.tap(find.text('接受并准备'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RoomPkBattlePage), findsOneWidget);
      expect(find.text('PK 对战与结算'), findsOneWidget);

      await tester.ensureVisible(find.text('返回房间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('返回房间'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomPkBattlePage), findsNothing);
      expect(find.byType(RoomPkPreparationPage), findsNothing);
      expect(find.text('实时公屏'), findsOneWidget);

      final RoomPkBattle? battle = await tester.runAsync<RoomPkBattle?>(
        () => dependencies.roomPkRepository.fetchActiveBattle(roomId: '880217'),
      );
      expect(battle, isNotNull);
      expect(battle!.currentRoomId, '880217');
      await _disposePage(tester);
    },
  );

  testWidgets('ordinary RoomPage warns before leaving an active PK', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = await createQaDependencies();
    qaRoomPkBattle(dependencies, completed: false);
    await _pumpRoom(tester, dependencies);

    await tester.tap(find.byTooltip('离开房间'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('离开房间？'), findsOneWidget);
    expect(find.textContaining('当前房间正在 PK'), findsOneWidget);
    expect(find.textContaining('主动结束或认输'), findsOneWidget);
    await _disposePage(tester);
  });
}

Future<void> _pumpRoom(
  WidgetTester tester,
  AppDependencies dependencies,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const RoomPage(roomId: '880217', title: '深夜温柔陪伴'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
  expect(find.byTooltip('更多'), findsOneWidget);
}

Future<void> _disposePage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
