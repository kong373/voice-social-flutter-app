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
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';

void main() {
  Future<AppDependencies> showChat(
    WidgetTester tester,
    MessageRepository repository, {
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

  testWidgets(
    '30001 cursor rows cannot starve newest messages behind old read scan',
    (tester) async {
      final api = _CursorApi()..oldDelay = const Duration(milliseconds: 100);
      final repository = BackendMessageRepository(
        apiClient: api,
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 1,
      );
      await showChat(tester, repository);
      api.latest = 30002;
      for (var tick = 0; tick < 50; tick++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.text('row-30002'),
        findsOneWidget,
        reason:
            'cursors=${api.cursors}; visible=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
      );
      expect(api.maximumFlights, 1);
      expect(
        api.cursors.where((cursor) => cursor == null).length,
        greaterThanOrEqualTo(2),
      );
      // Newest-first polling must continue even though the 300-page old scan
      // is nowhere near complete. Each tick may fetch at most two pages.
      expect(api.cursors.length, lessThanOrEqualTo(8));
    },
  );

  List<ChatMessage> renderedMessages(WidgetTester tester) {
    final list = tester.widget<ListView>(find.byType(ListView));
    final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
    return List.generate(delegate.childCount!, (index) {
      final dynamic bubble = delegate.builder(
        tester.element(find.byType(ListView)),
        index,
      );
      // Inspect the private stateless bubble produced by the real list builder.
      // ignore: avoid_dynamic_calls
      return bubble.message as ChatMessage;
    });
  }

  testWidgets(
    'slow successful newest polling does not starve read acknowledgement',
    (tester) async {
      final api = _CursorApi()..latest = 2;
      await showChat(
        tester,
        BackendMessageRepository(
          apiClient: api,
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 1,
        ),
      );
      final initialMarks = api.marks;
      expect(initialMarks, greaterThan(0));
      api
        ..headDelay = const Duration(milliseconds: 2800)
        ..latest = 3;
      api.incomingIds.add(3);
      for (var tick = 0; tick < 160; tick++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(renderedMessages(tester).last.id, 'row-3');
      expect(renderedMessages(tester).last.isMine, isFalse);
      expect(api.marks, greaterThan(initialMarks));
      expect(api.maximumFlights, 1);
      // This is a progress/fairness assertion under slow network responses,
      // not a claim that the five-second delivery gate passed in this case.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(api.flights, 0);
    },
  );

  testWidgets('slow successful newest polling does not starve a history gap', (
    tester,
  ) async {
    final api = _CursorApi()..latest = 201;
    await showChat(
      tester,
      BackendMessageRepository(
        apiClient: api,
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 1,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(renderedMessages(tester).length, 201);
    final initialOldPages = api.cursors
        .where((cursor) => cursor != null)
        .length;
    final initialMarks = api.marks;
    api
      ..headDelay = const Duration(milliseconds: 2800)
      ..latest = 451;
    for (var tick = 0; tick < 160; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      renderedMessages(tester).map((message) => message.id),
      List.generate(451, (index) => 'row-${index + 1}'),
    );
    expect(
      api.cursors.where((cursor) => cursor != null).length,
      greaterThan(initialOldPages),
    );
    expect(api.marks, greaterThan(initialMarks));
    expect(api.maximumFlights, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(api.flights, 0);
  });

  testWidgets(
    'cursor scan updates oldest receipt without loss or duplicate rows',
    (tester) async {
      final api = _CursorApi()..latest = 201;
      await showChat(
        tester,
        BackendMessageRepository(
          apiClient: api,
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 1,
        ),
      );
      for (var tick = 0; tick < 25; tick++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(renderedMessages(tester).length, 201);
      api.oldestRead = true;
      for (var tick = 0; tick < 50; tick++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final messages = renderedMessages(tester);
      expect(
        messages.map((message) => message.id),
        List.generate(201, (index) => 'row-${index + 1}'),
      );
      expect(messages.first.read, isTrue);
      expect(messages.first.readAt, DateTime.utc(2026, 9, 8, 10));
      expect(api.maximumFlights, 1);
      expect(api.marks, greaterThan(0));
    },
  );

  for (final changeAccount in [false, true]) {
    testWidgets(
      'cursor scan late response rejected on ${changeAccount ? 'identity change' : 'hidden route'}',
      (tester) async {
        final api = _CursorApi()..latest = 301;
        final navigator = GlobalKey<NavigatorState>();
        var userId = 1;
        final dependencies = await showChat(
          tester,
          BackendMessageRepository(
            apiClient: api,
            routes: const BackendRouteCatalog(),
            currentUserIdProvider: () => userId,
          ),
          navigator: navigator,
        );
        api.oldGate = Completer<void>();
        api.poisonOld = true;
        api.latest = 302;
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 200));
        // The newest page is already accepted while the old page is pending.
        expect(renderedMessages(tester).last.id, 'row-302');
        final calls = api.cursors.length;
        if (changeAccount) {
          userId = 3;
          await dependencies.sessionManager.save(_session(3));
        } else {
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('covered')),
            ),
          );
        }
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 6));
        expect(api.cursors.length, calls);
        expect(api.marks, 0);
        api.oldGate!.complete();
        api.oldGate = null;
        api.poisonOld = false;
        await tester.pumpAndSettle();
        expect(api.marks, 0);
        if (!changeAccount) {
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(
            renderedMessages(
              tester,
            ).any((message) => message.content.startsWith('late-old')),
            isFalse,
          );
        } else {
          expect(find.text('登录状态已改变，请重新进入会话。'), findsOneWidget);
        }
        expect(api.maximumFlights, 1);
      },
    );
  }

  testWidgets('cursor newest burst preserves the gap and defers marking read', (
    tester,
  ) async {
    final api = _CursorApi()..latest = 201;
    await showChat(
      tester,
      BackendMessageRepository(
        apiClient: api,
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 1,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(renderedMessages(tester).length, 201);
    final marks = api.marks;
    api.latest = 451;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(renderedMessages(tester).last.id, 'row-451');
    expect(
      api.marks,
      marks,
      reason: '100-row head and one old page do not cover the 250-row gap',
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      renderedMessages(tester).map((message) => message.id),
      List.generate(451, (index) => 'row-${index + 1}'),
    );
    expect(api.maximumFlights, 1);
  });

  testWidgets(
    'invalid old cursor page cannot erase or block newest publication',
    (tester) async {
      final api = _CursorApi()..invalidOldTarget = true;
      await showChat(
        tester,
        BackendMessageRepository(
          apiClient: api,
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => 1,
        ),
      );
      expect(renderedMessages(tester).length, 100);
      api.latest = 30002;
      for (var tick = 0; tick < 50; tick++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('row-30002'), findsOneWidget);
      expect(renderedMessages(tester).length, 101);
      expect(api.marks, 0);
      expect(api.maximumFlights, 1);
    },
  );

  testWidgets('sender receives authoritative read and never regresses', (
    tester,
  ) async {
    final repository = _VisibleHistory()
      ..messages.add(_message('own').copyWithReadForTest(false));
    await showChat(tester, repository);
    expect(find.textContaining('未读'), findsOneWidget);
    repository.messages[0] = _message('own').copyWithReadForTest(true);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('已读'), findsOneWidget);
    repository.messages[0] = _message('own').copyWithReadForTest(false);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('已读'), findsOneWidget);
    expect(find.text('own'), findsOneWidget);
  });

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
    'receipt-only refresh preserves equal-time order and read timestamp',
    (tester) async {
      final repository = _History()
        ..messages.addAll(
          List.generate(
            40,
            (index) => _message('own-$index')
                .copyWithReadForTest(true)
                .copyWith(readAt: DateTime.utc(2026, 9, 8)),
          ),
        );
      await showChat(tester, repository);
      List<String> visibleOrder() => tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .where((text) => text.startsWith('own-'))
          .toList();
      final before = visibleOrder();
      repository.messages.replaceRange(
        0,
        40,
        repository.messages.reversed.toList(),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(visibleOrder(), before);
      final message = repository.messages.first;
      expect(message.copyWith(read: false).readAt, DateTime.utc(2026, 9, 8));
      expect(message.copyWith(read: false).read, isTrue);
    },
  );

  testWidgets(
    'read refresh walks to oldest unresolved sender without dropping history',
    (tester) async {
      final repository = _VisibleHistory()
        ..messages.addAll([
          _message('old-own').copyWithReadForTest(false),
          _message('new-peer'),
        ]);
      await showChat(tester, repository);
      repository.messages
        ..clear()
        ..add(_message('new-peer'));
      repository.nextCursor = 'older';
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(repository.boundaries.last, {'old-own'});
      repository.messages
        ..clear()
        ..add(_message('old-own').copyWithReadForTest(true));
      repository.nextCursor = null;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(repository.cursors, contains('older'));
      expect(find.text('old-own'), findsOneWidget);
      expect(find.text('new-peer'), findsOneWidget);
      expect(find.textContaining('已读'), findsOneWidget);
    },
  );

  testWidgets('hidden then visible route rejects the old read response', (
    tester,
  ) async {
    final repository = _History()
      ..messages.add(_message('own').copyWithReadForTest(false));
    final navigator = GlobalKey<NavigatorState>();
    await showChat(tester, repository, navigator: navigator);
    repository.pending = Completer<List<ChatMessage>>();
    await tester.pump(const Duration(seconds: 3));
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    repository.pending!.complete([_message('own').copyWithReadForTest(true)]);
    repository.pending = null;
    await tester.pumpAndSettle();
    expect(find.textContaining('未读'), findsOneWidget);
  });

  testWidgets('unknown and delivered do not imply read or unread', (
    tester,
  ) async {
    final repository = _History()
      ..messages.add(
        ChatMessage(
          id: 'own',
          conversationId: 'conversation-2',
          senderUserId: 1,
          senderName: 'me',
          content: 'own',
          createdAt: DateTime(2026),
          isMine: true,
          status: ChatMessageStatus.sent,
          deliveryStatus: MessageDeliveryStatus.delivered,
        ),
      );
    await showChat(tester, repository);
    expect(find.text('已留存·已读状态未知·实时已送达'), findsOneWidget);
    expect(find.textContaining('未读'), findsNothing);
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

// Exercise the production repository/parser with the backend's id < cursor,
// id DESC, pageSize/hasMore contract, rather than returning model snapshots.
class _CursorApi extends ApiClient {
  _CursorApi()
    : super(
        baseUri: Uri.parse('http://example.invalid/'),
        clientType: 'test',
        clientInnerVersion: '1',
        authorizationProvider: () => null,
      );
  int latest = 30001;
  int flights = 0;
  int maximumFlights = 0;
  int marks = 0;
  Duration headDelay = Duration.zero;
  Duration oldDelay = Duration.zero;
  final incomingIds = <int>{30002};
  Completer<void>? oldGate;
  bool oldestRead = false;
  bool poisonOld = false;
  bool invalidOldTarget = false;
  final cursors = <String?>[];
  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    expect(path, '/app-api/user/imMessage/queryChat');
    expect(query!['targetUserId'], '2');
    final cursor = query['cursor'];
    cursors.add(cursor);
    flights++;
    if (flights > maximumFlights) maximumFlights = flights;
    final top = cursor == null ? latest : int.parse(cursor) - 1;
    final count = top.clamp(0, int.parse(query['pageSize']!));
    final rows = List.generate(count, (index) {
      final id = top - index;
      return <String, Object?>{
        'messageId': 'row-$id',
        'senderUserId': incomingIds.contains(id) ? 2 : 1,
        'direction': incomingIds.contains(id) ? 'INCOMING' : 'OUTGOING',
        'content': poisonOld && cursor != null ? 'late-old-$id' : 'row-$id',
        'deliveryStatus': 'VENDOR_BLOCKED',
        'read': id == 1 && oldestRead,
        'readAt': id == 1 && oldestRead ? '2026-09-08T10:00:00Z' : '',
        'createdAt': DateTime.utc(
          2026,
        ).add(Duration(seconds: id)).toIso8601String(),
      };
    });
    if (cursor == null && headDelay != Duration.zero) {
      await Future<void>.delayed(headDelay);
    }
    if (cursor != null) {
      if (oldGate != null) await oldGate!.future;
      if (oldDelay != Duration.zero) await Future<void>.delayed(oldDelay);
    }
    flights--;
    return ApiResponse(
      code: 200,
      message: '',
      data: {
        'list': rows,
        'conversationId': 'conversation-2',
        'targetUserId': cursor != null && invalidOldTarget ? 99 : 2,
        'hasMore': top > count,
        'nextCursor': top > count ? '${top - count + 1}' : '',
        'unreadCount': 0,
        'imStatus': 'VENDOR_BLOCKED',
        'providerInvocation': false,
      },
    );
  }

  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    marks++;
    return const ApiResponse(
      code: 200,
      message: '',
      data: {'targetUserId': 2, 'markedRead': 0, 'unreadCount': 0},
    );
  }
}

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

extension on ChatMessage {
  ChatMessage copyWithReadForTest(bool read) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderUserId: 1,
    senderName: 'me',
    content: content,
    createdAt: createdAt,
    isMine: true,
    status: ChatMessageStatus.storedPendingDelivery,
    read: read,
  );
}

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
  }) async => _message(content).copyWithReadForTest(false);
}
