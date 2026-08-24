import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';

void main() {
  testWidgets('notification category switch ignores stale refresh results', (
    WidgetTester tester,
  ) async {
    final _RaceMessageRepository repository = _RaceMessageRepository();
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      messageRepository: repository,
    );

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const NotificationCenterPage(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('互动通知'));
    await tester.pump();

    repository.interaction.complete(<AppNotification>[
      _notification('fresh-interaction', NotificationCategory.interaction),
    ]);
    await tester.pump();
    expect(find.text('fresh-interaction'), findsWidgets);

    repository.system.complete(<AppNotification>[
      _notification('stale-system', NotificationCategory.system),
    ]);
    await tester.pump();
    expect(find.text('stale-system'), findsNothing);
    expect(find.text('fresh-interaction'), findsWidgets);
  });
}

AppNotification _notification(String id, NotificationCategory category) {
  return AppNotification(
    id: id,
    category: category,
    title: id,
    summary: id,
    createdAt: DateTime(2026, 8, 22),
    unread: true,
    targetType: NotificationTargetType.none,
  );
}

class _RaceMessageRepository extends MockMessageRepository {
  final Completer<List<AppNotification>> system =
      Completer<List<AppNotification>>();
  final Completer<List<AppNotification>> interaction =
      Completer<List<AppNotification>>();

  @override
  Future<List<AppNotification>> fetchNotifications(
    NotificationCategory category,
  ) {
    return category == NotificationCategory.system
        ? system.future
        : interaction.future;
  }
}
