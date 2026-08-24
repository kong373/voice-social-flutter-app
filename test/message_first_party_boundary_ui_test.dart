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
  testWidgets('first-party stored chat never claims realtime online', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: AppEnvironment.mock(),
      messageRepository: _StoredOnlyMessageRepository(),
    );
    final ConversationSummary conversation = ConversationSummary(
      id: 'conversation-10002',
      kind: ConversationKind.privateChat,
      title: '晚风',
      lastMessage: '',
      updatedAt: DateTime(2026, 8, 22),
      unreadCount: 0,
      targetUserId: 10002,
    );

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: PrivateChatPage(conversation: conversation),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('服务端留存'), findsOneWidget);
    expect(find.text('实时在线'), findsNothing);
    expect(find.textContaining('VENDOR_BLOCKED'), findsOneWidget);
    expect(find.text('输入消息（服务端留存）…'), findsOneWidget);
  });

  testWidgets(
    'a stale history load cannot erase a message sent while loading',
    (WidgetTester tester) async {
      final _DelayedHistoryMessageRepository repository =
          _DelayedHistoryMessageRepository();
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment.mock(),
        messageRepository: repository,
      );
      final ConversationSummary conversation = ConversationSummary(
        id: 'conversation-10002',
        kind: ConversationKind.privateChat,
        title: '晚风',
        lastMessage: '',
        updatedAt: DateTime(2026, 8, 22),
        unreadCount: 0,
        targetUserId: 10002,
      );

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: PrivateChatPage(conversation: conversation),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '发送后不应丢失');
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pump();
      expect(repository.sendCount, 1);

      repository.history.complete(const <ChatMessage>[]);
      await tester.pump();

      expect(find.text('server-sent-message'), findsOneWidget);
      expect(repository.sendCount, 1);
    },
  );
}

class _StoredOnlyMessageRepository extends MockMessageRepository {
  @override
  bool get supportsPrivateRealtime => false;

  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async {
    return <ChatMessage>[
      ChatMessage(
        id: 'server-message-1',
        conversationId: conversation.id,
        senderUserId: 10001,
        senderName: '我',
        content: '已写入第一方存储',
        createdAt: DateTime(2026, 8, 22, 10),
        isMine: true,
        status: ChatMessageStatus.storedPendingDelivery,
      ),
    ];
  }
}

class _DelayedHistoryMessageRepository extends MockMessageRepository {
  final Completer<List<ChatMessage>> history = Completer<List<ChatMessage>>();
  int sendCount = 0;

  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) {
    return history.future;
  }

  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
    String? requestId,
  }) async {
    sendCount += 1;
    return ChatMessage(
      id: 'server-sent-message',
      conversationId: conversation.id,
      senderUserId: 10001,
      senderName: '我',
      content: 'server-sent-message',
      createdAt: DateTime(2026, 8, 22, 10),
      isMine: true,
      status: ChatMessageStatus.sent,
    );
  }
}
