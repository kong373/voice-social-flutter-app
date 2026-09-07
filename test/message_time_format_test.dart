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
  testWidgets('message center uses the device-local time for UTC timestamps', (
    WidgetTester tester,
  ) async {
    final DateTime createdAt = _localDateTime(2026, 9, 6, 9, 55);
    final AppDependencies dependencies = _dependencies(
      now: _localDateTime(2026, 9, 6, 9, 58),
      repository: _MessageTimeRepository(
        conversationUpdatedAt: createdAt,
        messages: <ChatMessage>[_message(createdAt)],
      ),
    );

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const MessageCenterPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('09:55'), findsOneWidget);
  });

  testWidgets('private chat uses the device-local time for UTC timestamps', (
    WidgetTester tester,
  ) async {
    final DateTime createdAt = _localDateTime(2026, 9, 6, 9, 55);
    final ConversationSummary conversation = _conversation(
      updatedAt: createdAt,
    );
    final AppDependencies dependencies = _dependencies(
      now: _localDateTime(2026, 9, 6, 9, 58),
      repository: _MessageTimeRepository(
        conversationUpdatedAt: createdAt,
        messages: <ChatMessage>[_message(createdAt)],
      ),
    );

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: PrivateChatPage(conversation: conversation),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('09:55'), findsOneWidget);
  });

  testWidgets('message time uses local calendar boundaries', (
    WidgetTester tester,
  ) async {
    final ConversationSummary conversation = _conversation(
      updatedAt: _localDateTime(2026, 9, 6, 9, 58),
    );
    final AppDependencies dependencies = _dependencies(
      now: _localDateTime(2026, 9, 6, 9, 58),
      repository: _MessageTimeRepository(
        conversationUpdatedAt: conversation.updatedAt!,
        messages: <ChatMessage>[
          _message(_localDateTime(2026, 9, 5, 23, 55), id: 'yesterday'),
          _message(_localDateTime(2026, 9, 4, 12), id: 'same-year'),
          _message(_localDateTime(2025, 12, 31, 23, 55), id: 'cross-year'),
        ],
      ),
    );

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: PrivateChatPage(conversation: conversation),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('9月5日'), findsOneWidget);
    expect(find.text('9月4日'), findsOneWidget);
    expect(find.text('12月31日'), findsOneWidget);
  });
}

AppDependencies _dependencies({
  required DateTime now,
  required MockMessageRepository repository,
}) => AppDependencies.forTestEnvironment(
  environment: AppEnvironment.mock(),
  mockNow: now,
  messageRepository: repository,
);

DateTime _localDateTime(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
]) => DateTime(year, month, day, hour, minute).toUtc();

ConversationSummary _conversation({required DateTime updatedAt}) =>
    ConversationSummary(
      id: 'conversation-time-test',
      kind: ConversationKind.privateChat,
      title: '时间测试',
      lastMessage: '消息时间测试',
      updatedAt: updatedAt,
      unreadCount: 0,
      targetUserId: 20001,
    );

ChatMessage _message(DateTime createdAt, {String id = 'message-time-test'}) =>
    ChatMessage(
      id: id,
      conversationId: 'conversation-time-test',
      senderUserId: 20001,
      senderName: '测试用户',
      content: '消息时间测试 $id',
      createdAt: createdAt,
      isMine: false,
      status: ChatMessageStatus.received,
    );

class _MessageTimeRepository extends MockMessageRepository {
  _MessageTimeRepository({
    required this.conversationUpdatedAt,
    required this.messages,
  });

  final DateTime conversationUpdatedAt;
  final List<ChatMessage> messages;

  @override
  Future<List<ConversationSummary>> fetchConversations() async =>
      <ConversationSummary>[_conversation(updatedAt: conversationUpdatedAt)];

  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async => messages;
}
