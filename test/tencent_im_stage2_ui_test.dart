import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/im/domain/im_authoritative_refresh_bus.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';

void main() {
  for (final ending in <String>['success', 'error', 'logout', 'dispose']) {
    testWidgets('message center drains pending hint after $ending', (
      tester,
    ) async {
      final bus = ImAuthoritativeRefreshBus();
      final repository = _DeferredConversationsRepository();
      final dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment.mock(),
        messageRepository: repository,
        imAuthoritativeRefreshBus: bus,
      );
      await dependencies.sessionManager.save(
        AuthSession(
          accessToken: 'test-only-access',
          tokenType: 'Bearer',
          expiresAt: DateTime.utc(2030),
          userId: 1,
          mobile: '',
          roles: '',
        ),
      );
      addTearDown(() {
        bus.dispose();
        dependencies.imSessionCoordinator.dispose();
      });
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
      expect(repository.calls, 1);
      final first = bus.publish(
        const ImRefreshHint(messageId: 'message-1', eventVersion: 1),
      );
      await tester.pump();
      expect(repository.calls, 2);
      final second = bus.publish(
        const ImRefreshHint(messageId: 'message-2', eventVersion: 2),
      );
      final third = bus.publish(
        const ImRefreshHint(messageId: 'message-3', eventVersion: 3),
      );
      await tester.pump();
      expect(
        repository.calls,
        2,
        reason: 'Hints must not start concurrent HTTP reads',
      );
      if (ending == 'logout') await dependencies.sessionManager.clear();
      if (ending == 'dispose') await tester.pumpWidget(const SizedBox.shrink());
      if (ending == 'error') {
        repository.pending.completeError(StateError('test-only unavailable'));
      } else {
        repository.pending.complete([
          _conversation().copyWith(lastMessage: 'snapshot-one', unreadCount: 1),
        ]);
      }
      await tester.pumpAndSettle();
      await Future.wait([first, second, third]);
      if (ending == 'success' || ending == 'error') {
        expect(
          repository.calls,
          3,
          reason: 'New hints during a read require exactly one trailing read',
        );
        expect(find.text('snapshot-three'), findsOneWidget);
        expect(find.text('snapshot-one'), findsNothing);
        final duplicate = await bus.publish(
          const ImRefreshHint(messageId: 'message-3', eventVersion: 3),
        );
        expect(duplicate.status, ImRefreshDispatchStatus.duplicate);
        expect(repository.calls, 3);
      } else {
        expect(
          repository.calls,
          2,
          reason: 'Old identity/page must not issue a trailing read',
        );
        expect(find.text('snapshot-one'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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

class _DeferredConversationsRepository extends MockMessageRepository {
  int calls = 0;
  final pending = Completer<List<ConversationSummary>>();

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    calls++;
    if (calls == 2) return pending.future;
    return [
      _conversation().copyWith(
        lastMessage: calls == 1 ? 'initial' : 'snapshot-three',
        unreadCount: calls == 1 ? 0 : 3,
      ),
    ];
  }
}
