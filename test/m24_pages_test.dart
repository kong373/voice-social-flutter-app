import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';

void main() {
  Future<void> disposeScoped(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> pumpScoped(
    WidgetTester tester,
    AppDependencies dependencies,
    Widget page,
  ) async {
    // Force disposal of the previous navigator and all page-owned timers
    // before mounting the next fixture.
    await disposeScoped(tester);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.dark(),
          home: page,
        ),
      ),
    );
    // Use bounded frames instead of pumpAndSettle. Some production pages own
    // periodic polling while a PK is active; tests must never wait for that
    // timer to become permanently idle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('RM-013 and RM-014 expose ordinary room PK states', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await pumpScoped(
      tester,
      dependencies,
      const RoomPkPreparationPage(
        roomId: 'room-880217',
        roomTitle: '深夜温柔陪伴',
      ),
    );
    expect(find.text('PK 邀请与准备'), findsOneWidget);
    expect(find.text('选择对手'), findsOneWidget);
    expect(find.textContaining('不会加入随机匹配'), findsOneWidget);
    final Finder sendButton = find.text('发送 PK 邀请');
    await tester.scrollUntilVisible(
      sendButton,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(sendButton, findsOneWidget);

    final RoomPkBattle completed = RoomPkBattle(
      id: 'battle-widget',
      currentRoomId: 'room-880217',
      sender: const RoomPkSide(
        roomId: 'room-880217',
        roomCode: '880217',
        roomName: '深夜温柔陪伴',
        score: 3680,
      ),
      receiver: const RoomPkSide(
        roomId: 'room-660318',
        roomCode: '660318',
        roomName: '下班后的松弛时刻',
        score: 2940,
      ),
      remainingSeconds: 0,
      punishmentTheme: '分享今天最开心的事',
      stage: RoomPkBattleStage.completed,
      result: RoomPkResult.win,
      updatedAt: DateTime(2026, 8, 15),
    );
    await pumpScoped(
      tester,
      dependencies,
      RoomPkBattlePage(
        roomId: 'room-880217',
        initialBattle: completed,
      ),
    );
    expect(find.text('PK 对战与结算'), findsOneWidget);
    expect(find.text('本房获胜'), findsOneWidget);
    expect(find.text('3680 : 2940'), findsOneWidget);
    expect(find.text('返回房间'), findsOneWidget);
    await disposeScoped(tester);
  });

  testWidgets('CM-002 through CM-004 enforce platform channels and authority', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await pumpScoped(tester, dependencies, const RechargeCatalogPage());
    expect(find.text('充值商品目录'), findsOneWidget);
    expect(find.text('60 礼物币'), findsOneWidget);

    const RechargeProduct product = RechargeProduct(
      id: 'widget-product',
      giftCoins: 300,
      priceCny: 30,
    );
    await pumpScoped(
      tester,
      dependencies,
      const PaymentSubmissionPage(
        product: product,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      ),
    );
    expect(find.text('微信支付'), findsOneWidget);
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('Apple IAP'), findsNothing);

    await pumpScoped(
      tester,
      dependencies,
      const PaymentSubmissionPage(
        product: product,
        platform: ClientStorePlatform.ios,
        youthModeEnabled: false,
      ),
    );
    expect(find.text('Apple IAP'), findsOneWidget);
    expect(find.text('微信支付'), findsNothing);

    final RechargeOrder? order =
        await tester.runAsync<RechargeOrder>(() async {
      RechargeOrder value = await dependencies.commerceCatalogRepository
          .createRechargeOrder(
        account: '13800138000',
        product: product,
        channel: PaymentChannelType.wechat,
        platform: ClientStorePlatform.android,
        youthModeEnabled: false,
      );
      value =
          await dependencies.commerceCatalogRepository.invokePayment(value);
      return value;
    });
    expect(order, isNotNull);

    await pumpScoped(
      tester,
      dependencies,
      PaymentResultPage(order: order!),
    );
    expect(find.text('支付返回与结果'), findsOneWidget);
    expect(find.text('服务端确认中'), findsOneWidget);
    expect(find.text('刷新订单状态'), findsOneWidget);
    await disposeScoped(tester);
  });

  testWidgets('CM-009 and CM-010 expose only ordinary assets', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await pumpScoped(tester, dependencies, const GiftCatalogPage());
    expect(find.text('礼物目录与赠送面板'), findsOneWidget);
    expect(find.text('星光'), findsWidgets);
    expect(find.text('红包'), findsNothing);
    expect(find.text('盲盒'), findsNothing);

    await pumpScoped(tester, dependencies, const MembershipBackpackPage());
    expect(find.text('会员装扮与背包'), findsOneWidget);
    expect(find.text('装扮'), findsOneWidget);
    expect(find.text('背包'), findsOneWidget);
    await disposeScoped(tester);
  });

  testWidgets('MS-001 through MS-006 preserve honest messaging boundaries', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await pumpScoped(tester, dependencies, const MessageCenterPage());
    expect(find.text('晚星'), findsOneWidget);
    expect(find.byTooltip('系统与互动通知'), findsOneWidget);
    expect(find.byTooltip('通知权限与消息恢复'), findsOneWidget);

    final ConversationSummary? conversation =
        await tester.runAsync<ConversationSummary>(() async {
      final List<ConversationSummary> conversations =
          await dependencies.messageRepository.fetchConversations();
      return conversations
          .firstWhere((ConversationSummary item) => item.available);
    });
    expect(conversation, isNotNull);

    await pumpScoped(
      tester,
      dependencies,
      PrivateChatPage(conversation: conversation!),
    );
    expect(find.text('今晚房间的话题很温柔。'), findsOneWidget);
    expect(find.byTooltip('发送消息'), findsOneWidget);

    await pumpScoped(tester, dependencies, const NotificationCenterPage());
    expect(find.text('账号安全提醒'), findsOneWidget);

    await pumpScoped(
      tester,
      dependencies,
      const NotificationDetailPage(
        notificationId: 'notification-room-1',
      ),
    );
    expect(find.text('收藏房间正在进行'), findsOneWidget);
    expect(find.text('查看相关内容'), findsOneWidget);

    await pumpScoped(
      tester,
      dependencies,
      const NotificationTargetUnavailablePage(
        reason: '动态已删除或不可见',
      ),
    );
    expect(find.text('动态已删除或不可见'), findsOneWidget);

    await pumpScoped(
      tester,
      dependencies,
      const MessagePermissionRecoveryPage(),
    );
    expect(find.text('私聊实时通道'), findsOneWidget);
    expect(find.textContaining('不会编造断线期间私聊'), findsOneWidget);
    await disposeScoped(tester);
  });
}
