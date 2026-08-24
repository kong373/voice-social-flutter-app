import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';

void main() {
  testWidgets(
    'order notification preserves targetId and opens the matching order detail',
    (WidgetTester tester) async {
      const String orderNo = 'MOCK202608150002';
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment.mock(),
        messageRepository: _OrderNotificationMessageRepository(
          notification: _orderNotification(orderNo),
        ),
      );

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: const NotificationDetailPage(
              notificationId: 'notification-order',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('查看相关内容'));
      await tester.pumpAndSettle();

      expect(find.byType(OrdersPage, skipOffstage: false), findsOneWidget);
      expect(find.byType(OrderDetailPage), findsOneWidget);
      expect(find.text(orderNo), findsOneWidget);
      expect(find.text('订单列表'), findsNothing);
    },
  );

  testWidgets(
    'missing order notification target stays in an explicit error state',
    (WidgetTester tester) async {
      const String orderNo = 'ORDER-TARGET-MISSING-42';
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment.mock(),
        messageRepository: _OrderNotificationMessageRepository(
          notification: _orderNotification(orderNo),
        ),
      );

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: const NotificationDetailPage(
              notificationId: 'notification-order',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('查看相关内容'));
      await tester.pumpAndSettle();

      expect(find.byType(OrdersPage), findsOneWidget);
      expect(find.byType(OrderDetailPage), findsNothing);
      expect(find.textContaining(orderNo), findsOneWidget);
    },
  );
}

AppNotification _orderNotification(String orderNo) => AppNotification(
  id: 'notification-order',
  category: NotificationCategory.system,
  title: '订单状态更新',
  summary: '订单状态发生变化。',
  createdAt: DateTime(2026, 8, 25, 10),
  unread: true,
  targetType: NotificationTargetType.order,
  targetId: orderNo,
);

class _OrderNotificationMessageRepository extends MockMessageRepository {
  _OrderNotificationMessageRepository({required this.notification});

  final AppNotification notification;

  @override
  Future<AppNotification> fetchNotification(String notificationId) async =>
      notification;

  @override
  Future<void> markNotificationRead(String notificationId) async {}
}
