import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/message/presentation/private_media_widgets.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/media/private_media_host.dart';
import 's13_private_media_host_test.dart' show PrivateHarness, pmPeer, pmOther;
import 'support/media_http_fakes.dart';

const peer = ConversationSummary(
  id: 'peer-2',
  kind: ConversationKind.privateChat,
  title: 'peer',
  lastMessage: '',
  updatedAt: null,
  unreadCount: 0,
  targetUserId: 2,
);

class MediaHistory extends MockMessageRepository {
  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async => [
    ChatMessage(
      id: 'media-row',
      conversationId: null,
      senderUserId: 2,
      senderName: 'peer',
      content: '',
      isMine: false,
      createdAt: DateTime(2026, 9, 10),
      status: ChatMessageStatus.received,
      messageType: ChatMessageType.image,
      media: MediaReference.fromJson({
        'assetId': '11111111-2222-4333-8444-555555555555',
        'purpose': 'PRIVATE_IMAGE',
        'mediaType': 'image/png',
        'bytes': 3,
        'durationMillis': 0,
        'version': 3,
      }),
    ),
  ];
}

void main() {
  testWidgets(
    'reused real chat page changes recipient and removes previous draft text',
    (tester) async {
      final deps = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.mock,
          apiBaseUrl: 'https://contract.test',
          clientType: 'test',
          clientInnerVersion: '1',
          oauthClientId: 'public',
          realtimeEndpoint: '',
        ),
        messageRepository: MediaHistory(),
      );
      Future<void> show(ConversationSummary conversation) => tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: MaterialApp(home: PrivateChatPage(conversation: conversation)),
        ),
      );
      await show(peer);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'only for old peer');
      await show(pmOther);
      await tester.pumpAndSettle();
      expect(find.text('other'), findsOneWidget);
      expect(find.text('only for old peer'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      deps.dispose();
    },
  );
  testWidgets(
    'private IMAGE history is a controlled image action, not empty text',
    (tester) async {
      final deps = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.mock,
          apiBaseUrl: 'https://contract.test',
          clientType: 'test',
          clientInnerVersion: '1',
          oauthClientId: 'public-test',
          realtimeEndpoint: '',
        ),
        messageRepository: MediaHistory(),
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: const MaterialApp(home: PrivateChatPage(conversation: peer)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('查看私信图片'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      deps.dispose();
    },
  );

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 300 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(ready(), true, reason: 'bounded wait for observable completion');
  }

  Future<PrivateHarness> harness(WidgetTester tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('s13-private-ui-test-'),
    ))!;
    final h = PrivateHarness(directory);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      var cleaned = false;
      unawaited(h.close().then((_) => cleaned = true));
      await until(tester, () => cleaned);
      await tester.runAsync(() => directory.delete(recursive: true));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    return h;
  }

  Future<void> composer(
    WidgetTester tester,
    PrivateHarness h,
    PrivateMediaHost host, {
    ConversationSummary conversation = pmPeer,
    bool visible = true,
    ValueChanged<ChatMessage>? sent,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivateMediaComposer(
            host: host,
            repository: h.repository,
            conversation: conversation,
            visible: visible,
            onSent: sent ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool has(String text) => find.text(text).evaluate().isNotEmpty;
  Future<void> pickUpload(WidgetTester tester, PrivateHarness h) async {
    await tester.tap(find.byKey(const Key('pm-pick-image')));
    await until(tester, () => has('上传媒体'));
    expect(h.http.requests, isEmpty);
    await tester.tap(find.text('上传媒体'));
    await until(tester, () => has('已上传'));
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('pm-send')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pm-confirm-send')));
    await tester.pump();
  }

  testWidgets(
    'real AppDependencies chat wiring sends one image only after explicit confirmation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.view.resetViewInsets();
      });
      final h = await harness(tester), host = h.create();
      h.intercept = (r) {
        if ((r.uri.path.contains('/message/') ||
                r.uri.path.endsWith('/imMessage/queryChat')) &&
            !r.uri.path.endsWith('/send')) {
          if (r.method == 'GET')
            return MediaFakeResponse.json({
              'conversationId': pmPeer.id,
              'targetUserId': 2,
              'list': <Object?>[],
              'hasMore': false,
              'nextCursor': '',
              'unreadCount': 0,
              'imStatus': 'VENDOR_BLOCKED',
              'providerInvocation': false,
            });
          return MediaFakeResponse.json({
            'targetUserId': 2,
            'markedRead': 0,
            'unreadCount': 0,
          });
        }
        return h.respond(r);
      };
      final deps = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'https://contract.test',
          clientType: 'test',
          clientInnerVersion: '1',
          oauthClientId: 'public',
          realtimeEndpoint: '',
        ),
        messageRepository: h.repository,
        privateMediaHost: host,
      );
      await deps.sessionManager.save(
        AuthSession(
          accessToken: 'contract-A',
          tokenType: 'Bearer',
          expiresAt: DateTime(2099),
          userId: 1,
          mobile: '',
          roles: 'USER',
        ),
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: const MaterialApp(home: PrivateChatPage(conversation: pmPeer)),
        ),
      );
      await until(tester, () => has('还没有消息，认真说第一句话吧'));
      expect(
        find.byKey(const Key('pm-pick-image')),
        findsOneWidget,
        reason: h.http.requests
            .map((r) => '${r.method} ${r.uri.path}')
            .join(', '),
      );
      await tester.tap(find.byKey(const Key('pm-pick-image')));
      await until(tester, () => has('上传媒体'));
      await Scrollable.ensureVisible(tester.element(find.text('上传媒体')));
      await tester.pump();
      await tester.tap(find.text('上传媒体'));
      await until(tester, () => has('已上传'));
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('pm-send'))),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('pm-send')));
      await tester.pump();
      expect(
        h.http.requests.where((r) => r.uri.path.endsWith('/message/send')),
        isEmpty,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('pm-confirm-send'))),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('pm-confirm-send')));
      await until(tester, () => has('查看私信图片'));
      expect(h.http.requests.where((r) => r.method == 'PUT').length, 1);
      expect(
        h.http.requests
            .where((r) => r.uri.path.endsWith('/message/send'))
            .length,
        1,
      );
      expect(find.textContaining('已留存'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      deps.dispose();
    },
  );
  testWidgets(
    'unknown send remount requires human confirmation, same bytes and key',
    (tester) async {
      final h = await harness(tester), host = h.create();
      var successes = 0;
      await composer(tester, h, host, sent: (_) => successes++);
      await pickUpload(tester, h);
      h.intercept = (r) {
        if (r.uri.path.endsWith('/message/send'))
          throw const SocketException('lost');
        return h.respond(r);
      };
      await confirm(tester);
      await until(tester, () => has('恢复原发送'));
      final original = h.http.requests.last;
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await composer(tester, h, host, sent: (_) => successes++);
      expect(h.http.requests.last, same(original));
      expect(successes, 0);
      h.intercept = null;
      await confirm(tester);
      await until(tester, () => successes == 1);
      expect(h.http.requests.last.body, original.body);
      expect(
        h.http.requests.last.headers.value('X-Request-Id'),
        original.headers.value('X-Request-Id'),
      );
    },
  );
  testWidgets(
    'ABA while send pending shows no old success and retains intent for original actor',
    (tester) async {
      final h = await harness(tester), host = h.create();
      var successes = 0;
      await composer(tester, h, host, sent: (_) => successes++);
      await pickUpload(tester, h);
      final response = Completer<MediaFakeResponse>();
      var entered = false;
      h.intercept = (r) {
        entered = true;
        return response.future;
      };
      await confirm(tester);
      await until(tester, () => entered);
      h.identity.change(7);
      h.identity.change(1);
      await tester.pump();
      response.complete(MediaFakeResponse.json(h.receipt()));
      await tester.pumpAndSettle();
      expect(successes, 0);
      expect(find.textContaining('登录状态已改变'), findsOneWidget);
      final raw = await h.store.read('s13.private-media.v1.1.2');
      expect(raw, contains('"sendAttempted":true'));
    },
  );
  testWidgets(
    'receiver change invalidates confirmation and never sends old asset to new peer',
    (tester) async {
      final h = await harness(tester), host = h.create();
      await composer(tester, h, host);
      await pickUpload(tester, h);
      await tester.tap(find.byKey(const Key('pm-send')));
      await tester.pump();
      expect(find.byKey(const Key('pm-confirm-send')), findsOneWidget);
      await composer(tester, h, host, conversation: pmOther);
      expect(find.byKey(const Key('pm-confirm-send')), findsNothing);
      expect(has('已上传'), false);
      expect(
        h.http.requests.where((r) => r.uri.path.endsWith('/message/send')),
        isEmpty,
      );
    },
  );
  testWidgets(
    'microphone permission denied is explicit; background cancels recording without send',
    (tester) async {
      final h = await harness(tester), host = h.create();
      await composer(tester, h, host);
      h.inputs.last.permission = false;
      await tester.tap(find.byKey(const Key('pm-record')));
      await tester.pumpAndSettle();
      expect(has('麦克风权限被拒绝'), true);
      expect(h.inputs.last.starts, 0);
      h.inputs.last.permission = true;
      await tester.tap(find.byKey(const Key('pm-record')));
      await tester.pumpAndSettle();
      expect(has('完成录音'), true);
      final input = h.inputs.last;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(input.closes, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(has('完成录音'), false);
      expect(h.http.requests, isEmpty);
    },
  );
  testWidgets(
    'voice automatic limit stops into a draft, never uploads or sends',
    (tester) async {
      final h = await harness(tester), host = h.create();
      await composer(tester, h, host);
      await tester.tap(find.byKey(const Key('pm-record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      await until(tester, () => has('上传媒体'));
      expect(h.inputs.last.stops, 1);
      expect(h.http.requests, isEmpty);
    },
  );
  testWidgets(
    'cancel recording releases native input and permits a fresh explicit recording',
    (tester) async {
      final h = await harness(tester), host = h.create();
      await composer(tester, h, host);
      await tester.tap(find.byKey(const Key('pm-record')));
      await tester.pumpAndSettle();
      final first = h.inputs.last;
      await tester.tap(find.text('取消录音'));
      await tester.pumpAndSettle();
      expect(first.closes, 1);
      expect(has('录制语音'), true);
      await tester.tap(find.byKey(const Key('pm-record')));
      await tester.pumpAndSettle();
      expect(h.inputs.last, isNot(same(first)));
      expect(h.inputs.last.starts, 1);
      expect(h.http.requests, isEmpty);
    },
  );
  for (final purpose in [
    MediaPurpose.privateVoice,
    MediaPurpose.privateVideo,
  ]) {
    testWidgets(
      '$purpose playback uses controlled local file and stops on background',
      (tester) async {
        final h = await harness(tester), host = h.create();
        h.purpose = purpose;
        final media = MediaReference.fromJson(h.reference());
        h.intercept = (r) => MediaFakeResponse(
          200,
          Stream.value([1, 2, 3]),
          contentLength: 3,
          type: media.mediaType,
        );
        final message = ChatMessage(
          id: 'private-play',
          conversationId: null,
          senderUserId: 2,
          senderName: 'peer',
          content: '',
          createdAt: DateTime(2026),
          isMine: false,
          status: ChatMessageStatus.received,
          media: media,
          messageType: purpose == MediaPurpose.privateVoice
              ? ChatMessageType.voice
              : ChatMessageType.video,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PrivateMediaBubble(
                message: message,
                host: host,
                visible: true,
              ),
            ),
          ),
        );
        await tester.tap(
          find.text(purpose == MediaPurpose.privateVoice ? '播放私信语音' : '播放私信视频'),
        );
        await until(
          tester,
          () => h.players.isNotEmpty && h.players.last.plays == 1,
        );
        final player = h.players.last;
        expect(player.file!.isAbsolute, true);
        expect(player.file!.path, startsWith(h.directory.path));
        expect(h.http.requests.single.method, 'GET');
        expect(h.http.requests.single.uri.host, 'configured.backend.test');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        await until(tester, () => player.closes > 0);
        expect(player.playing, false);
        var removed = false;
        for (var attempt = 0; attempt < 100 && !removed; attempt++) {
          removed = await tester.runAsync(player.file!.exists) == false;
          if (!removed) await tester.pump(const Duration(milliseconds: 10));
        }
        expect(
          removed,
          true,
          reason: 'background cleanup removes the controlled local file',
        );
      },
    );
  }
  testWidgets(
    'permission read failure offers retry; late content after ABA never reaches player',
    (tester) async {
      final h = await harness(tester), host = h.create();
      h.purpose = MediaPurpose.privateVoice;
      final message = ChatMessage(
        id: 'read-denied',
        conversationId: null,
        senderUserId: 2,
        senderName: 'peer',
        content: '',
        createdAt: DateTime(2026),
        isMine: false,
        status: ChatMessageStatus.received,
        media: MediaReference.fromJson(h.reference()),
        messageType: ChatMessageType.voice,
      );
      h.intercept = (_) => MediaFakeResponse.json({}, status: 403, code: 40381);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivateMediaBubble(
              message: message,
              host: host,
              visible: true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('播放私信语音'));
      await until(tester, () => has('重试读取媒体'));
      final gate = Completer<MediaFakeResponse>();
      var entered = false;
      h.intercept = (_) {
        entered = true;
        return gate.future;
      };
      await tester.tap(find.text('重试读取媒体'));
      await until(tester, () => entered);
      h.identity.change(7);
      h.identity.change(1);
      await tester.pump();
      gate.complete(
        MediaFakeResponse(
          200,
          Stream.value([1, 2, 3]),
          contentLength: 3,
          type: 'audio/mp4',
        ),
      );
      await tester.pumpAndSettle();
      expect(h.players, isEmpty);
    },
  );
}
