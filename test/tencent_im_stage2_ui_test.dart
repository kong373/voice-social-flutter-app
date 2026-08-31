import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/im/domain/im_authoritative_refresh_bus.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';

void main() {
  testWidgets('trusted hint refreshes visible private-chat content once', (
    WidgetTester tester,
  ) async {
    final ImAuthoritativeRefreshBus bus = ImAuthoritativeRefreshBus();
    final _VisibleRefreshRepository repository = _VisibleRefreshRepository();
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      messageRepository: repository,
      imAuthoritativeRefreshBus: bus,
    );
    addTearDown(() {
      bus.dispose();
      dependencies.imSessionCoordinator.dispose();
    });

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: PrivateChatPage(conversation: _conversation()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('before-hint'), findsOneWidget);
    expect(repository.historyCalls, 1);

    final ImRefreshHint hint = ImRefreshHint(
      messageId: 'message-1',
      eventVersion: 1,
    );
    final ImRefreshDispatchResult first = await bus.publish(hint);
    await tester.pumpAndSettle();
    expect(first.status, ImRefreshDispatchStatus.delivered);
    expect(find.text('after-hint'), findsOneWidget);
    expect(repository.historyCalls, 2);

    final ImRefreshDispatchResult duplicate = await bus.publish(hint);
    await tester.pumpAndSettle();
    expect(duplicate.status, ImRefreshDispatchStatus.duplicate);
    expect(repository.historyCalls, 2);

    repository.failNext = true;
    final ImRefreshDispatchResult failed = await bus.publish(
      const ImRefreshHint(messageId: 'message-2', eventVersion: 2),
    );
    await tester.pumpAndSettle();
    // The page handler catches a failed HTTP refresh and preserves the last
    // authoritative snapshot instead of showing provider content or a blank
    // loading state.
    expect(failed.status, ImRefreshDispatchStatus.delivered);
    expect(find.text('after-hint'), findsOneWidget);
    expect(find.textContaining('消息加载失败'), findsNothing);
  });
}

ConversationSummary _conversation() => ConversationSummary(
  id: 'conversation-1',
  kind: ConversationKind.privateChat,
  title: '晚风',
  lastMessage: '',
  updatedAt: DateTime.utc(2030, 1, 1, 12),
  unreadCount: 0,
  targetUserId: 123,
);

class _VisibleRefreshRepository extends MockMessageRepository {
  int historyCalls = 0;
  bool failNext = false;

  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async {
    historyCalls += 1;
    if (failNext) {
      failNext = false;
      throw StateError('refresh unavailable');
    }
    final String content = historyCalls == 1 ? 'before-hint' : 'after-hint';
    return <ChatMessage>[
      ChatMessage(
        id: 'message-1',
        conversationId: conversation.id,
        senderUserId: 123,
        senderName: '我',
        content: content,
        createdAt: DateTime.utc(2030, 1, 1, 12),
        isMine: true,
        status: ChatMessageStatus.sent,
        deliveryStatus: MessageDeliveryStatus.delivered,
      ),
    ];
  }
}
