import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/domain/message_repository.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';

void main() {
  Future<AppDependencies> showChat(
    WidgetTester tester,
    _History repository, {
    GlobalKey<NavigatorState>? navigator,
  }) async {
    final dependencies = AppDependencies.forTestEnvironment(
      environment: const AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: 'http://127.0.0.1:28080/',
        clientType: 'test',
        clientInnerVersion: '1',
        oauthClientId: 'public-test-client',
        realtimeEndpoint: '',
        allowInsecureHttp: true,
      ),
      messageRepository: repository,
    );
    await dependencies.sessionManager.save(_session(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          navigatorKey: navigator,
          home: PrivateChatPage(
            conversation: ConversationSummary(
              id: 'conversation-2',
              kind: ConversationKind.privateChat,
              title: 'peer',
              lastMessage: '',
              updatedAt: DateTime(2026, 9, 7),
              unreadCount: 0,
              targetUserId: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      dependencies.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    return dependencies;
  }

  testWidgets('a peer message appears without leaving the open chat', (
    tester,
  ) async {
    final repository = _History();
    await showChat(tester, repository);
    repository.messages.add(_message('peer-1'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('peer-1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('peer-1'), findsOneWidget);
    expect(repository.calls, greaterThanOrEqualTo(3));
  });

  testWidgets(
    'HTTP fallback shows a delayed peer response within five seconds',
    (tester) async {
      final repository = _History();
      await showChat(tester, repository);
      repository.responseDelay = const Duration(milliseconds: 2800);
      repository.messages.add(_message('delayed-peer'));
      // Include the scheduling wait, response latency and widget updates in
      // the same user-visible deadline; no navigation or manual refresh.
      for (var tick = 0; tick < 50; tick++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final visibleByDeadline = find.text('delayed-peer').evaluate().isNotEmpty;
      repository.responseDelay = Duration.zero;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(visibleByDeadline, isTrue);
      expect(find.text('delayed-peer'), findsOneWidget);
    },
  );

  testWidgets(
    'a send receipt never advances the synchronized history boundary',
    (tester) async {
      final repository = _VisibleHistory()
        ..messages.add(_message('history-100'));
      await showChat(tester, repository);
      await tester.enterText(find.byType(TextField), 'own-receipt-251');
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pumpAndSettle();
      expect(find.text('own-receipt-251'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(repository.boundaries.last, {'history-100'});
    },
  );

  testWidgets(
    'a bounded sync retains its old boundary until continuation completes',
    (tester) async {
      final repository = _VisibleHistory()..messages.add(_message('history-1'));
      await showChat(tester, repository);
      repository.messages
        ..clear()
        ..add(_message('history-10002'));
      repository.nextCursor = '3';
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final continuationIndex = repository.boundaries.length;
      repository.messages
        ..clear()
        ..add(_message('history-2'));
      repository.nextCursor = null;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      // Assert the actual continuation request, not a later foreground poll
      // that may run after this batch has legitimately completed.
      expect(repository.boundaries.length, greaterThan(continuationIndex));
      expect(repository.boundaries[continuationIndex], {'history-1'});
      expect(repository.cursors[continuationIndex], '3');
      expect(find.text('history-2'), findsOneWidget);
      expect(find.text('history-10002'), findsOneWidget);
    },
  );

  testWidgets('a pending history request is never duplicated by the timer', (
    tester,
  ) async {
    final repository = _History();
    await showChat(tester, repository);
    repository.pending = Completer<List<ChatMessage>>();
    await tester.pump(const Duration(seconds: 3));
    final calls = repository.calls;
    await tester.pump(const Duration(seconds: 12));
    expect(repository.calls, calls);
    repository.pending!.complete([_message('slow-peer')]);
    repository.pending = null;
    await tester.pumpAndSettle();
    expect(find.text('slow-peer'), findsOneWidget);
  });

  testWidgets('background and covered routes do not poll or mark chats read', (
    tester,
  ) async {
    final repository = _History();
    final navigator = GlobalKey<NavigatorState>();
    await showChat(tester, repository, navigator: navigator);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    final initial = repository.calls;
    await tester.pump(const Duration(seconds: 10));
    expect(repository.calls, initial);
    repository.messages.add(_message('after-background'));
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('after-background'), findsOneWidget);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('other page')),
      ),
    );
    await tester.pumpAndSettle();
    final covered = repository.calls;
    await tester.pump(const Duration(seconds: 10));
    expect(repository.calls, covered);
    repository.messages.add(_message('after-return'));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('after-return'), findsOneWidget);
  });

  testWidgets(
    'background sync does not pull a reader away from older messages',
    (tester) async {
      final repository = _History();
      repository.messages.addAll(
        List.generate(40, (index) => _message('history-$index')),
      );
      await showChat(tester, repository);
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      final offset = controller.offset;
      repository.messages.add(_message('new-while-reading'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(offset, 1));
      // Same-account token persistence must not invalidate the chat.
      final scope = tester.widget<AppDependencyScope>(
        find.byType(AppDependencyScope),
      );
      await scope.dependencies.sessionManager.save(_session(1));
      await tester.pump();
      expect(find.text('登录状态已改变，请重新进入会话。'), findsNothing);
    },
  );

  testWidgets('transient sync failure preserves messages and retries', (
    tester,
  ) async {
    final repository = _History()..messages.add(_message('already-stored'));
    await showChat(tester, repository);
    repository.failNext = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('already-stored'), findsOneWidget);
    repository.messages.add(_message('recovered-peer'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('recovered-peer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account change rejects in-flight content and ends old chat sync',
    (tester) async {
      final repository = _History()..messages.add(_message('old-account'));
      final dependencies = await showChat(tester, repository);
      repository.pending = Completer<List<ChatMessage>>();
      await tester.pump(const Duration(seconds: 3));
      await dependencies.sessionManager.save(_session(3));
      await tester.pump();
      expect(find.text('old-account'), findsNothing);
      // Switching back must not revive the pending request's old lease.
      await dependencies.sessionManager.save(_session(1));
      repository.pending!.complete([_message('late-old-account')]);
      repository.pending = null;
      await tester.pumpAndSettle();
      expect(find.text('old-account'), findsNothing);
      expect(find.text('late-old-account'), findsNothing);
      final calls = repository.calls;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.calls, calls);
      expect(find.text('登录状态已改变，请重新进入会话。'), findsOneWidget);
    },
  );
}

AuthSession _session(int id) => AuthSession(
  accessToken: 'test-$id',
  tokenType: 'Bearer',
  expiresAt: DateTime(2030),
  userId: id,
  mobile: '',
  roles: 'USER',
);
ChatMessage _message(String id) => ChatMessage(
  id: id,
  conversationId: 'conversation-2',
  senderUserId: 2,
  senderName: 'peer',
  content: id,
  createdAt: DateTime(2026, 9, 7, 16),
  isMine: false,
  status: ChatMessageStatus.sent,
);

class _History extends MockMessageRepository {
  int calls = 0;
  bool failNext = false;
  Duration responseDelay = Duration.zero;
  Completer<List<ChatMessage>>? pending;
  final messages = <ChatMessage>[];
  @override
  bool get supportsPrivateRealtime => false;
  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async {
    calls++;
    if (pending != null) return pending!.future;
    if (failNext) {
      failNext = false;
      throw StateError('offline');
    }
    if (responseDelay > Duration.zero) {
      await Future<void>.delayed(responseDelay);
    }
    return List.of(messages);
  }
}

class _VisibleHistory extends _History
    implements VisiblePrivateMessageRepository {
  final boundaries = <Set<String>>[];
  final cursors = <String?>[];
  String? nextCursor;
  @override
  Future<PrivateMessageSyncBatch> fetchVisiblePrivateMessages(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
    Set<String> knownMessageIds = const {},
    String? resumeCursor,
  }) async {
    boundaries.add(Set.of(knownMessageIds));
    cursors.add(resumeCursor);
    return PrivateMessageSyncBatch(
      await super.fetchPrivateMessages(conversation),
      nextCursor: nextCursor,
    );
  }

  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
    String? requestId,
  }) async => _message(content);
}
