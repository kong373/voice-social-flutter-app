import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/user_avatar_descriptor.dart';
import 'package:voice_social_app/core/media/media_identity.dart';
import 'package:voice_social_app/core/media/media_models.dart';
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
    '375x667 private media chat follows latest own receipt across three rounds',
    (tester) async {
      // Explicit widget fixtures, not device-captured MediaQuery values.
      // Keep the real screen size; 260 logical px models a portrait keyboard.
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.padding = const FakeViewPadding(top: 40);
      tester.view.viewPadding = const FakeViewPadding(top: 40);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final repository = _MediaViewportHistory()..receive(0);
      final dependencies = await showChat(tester, repository);
      expect(dependencies.privateMediaHost.enabled, isTrue);
      expect(find.byKey(const Key('pm-pick-image')), findsOneWidget);
      expect(find.text('图片≤10MB；语音≤60秒/10MB；视频≤30秒/100MB。'), findsOneWidget);
      final media = MediaQuery.of(tester.element(find.byType(PrivateChatPage)));
      expect(media.size, const Size(375, 667));
      expect(media.padding, const EdgeInsets.only(top: 20));
      expect(media.textScaler.scale(1), 1);

      Map<String, Object?> snapshot(String stage, String content) {
        final text = find.text(content, findRichText: false);
        final viewport = tester.getRect(find.byType(ListView));
        final position = tester
            .widget<ListView>(find.byType(ListView))
            .controller!
            .position;
        final mounted = text.evaluate().length == 1;
        final rect = mounted ? tester.getRect(text) : null;
        final result = <String, Object?>{
          'stage': stage,
          'dataPresent': renderedMessages(
            tester,
          ).any((m) => m.content == content),
          'textMounted': mounted,
          'centerHit': text.hitTestable().evaluate().length == 1,
          'topHit':
              text
                  .hitTestable(at: const Alignment(0, -0.95))
                  .evaluate()
                  .length ==
              1,
          'textRect': rect,
          'viewport': viewport,
          'visibleTextHeight': rect != null && rect.overlaps(viewport)
              ? rect.intersect(viewport).height
              : 0.0,
          'offset': position.pixels,
          'maxExtent': position.maxScrollExtent,
          'extentAfter': position.extentAfter,
        };
        debugPrint('PRIVATE_VIEWPORT $result');
        return result;
      }

      for (var round = 0; round < 3; round++) {
        final own = _MediaViewportHistory.content('A', round);
        final peer = _MediaViewportHistory.content('B', round);
        if (round > 0) repository.receive(round);
        // Default foreground polling only: no manual refresh/scroll or bus event.
        var peerVisible = false;
        for (var tick = 0; tick < 50; tick++) {
          await tester.pump(const Duration(milliseconds: 100));
          peerVisible = find.text(peer).hitTestable().evaluate().length == 1;
          if (peerVisible) break;
        }
        expect(
          peerVisible,
          isTrue,
          reason: 'round $round peer visible within 5s',
        );
        await tester.pump(const Duration(milliseconds: 300));
        snapshot('peer-$round', peer);

        final composer = find.byType(TextField).hitTestable();
        await tester.tap(composer);
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 520);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          MediaQuery.of(
            tester.element(find.byType(PrivateChatPage)),
          ).viewInsets.bottom,
          260,
        );
        await tester.enterText(composer, own);
        await tester.pump(const Duration(milliseconds: 300));
        final sendButton = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '发送消息',
        );
        final send = sendButton.hitTestable();
        expect(send, findsOneWidget);
        await tester.tap(send);
        // The repository returns a stored receipt for this actual UI send.
        for (var tick = 0; tick < 50; tick++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(repository.sent.where((m) => m.content == own), hasLength(1));
        final receipt = renderedMessages(
          tester,
        ).singleWhere((m) => m.content == own);
        expect(receipt.isMine, isTrue);
        expect(receipt.status, ChatMessageStatus.storedPendingDelivery);
        expect(receipt.receiptLabel, '已留存·未读·实时不可用');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
        expect(renderedMessages(tester).last.id, receipt.id);
        snapshot('own-$round-keyboard', own);

        // The supplied post-failure screenshot has no keyboard. Observe that
        // state too without repairing the list offset using ensureVisible.
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        snapshot('own-$round-keyboard-dismissed', own);
        expect(tester.takeException(), isNull);
      }
      expect(repository.sent, hasLength(3));
      expect(repository.messages, hasLength(6));
      expect(renderedMessages(tester), hasLength(6));
      expect(repository.pageCalls, greaterThan(1));
      expect(repository.readMarks, greaterThan(0));
      expect(repository.boundaries, isEmpty, reason: 'use the Paged branch');
      final own = _MediaViewportHistory.content('A', 2);
      final last = snapshot('final-latest-own', own);
      final viewport = tester.getRect(find.byType(ListView));
      final textRect = tester.getRect(find.text(own, findRichText: false));
      expect(textRect.height, lessThan(viewport.height));
      expect(last['centerHit'], isTrue, reason: '$last');
      expect(textRect.top, greaterThanOrEqualTo(viewport.top), reason: '$last');
      expect(
        textRect.bottom,
        lessThanOrEqualTo(viewport.bottom),
        reason: '$last',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final interruptByDrag in [false, true]) {
    testWidgets(
      interruptByDrag
          ? 'manual history drag cancels pending send auto-scroll before a new page'
          : 'incoming page during send auto-scroll keeps the newest own bubble visible',
      (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = const Size(750, 1334);
        tester.view.padding = const FakeViewPadding(top: 40);
        tester.view.viewPadding = const FakeViewPadding(top: 40);
        tester.view.viewInsets = const FakeViewPadding(bottom: 520);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
          tester.view.resetViewPadding();
          tester.view.resetViewInsets();
        });
        final repository = _MediaViewportHistory();
        for (var index = 0; index < 2; index++) {
          repository.receive(index);
          repository.messages.add(
            repository._row(
              _message(
                _MediaViewportHistory.content('A', index),
              ).copyWithReadForTest(false),
            ),
          );
        }
        DateTime? lastPageAt;
        repository.onPageRead = () => lastPageAt = tester.binding.clock.now();
        await showChat(tester, repository);
        final own = _MediaViewportHistory.content('A', 2);
        await tester.enterText(find.byType(TextField), own);
        await tester.pump();
        // Complete the actual UI send just before an independently scheduled
        // foreground page read. The peer row was stored earlier but arrives late.
        final sendAt = lastPageAt!.add(const Duration(milliseconds: 1919));
        await tester.pump(sendAt.difference(tester.binding.clock.now()));
        await tester.tap(find.byTooltip('发送消息').hitTestable());
        await tester.pump(const Duration(milliseconds: 80));
        double? manualOffset;
        if (interruptByDrag) {
          await tester.drag(find.byType(ListView), const Offset(0, 90));
          await tester.pump();
          manualOffset = tester
              .widget<ListView>(find.byType(ListView))
              .controller!
              .offset;
        }
        repository.messages.add(
          repository._row(
            _message(_MediaViewportHistory.content('B', 2)),
            order: 3,
          ),
        );
        for (var tick = 0; tick < 50; tick++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(repository.sent.where((m) => m.content == own), hasLength(1));
        expect(renderedMessages(tester), hasLength(6));
        expect(
          renderedMessages(
            tester,
          ).where((m) => m.content == _MediaViewportHistory.content('B', 2)),
          hasLength(1),
        );
        expect(renderedMessages(tester).last.content, own);
        final text = find.text(own, findRichText: false);
        final position = tester
            .widget<ListView>(find.byType(ListView))
            .controller!
            .position;
        if (interruptByDrag) {
          expect(position.pixels, closeTo(manualOffset!, 1));
          expect(position.extentAfter, greaterThan(80));
        } else {
          expect(
            text.hitTestable(),
            findsOneWidget,
            reason:
                'offset=${position.pixels}, max=${position.maxScrollExtent}, '
                'after=${position.extentAfter}, text=${tester.getRect(text)}, '
                'viewport=${tester.getRect(find.byType(ListView))}',
          );
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
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
  @override
  Future<ApiResponse> getBoundToIdentity(
    String path, {
    required void Function() requireIdentity,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    requireIdentity();
    final response = await get(path, query: query, headers: headers);
    requireIdentity();
    return response;
  }

  @override
  Future<ApiResponse> postBoundToIdentity(
    String path, {
    required void Function() requireIdentity,
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) async {
    requireIdentity();
    final response = await post(
      path,
      query: query,
      headers: headers,
      body: body,
    );
    requireIdentity();
    return response;
  }

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
        'messageSequence': '$id',
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
        'historyVersion': '0',
        'clearedThroughSequence': '0',
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
      data: {
        'targetUserId': 2,
        'markedRead': 0,
        'unreadCount': 0,
        'historyVersion': '0',
        'clearedThroughSequence': '0',
      },
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

// Reuse the existing history/send fixture with the real media composer and
// Paged page-load branch. No media operation, external HTTP, or device is used.
class _MediaViewportHistory extends _VisibleHistory
    implements MediaPrivateMessageRepository, PagedPrivateMessageRepository {
  final sent = <ChatMessage>[];
  int pageCalls = 0;
  int readMarks = 0;

  @override
  Future<PrivateMessageSyncBatch> fetchVisiblePrivateMessagePage(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
    String? cursor,
  }) async {
    if (!isCurrent()) return const PrivateMessageSyncBatch([]);
    expect(conversation.id, 'conversation-2');
    expect(conversation.targetUserId, 2);
    expect(cursor, isNull, reason: 'all six fixture messages fit one page');
    pageCalls++;
    onPageRead?.call();
    final rows = await super.fetchPrivateMessages(conversation);
    if (!isCurrent()) return const PrivateMessageSyncBatch([]);
    // BackendMessageRepository reverses the server's id-DESC wire order into
    // chronological page output. _row assigns strictly increasing timestamps.
    return PrivateMessageSyncBatch(rows, conversationId: 'conversation-2');
  }

  @override
  Future<void> markVisiblePrivateMessagesRead(
    ConversationSummary conversation, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return;
    expect(conversation.id, 'conversation-2');
    expect(conversation.targetUserId, 2);
    // First-party read acknowledgement only; no provider or media invocation.
    readMarks++;
  }

  static String content(String role, int round) =>
      'dual-dualios0907-f40f21bd73-$role-private-$round';

  VoidCallback? onPageRead;

  ChatMessage _row(ChatMessage source, {int? order}) => ChatMessage(
    id: source.id,
    conversationId: source.conversationId,
    senderUserId: source.senderUserId,
    senderName: source.senderName,
    senderAvatar: UserAvatarDescriptor.fromBackendData({
      'kind': 'PRESET',
      'reference': source.isMine ? 'avatar-preset-moon' : 'avatar-preset-sun',
    }),
    content: source.content,
    createdAt: DateTime(
      2026,
      9,
      7,
      16,
    ).add(Duration(seconds: order ?? messages.length)),
    isMine: source.isMine,
    status: source.status,
    deliveryStatus: MessageDeliveryStatus.vendorBlocked,
    read: source.isMine ? false : null,
  );

  void receive(int round) => messages.add(_row(_message(content('B', round))));

  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
    String? requestId,
  }) async {
    final receipt = _row(
      await super.sendPrivateMessage(
        conversation: conversation,
        content: content,
        requestId: requestId,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    messages.add(receipt);
    sent.add(receipt);
    return receipt;
  }

  @override
  Future<ChatMessage> sendPrivateMediaMessage({
    required ConversationSummary conversation,
    required MediaReference media,
    required MediaIdentityScope identity,
    required String requestId,
  }) => throw StateError('This fixture only sends text through the real UI');
}
