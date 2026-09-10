import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/message/presentation/private_media_widgets.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'q19_private_history_contract_test.dart'
    show HistoryApi, conversation, history, watermark, row;

AuthSession session(int id) => AuthSession(
  accessToken: 'test-$id',
  tokenType: 'Bearer',
  expiresAt: DateTime(2030),
  userId: id,
  mobile: '',
  roles: 'USER',
);

void main() {
  late HistoryApi api;
  late AppDependencies deps;
  late BackendMessageRepository repository;
  Future<void> show(WidgetTester tester) async {
    api = HistoryApi();
    repository = BackendMessageRepository(
      apiClient: api,
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => deps.sessionManager.session?.userId ?? 0,
      identityGenerationProvider: () => deps.sessionManager.identityGeneration,
    );
    deps = AppDependencies.forTestEnvironment(
      environment: const AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: 'http://example.invalid/',
        clientType: 'test',
        clientInnerVersion: '1',
        oauthClientId: 'test',
        realtimeEndpoint: '',
        allowInsecureHttp: true,
      ),
      messageRepository: repository,
    );
    await deps.sessionManager.save(session(1));
    api.onPost = (path, _) => path.endsWith('/read')
        ? {...watermark(), 'markedRead': 0, 'unreadCount': 0}
        : watermark(version: '1', through: '1');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await mount(tester, deps);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      deps.dispose();
    });
  }

  Future<void> openClear(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空聊天记录'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'clear needs confirmation, unknown then 40322 keeps retry after remount; new messages visible',
    (tester) async {
      await show(tester);
      expect(find.text('text-1'), findsOneWidget);
      await openClear(tester);
      expect(find.text('只清空本人当前聊天记录，不影响对方，清空后无法恢复。'), findsOneWidget);
      expect(
        api.posts.where((p) => p.path.endsWith('/clear-history')),
        isEmpty,
      );
      api.onPost = (_, _) => throw const ApiException(
        kind: ApiFailureKind.network,
        message: '网络未知',
      );
      await tester.tap(find.text('确认清空'));
      await tester.pumpAndSettle();
      expect(find.text('text-1'), findsOneWidget);
      final key = api.posts
          .where((p) => p.path.endsWith('/clear-history'))
          .single
          .key;
      await tester.pumpWidget(const SizedBox());
      await mount(tester, deps);
      api.onPost = (_, _) => throw const ApiException(
        kind: ApiFailureKind.forbidden,
        code: 40322,
        message: '当前账号暂不可清空',
      );
      await tester.tap(find.text('重试原清空请求'));
      await tester.pumpAndSettle();
      expect(find.text('text-1'), findsOneWidget);
      expect(find.text('聊天记录已清空（仅本人）'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mount(tester, deps);
      expect(find.text('重试原清空请求'), findsOneWidget);
      api.onPost = (_, _) => watermark(version: '1', through: '1');
      api.onGet = (_, _) => history(version: '1', through: '1', sequences: []);
      await tester.tap(find.text('重试原清空请求'));
      await tester.pumpAndSettle();
      expect(
        api.posts.where((p) => p.path.endsWith('/clear-history')).last.key,
        key,
      );
      final clearPosts = api.posts
          .where((p) => p.path.endsWith('/clear-history'))
          .toList();
      expect(clearPosts, hasLength(3));
      for (final retry in clearPosts.skip(1)) {
        expect(retry.key, key);
        expect(retry.body, clearPosts.first.body);
      }
      expect(find.text('text-1'), findsNothing);
      expect(find.text('聊天记录已清空（仅本人）'), findsOneWidget);
      api.onGet = (_, _) =>
          history(version: '1', through: '1', sequences: ['2']);
      api.onPost = (_, _) => {
        ...watermark(version: '1', through: '1'),
        'markedRead': 0,
        'unreadCount': 0,
      };
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('text-2'), findsOneWidget);
      expect(find.text('text-1'), findsNothing);
    },
  );
  testWidgets(
    'account ABA while confirmation is open sends zero clear requests',
    (tester) async {
      await show(tester);
      await openClear(tester);
      await deps.sessionManager.save(session(3));
      await deps.sessionManager.save(session(1));
      await tester.pump();
      await tester.tap(find.text('确认清空'));
      await tester.pumpAndSettle();
      expect(
        api.posts.where((p) => p.path.endsWith('/clear-history')),
        isEmpty,
      );
      expect(find.text('text-1'), findsNothing);
      expect(find.text('聊天记录已清空（仅本人）'), findsNothing);
    },
  );
  testWidgets(
    'late clear success after logout cannot display success or old content',
    (tester) async {
      await show(tester);
      await openClear(tester);
      final gate = Completer<Object?>();
      api.onPost = (_, _) => gate.future;
      await tester.tap(find.text('确认清空'));
      await tester.pump();
      expect(
        api.posts.where((p) => p.path.endsWith('/clear-history')),
        hasLength(1),
      );
      await deps.sessionManager.save(session(3));
      await deps.sessionManager.save(session(1));
      gate.complete(watermark(version: '1', through: '1'));
      await tester.pumpAndSettle();
      expect(find.text('text-1'), findsNothing);
      expect(find.text('聊天记录已清空（仅本人）'), findsNothing);
      expect(repository.privateHistory.forTarget(2), isNull);
    },
  );
  testWidgets(
    'remote clear realtime recovery disposes media bubble; stale poll never restores it',
    (tester) async {
      await show(tester);
      final old = history();
      old['list'] = [
        {
          ...row('1'),
          'content': '',
          'messageType': 'IMAGE',
          'media': [
            {
              'assetId': '11111111-1111-4111-8111-111111111111',
              'purpose': 'PRIVATE_IMAGE',
              'mediaType': 'image/png',
              'bytes': 50,
              'durationMillis': 0,
              'version': 3,
            },
          ],
          'storageStatus': 'FIRST_PARTY_STORED',
          'imStatus': 'VENDOR_BLOCKED',
          'deliveryStatus': 'VENDOR_BLOCKED',
          'providerInvocation': false,
        },
      ];
      api.onGet = (_, _) => old;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(PrivateMediaBubble), findsOneWidget);
      api.onGet = (_, _) => history(version: '1', through: '1', sequences: []);
      api.onPost = (_, _) => {
        ...watermark(version: '1', through: '1'),
        'markedRead': 0,
        'unreadCount': 0,
      };
      deps.imAuthoritativeRefreshBus
          .publish(const ImRefreshHint(messageId: 'recover', eventVersion: 1))
          .ignore();
      await tester.pumpAndSettle();
      expect(find.byType(PrivateMediaBubble), findsNothing);
      api.onGet = (_, _) => old;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(PrivateMediaBubble), findsNothing);
      expect(find.text('text-1'), findsNothing);
    },
  );
  testWidgets(
    'clear invalidates pending send UI; old successful Future cannot republish',
    (tester) async {
      await show(tester);
      final gate = Completer<Object?>();
      api.onPost = (path, _) => path.endsWith('/send')
          ? gate.future
          : watermark(version: '1', through: '2');
      await tester.enterText(find.byType(TextField).last, 'old-send');
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pump();
      api.onGet = (_, _) => history(version: '1', through: '2', sequences: []);
      await repository.clearPrivateHistory(conversation);
      gate.complete({
        ...row('2'),
        ...watermark(),
        'senderUserId': 1,
        'receiverUserId': 2,
        'direction': 'OUTGOING',
        'content': 'old-send',
        'providerInvocation': false,
        'storageStatus': 'FIRST_PARTY_STORED',
        'deliveryStatus': 'VENDOR_BLOCKED',
      });
      await tester.pumpAndSettle();
      expect(find.text('text-1'), findsNothing);
      expect(find.text('old-send'), findsNothing);
      expect(api.posts.where((p) => p.path.endsWith('/send')), hasLength(1));
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '',
      );
    },
  );
  testWidgets('empty restored conversation retains real ID and clear menu', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpWidget(const SizedBox());
    api.onGet = (_, _) => history(version: '1', through: '1', sequences: []);
    api.onPost = (_, _) => {
      ...watermark(version: '1', through: '1'),
      'markedRead': 0,
      'unreadCount': 0,
    };
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: deps,
        child: const MaterialApp(
          home: PrivateChatPage(
            conversation: ConversationSummary.draft(
              kind: ConversationKind.privateChat,
              title: 'peer',
              lastMessage: '',
              unreadCount: 0,
              targetUserId: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('text-1'), findsNothing);
    await openClear(tester);
    expect(find.text('确认清空'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.posts.where((p) => p.path.endsWith('/clear-history')), isEmpty);
  });
  testWidgets(
    'visible list and open search drop cleared summary without deleting conversation',
    (tester) async {
      await show(tester);
      await tester.pumpWidget(const SizedBox());
      api.onGet = (_, _) => {
        'list': [
          {
            ...watermark(),
            'lastMessageSequence': '1',
            'lastMessage': 'old-summary',
            'nickname': 'peer',
            'unreadCount': 4,
            'lastMessageAt': '2026-09-10T00:00:00Z',
          },
        ],
        'pageNum': 1,
        'pageSize': 100,
        'pages': 1,
        'total': 1,
        'hasMore': false,
      };
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: const MaterialApp(home: MessageCenterPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('old-summary'), findsOneWidget);
      await tester.tap(find.byTooltip('搜索消息'));
      await tester.pumpAndSettle();
      expect(find.text('old-summary'), findsWidgets);
      api.onPost = (_, _) => watermark(version: '1', through: '1');
      await repository.clearPrivateHistory(conversation);
      await tester.pumpAndSettle();
      expect(find.text('old-summary'), findsNothing);
      expect(find.text('peer'), findsWidgets);
    },
  );
}

Future<void> mount(WidgetTester tester, AppDependencies deps) async {
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: deps,
      child: const MaterialApp(
        home: PrivateChatPage(conversation: conversation),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
