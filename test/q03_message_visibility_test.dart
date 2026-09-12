import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/features/media/private_media_host.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/domain/message_repository.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/message/presentation/private_media_widgets.dart';

import 'support/media_http_fakes.dart';
import 's13_private_media_host_test.dart' show PrivateHarness;

const _peer = ConversationSummary(
  id: 'conversation-2',
  kind: ConversationKind.privateChat,
  title: 'deleted-peer-name',
  lastMessage: 'old-preview',
  updatedAt: null,
  unreadCount: 0,
  targetUserId: 2,
);
const _other = ConversationSummary(
  id: 'conversation-3',
  kind: ConversationKind.privateChat,
  title: 'other-peer',
  lastMessage: 'other-preview',
  updatedAt: null,
  unreadCount: 0,
  targetUserId: 3,
);

void main() {
  testWidgets(
    'same-peer confirmed denial while backgrounded redacts before returning foreground',
    (tester) async {
      final repository = _PendingRepository();
      await _show(tester, repository);
      final pending = Completer<List<ChatMessage>>();
      repository.nextHistory = pending;
      await _tick(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      void resume() {
        if (tester.binding.lifecycleState != AppLifecycleState.paused) return;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }

      addTearDown(resume);
      await tester.pump();
      pending.completeError(_unavailable);
      await _drain(tester);
      final calls = repository.calls;
      resume();
      // Paused Flutter does not paint. Inspect the FIRST resumed frame, before
      // another network turn could repair the stale page by coincidence.
      await tester.pump();
      expect(find.text('old-body'), findsNothing);
      expect(find.text('deleted-peer-name'), findsNothing);
      await _drain(tester);
      expect(repository.calls, calls);
    },
  );
  testWidgets(
    'paged same-peer confirmed denial while backgrounded redacts before returning foreground',
    (tester) async {
      final fixture = _HttpFixture();
      await _show(tester, fixture.repository);
      final pending = Completer<MediaFakeResponse>();
      fixture.nextHistory = pending;
      await _tick(tester);
      expect(
        fixture.nextHistory,
        isNull,
        reason:
            'the real BackendMessageRepository Paged head must be in flight',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      void resume() {
        if (tester.binding.lifecycleState != AppLifecycleState.paused) return;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }

      addTearDown(resume);
      await tester.pump();
      pending.complete(MediaFakeResponse.json(null, status: 404, code: 40402));
      await _drain(tester);
      resume();
      // Paused Flutter does not paint. Inspect the FIRST resumed frame, before
      // another network turn could repair the stale page by coincidence.
      await tester.pump();
      expect(find.text('old-body'), findsNothing);
      expect(find.text('deleted-peer-name'), findsNothing);
    },
  );
  testWidgets(
    'list recheck remains redacted on repeated denial then accepts a fresh authorized list',
    (tester) async {
      final fixture = _HttpFixture();
      final deps = await _show(tester, fixture.repository, center: true);
      fixture.listFailure = (403, 40332);
      deps.imAuthoritativeRefreshBus
          .publish(
            const ImRefreshHint(messageId: 'list-revoked', eventVersion: 1),
          )
          .ignore();
      await _drain(tester);
      await tester.tap(find.text('检查账号状态'));
      await _drain(tester);
      expect(find.text('检查账号状态'), findsOneWidget);
      expect(find.text('deleted-peer-name'), findsNothing);
      fixture.listFailure = null;
      fixture.peers = [3];
      await tester.tap(find.text('检查账号状态'));
      await _drain(tester);
      expect(find.text('other-peer'), findsOneWidget);
      expect(find.text('deleted-peer-name'), findsNothing);
    },
  );

  testWidgets(
    'recheck HTTP late success across ABA cannot restore title history or media',
    (tester) async {
      final fixture = _HttpFixture();
      final deps = await _show(tester, fixture.repository);
      fixture.denial = (404, 40402);
      await _tick(tester);
      fixture.denial = null;
      final pending = Completer<MediaFakeResponse>();
      fixture.nextHistory = pending;
      await tester.tap(find.text('检查会话状态'));
      await _drain(tester);
      expect(
        fixture.nextHistory,
        isNull,
        reason: 'fresh history must actually be waiting',
      );
      await deps.sessionManager.save(_session(4));
      await deps.sessionManager.save(_session(1));
      pending.complete(
        MediaFakeResponse.json({
          'conversationId': _peer.id,
          'targetUserId': 2,
          'list': [_row('late-id', 'late-recheck-body')],
          'hasMore': false,
          'nextCursor': '',
          'unreadCount': 0,
          'imStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        }),
      );
      await _drain(tester);
      expect(find.text('deleted-peer-name'), findsNothing);
      expect(find.text('late-recheck-body'), findsNothing);
      expect(find.byType(PrivateMediaBubble), findsNothing);
      expect(find.text('登录状态已改变，请重新进入会话。'), findsOneWidget);
    },
  );
  testWidgets(
    'explicit recheck never restores cached data on list-only success or failed history',
    (tester) async {
      final fixture = _HttpFixture();
      await _show(tester, fixture.repository);
      fixture.denial = (403, 40381);
      await _tick(tester);
      await tester.tap(find.text('检查会话状态'));
      await _drain(tester);
      expect(find.text('old-body'), findsNothing);
      expect(find.text('deleted-peer-name'), findsNothing);
      fixture.denial = null;
      fixture.failure = (500, 50000);
      await tester.tap(find.text('检查会话状态'));
      await _drain(tester);
      expect(find.text('old-body'), findsNothing);
      fixture.failure = null;
      fixture.body = 'new-authoritative-body';
      fixture.peerName = 'current-authoritative-name';
      await tester.tap(find.text('检查会话状态'));
      await _drain(tester);
      expect(find.text('new-authoritative-body'), findsOneWidget);
      expect(find.text('current-authoritative-name'), findsOneWidget);
      expect(find.text('old-body'), findsNothing);
      expect(find.text('deleted-peer-name'), findsNothing);
    },
  );
  testWidgets(
    'send receipt cannot suppress a same-peer authoritative denial already in flight',
    (tester) async {
      final repository = _PendingRepository();
      await _show(tester, repository);
      final oldHistory = Completer<List<ChatMessage>>();
      repository.nextHistory = oldHistory;
      await _tick(tester);
      await tester.enterText(find.byType(TextField), 'sent-before-denial');
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pump();
      repository.send.complete(_message('accepted-before-erasure'));
      await _drain(tester);
      expect(find.text('accepted-before-erasure'), findsOneWidget);
      oldHistory.completeError(_unavailable);
      await _drain(tester);
      expect(find.text('old-body'), findsNothing);
      expect(find.text('accepted-before-erasure'), findsNothing);
      expect(find.text('deleted-peer-name'), findsNothing);
    },
  );

  testWidgets(
    'controlled media GET account denial clears the current chat immediately',
    (tester) async {
      final h = await _mediaHarness(tester);
      h.intercept = (_) =>
          MediaFakeResponse.json(null, status: 404, code: 40402);
      final fixture = _HttpFixture()..media = h.reference();
      await _show(tester, fixture.repository, mediaHost: h.create());
      await tester.tap(find.text('查看私信图片'));
      await _until(
        tester,
        () =>
            h.http.requests.isNotEmpty &&
            (find.text('重试读取媒体').evaluate().isNotEmpty ||
                find.byType(PrivateMediaBubble).evaluate().isEmpty),
      );
      expect(h.http.requests.single.method, 'GET');
      expect(find.text('old-body'), findsNothing);
      expect(find.byType(PrivateMediaBubble), findsNothing);
      expect(find.text('deleted-peer-name'), findsNothing);
    },
  );

  testWidgets(
    'poll denial stops current playback and removes its owned file without deleting pending intents',
    (tester) async {
      final h = await _mediaHarness(tester);
      h.purpose = MediaPurpose.privateVoice;
      h.intercept = (_) => MediaFakeResponse(
        200,
        Stream.value([1, 2, 3]),
        contentLength: 3,
        type: 'audio/mp4',
      );
      await h.store.write(
        's13.private-media.v1.1.99',
        'unrelated-retained-intent',
      );
      final fixture = _HttpFixture()..media = h.reference();
      await _show(tester, fixture.repository, mediaHost: h.create());
      await tester.tap(find.text('播放私信语音'));
      await _until(
        tester,
        () => h.players.isNotEmpty && h.players.last.plays == 1,
      );
      final player = h.players.last;
      expect(player.playing, isTrue);
      fixture.denial = (404, 40402);
      await _tick(tester);
      await _until(tester, () => player.closes > 0);
      expect(player.playing, isFalse);
      var removed = false;
      for (var attempt = 0; attempt < 50 && !removed; attempt++) {
        removed = await tester.runAsync(player.file!.exists) == false;
        await tester.pump();
      }
      expect(removed, isTrue);
      expect(
        await h.store.read('s13.private-media.v1.1.99'),
        'unrelated-retained-intent',
      );
    },
  );
  for (final (status, code) in [(404, 40402), (403, 40381), (401, 40101)]) {
    testWidgets(
      'HTTP $status/$code clears visible history title media and stops retry',
      (tester) async {
        final fixture = _HttpFixture();
        final deps = await _show(tester, fixture.repository);
        expect(
          find.text('old-body'),
          findsOneWidget,
          reason:
              'requests=${fixture.http.requests.map((r) => r.uri).toList()} text=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
        );
        expect(find.text('deleted-peer-name'), findsOneWidget);
        expect(find.byType(PrivateMediaBubble), findsOneWidget);
        fixture.denial = (status, code);
        await _tick(tester);
        expect(find.text('old-body'), findsNothing);
        expect(find.text('deleted-peer-name'), findsNothing);
        expect(find.byType(PrivateMediaBubble), findsNothing);
        expect(find.byType(PrivateMediaComposer), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        expect(find.text('重新加载'), findsNothing);
        final calls = fixture.historyCalls;
        fixture.denial = null;
        await _tick(tester);
        expect(fixture.historyCalls, calls);
        expect(find.text('old-body'), findsNothing);
        expect(
          deps.sessionManager.session?.userId,
          1,
          reason: 'not a global logout',
        );
      },
    );
  }

  for (final failure in <Object>[
    (500, 50000),
    (404, 40481),
    const SocketException('offline'),
  ]) {
    testWidgets('temporary/unrelated failure $failure preserves history', (
      tester,
    ) async {
      final fixture = _HttpFixture();
      await _show(tester, fixture.repository);
      fixture.failure = failure;
      await _tick(tester);
      expect(find.text('old-body'), findsOneWidget);
      expect(find.text('deleted-peer-name'), findsOneWidget);
      expect(find.byType(PrivateMediaBubble), findsOneWidget);
      fixture.failure = null;
      fixture.body = 'new-authoritative-body';
      await _tick(tester);
      expect(find.text('new-authoritative-body'), findsOneWidget);
    });
  }

  testWidgets(
    'authoritative conversation refresh removes old rows from already open search',
    (tester) async {
      final fixture = _HttpFixture();
      final deps = await _show(tester, fixture.repository, center: true);
      await tester.tap(find.byTooltip('搜索消息'));
      await tester.pumpAndSettle();
      expect(find.text('deleted-peer-name'), findsOneWidget);
      fixture.peers = [3];
      var refreshed = false;
      deps.imAuthoritativeRefreshBus
          .publish(const ImRefreshHint(messageId: 'hint', eventVersion: 1))
          .then((_) => refreshed = true);
      await _drain(tester);
      expect(
        refreshed,
        isTrue,
        reason: 'authoritative list HTTP must actually finish',
      );
      expect(find.text('deleted-peer-name'), findsNothing);
      expect(find.text('old-preview'), findsNothing);
      expect(find.text('other-peer'), findsOneWidget);
    },
  );

  testWidgets(
    'chat denial cannot resurface through cached list after failed refresh',
    (tester) async {
      final fixture = _HttpFixture();
      await _show(tester, fixture.repository, center: true);
      await tester.tap(find.text('deleted-peer-name'));
      await _drain(tester);
      expect(find.text('old-body'), findsOneWidget);
      fixture.denial = (404, 40402);
      await _tick(tester);
      fixture.listFailure = (500, 50000);
      await tester.pageBack();
      await _drain(tester);
      expect(find.text('deleted-peer-name'), findsNothing);
      expect(find.text('old-preview'), findsNothing);
      expect(find.text('other-peer'), findsOneWidget);
    },
  );

  testWidgets(
    'late successful text send cannot restore a denied conversation',
    (tester) async {
      final repository = _PendingRepository();
      await _show(tester, repository);
      await tester.enterText(find.byType(TextField), 'outgoing-pending');
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pump();
      repository.denied = true;
      await _tick(tester);
      repository.send.complete(_message('late-success'));
      await tester.pumpAndSettle();
      expect(find.text('late-success'), findsNothing);
      expect(find.text('old-body'), findsNothing);
      expect(repository.sends, 1);
    },
  );

  testWidgets('late old-peer denial does not clear the new peer', (
    tester,
  ) async {
    final repository = _PendingRepository();
    final deps = await _show(tester, repository);
    final oldHistory = Completer<List<ChatMessage>>();
    repository.nextHistory = oldHistory;
    await _tick(tester);
    expect(
      repository.nextHistory,
      isNull,
      reason: 'old read is really in flight',
    );
    await _render(tester, deps, _other);
    await _drain(tester);
    expect(find.text('other-peer'), findsOneWidget);
    oldHistory.completeError(_unavailable);
    await _drain(tester);
    expect(find.text('other-peer'), findsOneWidget);
    expect(find.text('body-3'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets(
    'ABA late denial and old title cannot contaminate another identity generation',
    (tester) async {
      final repository = _PendingRepository();
      final deps = await _show(tester, repository);
      final oldHistory = Completer<List<ChatMessage>>();
      repository.nextHistory = oldHistory;
      await _tick(tester);
      await deps.sessionManager.save(_session(4));
      await _drain(tester);
      expect(find.text('deleted-peer-name'), findsNothing);
      expect(find.text('old-body'), findsNothing);
      await _render(tester, deps, _other, key: const ValueKey('B'));
      await _drain(tester);
      oldHistory.completeError(_unavailable);
      await _drain(tester);
      expect(find.text('body-3'), findsOneWidget);
      await deps.sessionManager.save(_session(1));
      await _render(tester, deps, _peer, key: const ValueKey('new-A'));
      await _drain(tester);
      expect(
        find.text('old-body'),
        findsOneWidget,
        reason: 'fresh authoritative read in new generation, not old response',
      );
    },
  );

  testWidgets(
    'denied peer stays redacted on remount while other peer remains readable',
    (tester) async {
      final repository = _PendingRepository();
      final deps = await _show(tester, repository);
      repository.denied = true;
      await _tick(tester);
      final calls = repository.calls;
      repository.denied = false;
      await _render(tester, deps, _peer, key: const ValueKey('remount'));
      await _drain(tester);
      expect(repository.calls, calls);
      expect(find.text('deleted-peer-name'), findsNothing);
      await _render(tester, deps, _other, key: const ValueKey('other'));
      await _drain(tester);
      expect(find.text('body-3'), findsOneWidget);
      expect(find.text('other-peer'), findsOneWidget);
    },
  );

  for (final reason in ['BLOCKED_RELATION', 'FRIENDS_ONLY']) {
    testWidgets(
      'send 40381 $reason does not confuse send policy with read revocation',
      (tester) async {
        final repository = _PendingRepository();
        await _show(tester, repository);
        await tester.enterText(find.byType(TextField), 'attempted');
        await tester.tap(find.byTooltip('发送消息'));
        await tester.pump();
        repository.send.completeError(
          ApiException(
            kind: ApiFailureKind.forbidden,
            message: reason,
            httpStatus: 403,
            code: 40381,
          ),
        );
        await _drain(tester);
        expect(
          find.text('old-body'),
          reason == 'BLOCKED_RELATION' ? findsNothing : findsOneWidget,
        );
        expect(repository.sends, 1);
      },
    );
  }

  testWidgets(
    'current list permission loss clears open search; stale retry is not recovery',
    (tester) async {
      final fixture = _HttpFixture();
      final deps = await _show(tester, fixture.repository, center: true);
      await tester.tap(find.byTooltip('搜索消息'));
      await tester.pumpAndSettle();
      fixture.listFailure = (403, 40332);
      deps.imAuthoritativeRefreshBus
          .publish(
            const ImRefreshHint(messageId: 'denied-list', eventVersion: 1),
          )
          .ignore();
      await _drain(tester);
      expect(find.text('deleted-peer-name'), findsNothing);
      expect(find.text('other-peer'), findsNothing);
      fixture.listFailure = null;
      final calls = fixture.http.requests.length;
      deps.imAuthoritativeRefreshBus
          .publish(
            const ImRefreshHint(messageId: 'stale-hint', eventVersion: 2),
          )
          .ignore();
      await _drain(tester);
      expect(fixture.http.requests.length, calls);
      expect(find.text('old-preview'), findsNothing);
    },
  );

  test(
    'real HTTP repository preserves permission status/code rather than empty success',
    () async {
      final fixture = _HttpFixture();
      for (final denial in [(404, 40402), (403, 40381), (500, 50000)]) {
        fixture.denial = denial;
        await expectLater(
          fixture.repository.fetchVisiblePrivateMessagePage(
            _peer,
            isCurrent: () => true,
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.httpStatus, 'status', denial.$1)
                .having((e) => e.code, 'code', denial.$2),
          ),
        );
      }
      fixture.peers = [2, 3];
      expect(
        (await fixture.repository.fetchConversations()).map(
          (e) => e.targetUserId,
        ),
        [2, 3],
      );
      fixture.peers = [3];
      expect(
        (await fixture.repository.fetchConversations()).map(
          (e) => e.targetUserId,
        ),
        [3],
      );
    },
  );
}

const _unavailable = ApiException(
  kind: ApiFailureKind.business,
  message: '用户不存在或不可用',
  httpStatus: 404,
  code: 40402,
);

Future<void> _render(
  WidgetTester tester,
  AppDependencies deps,
  ConversationSummary peer, {
  Key? key,
}) => tester.pumpWidget(
  AppDependencyScope(
    dependencies: deps,
    child: MaterialApp(
      home: PrivateChatPage(key: key, conversation: peer),
    ),
  ),
);

Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await _drain(tester);
}

Future<void> _drain(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(
    ready(),
    isTrue,
    reason: 'bounded async fixture did not reach expected state',
  );
}

Future<PrivateHarness> _mediaHarness(WidgetTester tester) async {
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('q03-private-media-'),
  ))!;
  final h = PrivateHarness(dir);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    var cleaned = false;
    h.close().then((_) => cleaned = true);
    await _until(tester, () => cleaned);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
  return h;
}

AuthSession _session(int user) => AuthSession(
  accessToken: 'test-$user',
  tokenType: 'Bearer',
  expiresAt: DateTime(2030),
  userId: user,
  mobile: '',
  roles: 'USER',
);

Future<AppDependencies> _show(
  WidgetTester tester,
  MessageRepository repository, {
  bool center = false,
  PrivateMediaHost? mediaHost,
}) async {
  final deps = AppDependencies.forTestEnvironment(
    environment: const AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: 'https://configured.backend.test',
      clientType: 'test',
      clientInnerVersion: '1',
      oauthClientId: 'test',
      realtimeEndpoint: '',
    ),
    messageRepository: repository,
    privateMediaHost: mediaHost,
  );
  await deps.sessionManager.save(_session(1));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: deps,
      child: MaterialApp(
        home: center
            ? const MessageCenterPage()
            : const PrivateChatPage(conversation: _peer),
      ),
    ),
  );
  await _drain(tester);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    deps.dispose();
  });
  return deps;
}

class _HttpFixture {
  _HttpFixture() {
    http = MediaFakeHttp((request) {
      if (request.uri.path.endsWith('/queryChat')) {
        historyCalls++;
        final pending = nextHistory;
        nextHistory = null;
        if (pending != null) return pending.future;
        final error = denial ?? failure;
        if (error is (int, int))
          return MediaFakeResponse.json(null, status: error.$1, code: error.$2);
        if (error != null) throw error;
        return MediaFakeResponse.json({
          'conversationId': _peer.id,
          'historyVersion': '0',
          'clearedThroughSequence': '0',
          'targetUserId': 2,
          'list': [
            _row('text', body),
            _row('image', '', image: true, attachment: media),
          ],
          'hasMore': false,
          'nextCursor': '',
          'unreadCount': 0,
          'imStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        });
      }
      if (request.uri.path.endsWith('/conversations')) {
        final error = listFailure;
        if (error != null)
          return MediaFakeResponse.json(null, status: error.$1, code: error.$2);
        return MediaFakeResponse.json({
          'list': [
            for (final peer in peers)
              {
                'conversationId': 'conversation-$peer',
                'historyVersion': '0',
                'clearedThroughSequence': '0',
                'lastMessageSequence': '1',
                'targetUserId': peer,
                'nickName': peer == 2 ? peerName : _other.title,
                'lastMessage': peer == 2
                    ? _peer.lastMessage
                    : _other.lastMessage,
                'lastMessageAt': '2026-09-10T00:00:00Z',
                'unreadCount': 0,
              },
          ],
          'pageNum': 1,
          'pageSize': 100,
          'total': peers.length,
          'pages': peers.isEmpty ? 0 : 1,
          'hasMore': false,
          'imStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        });
      }
      return MediaFakeResponse.json({
        'targetUserId': 2,
        'historyVersion': '0',
        'clearedThroughSequence': '0',
        'markedRead': 0,
        'unreadCount': 0,
      });
    });
    repository = BackendMessageRepository(
      apiClient: http.api(identity),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => identity.user,
    );
  }
  final identity = TestMediaIdentity();
  late final MediaFakeHttp http;
  late final BackendMessageRepository repository;
  (int, int)? denial;
  (int, int)? listFailure;
  Object? failure;
  String body = 'old-body';
  String peerName = _peer.title;
  List<int> peers = [2, 3];
  int historyCalls = 0;
  Completer<MediaFakeResponse>? nextHistory;
  Map<String, Object?>? media;
}

Map<String, Object?> _row(
  String id,
  String content, {
  bool image = false,
  Map<String, Object?>? attachment,
}) => {
  'messageId': id,
  'messageSequence': id == 'text' ? '1' : '2',
  'senderUserId': 2,
  'receiverUserId': 1,
  'direction': 'INCOMING',
  'content': content,
  'messageType': image
      ? (attachment?['purpose'] == 'PRIVATE_VOICE' ? 'VOICE' : 'IMAGE')
      : 'TEXT',
  if (image)
    'media': [
      {
        ...?attachment,
        if (attachment == null) ...{
          'assetId': '11111111-1111-4111-8111-111111111111',
          'purpose': 'PRIVATE_IMAGE',
          'mediaType': 'image/png',
          'bytes': 50,
          'durationMillis': 0,
          'version': 3,
        },
      },
    ],
  'deliveryStatus': 'VENDOR_BLOCKED',
  'read': true,
  'storageStatus': 'FIRST_PARTY_STORED',
  'imStatus': 'VENDOR_BLOCKED',
  'providerInvocation': false,
  'createdAt': '2026-09-10T00:00:00Z',
};

ChatMessage _message(String text) => ChatMessage(
  id: text,
  conversationId: _peer.id,
  senderUserId: 2,
  senderName: _peer.title,
  content: text,
  createdAt: DateTime(2026),
  isMine: false,
  status: ChatMessageStatus.sent,
);

class _PendingRepository extends MockMessageRepository {
  bool denied = false;
  int calls = 0;
  Completer<List<ChatMessage>>? nextHistory;
  int sends = 0;
  final send = Completer<ChatMessage>();
  @override
  bool get supportsPrivateRealtime => false;
  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async {
    calls++;
    final pending = nextHistory;
    nextHistory = null;
    if (pending != null) return pending.future;
    if (denied && conversation.targetUserId == 2) throw _unavailable;
    return [_message(conversation.targetUserId == 2 ? 'old-body' : 'body-3')];
  }

  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
    String? requestId,
  }) {
    sends++;
    return send.future;
  }
}
