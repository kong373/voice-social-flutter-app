import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/room_recovery_page.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';

void main() {
  const AppEnvironment liveTestEnvironment = AppEnvironment(
    backendMode: BackendMode.live,
    apiBaseUrl: 'https://example.invalid',
    clientType: 'Android',
    clientInnerVersion: '1',
    oauthClientId: 'public-client',
    realtimeEndpoint: 'wss://example.invalid/realtime',
    deploymentEnvironment: DeploymentEnvironment.development,
  );

  testWidgets(
    'live home keeps layout and labels an unavailable online count as unknown',
    (WidgetTester tester) async {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: liveTestEnvironment,
      );

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: Scaffold(
              body: VideoRuntimeHomePage(
                dependencies: dependencies,
                onOpenRoom: (_) {},
                repository: _UnknownCountDiscoveryRepository(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('实时房间'), findsWidgets);
      expect(find.textContaining('在线人数未知'), findsWidgets);
      expect(find.text('未知'), findsOneWidget);
      expect(find.byKey(const Key('live-room-room-unknown')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live home does not render fallback room identities before an empty/error response',
    (WidgetTester tester) async {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: liveTestEnvironment,
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: Scaffold(
              body: VideoRuntimeHomePage(
                dependencies: dependencies,
                onOpenRoom: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('深夜轻聊'), findsNothing);
      expect(find.textContaining('云朵和晚星'), findsNothing);
      expect(find.byKey(const Key('live-room-880217')), findsNothing);
    },
  );

  testWidgets('live account does not expose hardcoded recent rooms', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: liveTestEnvironment,
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.social(),
          home: Scaffold(
            body: VideoRuntimeAccountPage(
              dependencies: dependencies,
              profileRepository: MockSocialRepository(),
              onOpenRoom: (_) {},
              onSignOut: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近常听'), findsNothing);
    expect(find.byKey(const Key('recent-room-880217')), findsNothing);
  });

  testWidgets('live discovery renders the backend dynamic feed', (
    WidgetTester tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: liveTestEnvironment,
      );
      await dependencies.sessionManager.save(
        AuthSession(
          accessToken: 'dynamic-feed-token',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          userId: 10001,
          mobile: '13800138000',
          roles: 'USER',
        ),
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: VideoRuntimeDiscoveryPage(dependencies: dependencies),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      for (int index = 0; index < 10; index += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('服务端真实动态'), findsOneWidget);
      expect(find.text('这条内容来自 live dynamic backend feed'), findsOneWidget);
      expect(find.text('深夜轻聊'), findsNothing);
      expect(find.text('云朵和晚星'), findsNothing);
    }, createHttpClient: (_) => _DynamicFeedHttpClient());
  });

  testWidgets(
    'snapshot-only recovery names unavailable realtime and room hides unknown heat',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final RoomController controller = _snapshotOnlyController();
      addTearDown(controller.dispose);
      await controller.join();

      await tester.pumpWidget(
        MaterialApp(home: RoomRecoveryPage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('快照模式：实时能力未接入'), findsOneWidget);
      expect(find.textContaining('实时能力未接入'), findsWidgets);
      expect(find.text('实时通道已连接'), findsNothing);
      expect(find.text('实时公屏'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(home: VideoRuntimeRoomPage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('3.6k'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'live room public screen never renders client-generated history fixtures',
    (WidgetTester tester) async {
      final RoomController controller = _snapshotOnlyController(
        allowSyntheticPublicMessages: false,
      );
      addTearDown(controller.dispose);
      await controller.join();

      expect(controller.messages, isEmpty);

      await tester.pumpWidget(
        MaterialApp(home: VideoRuntimeRoomPage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('欢迎进入房间，请友善交流。'), findsNothing);
      expect(find.text('实时消息通道暂未连接，房间状态可能延迟。'), findsNothing);
      expect(find.text('麦位动态'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _DynamicFeedHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    expect(method, 'GET');
    expect(url.path, '/app-mini-api/mini/v1/dynamic/list');
    expect(url.queryParameters['pageNum'], '1');
    expect(url.queryParameters['pageSize'], '20');
    return _DynamicFeedHttpClientRequest();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DynamicFeedHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _DynamicFeedHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _DynamicFeedHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DynamicFeedHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DynamicFeedHttpClientResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _DynamicFeedHttpClientResponse()
    : super(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': <String, Object?>{
                'current': 1,
                'pageSize': 20,
                'size': 20,
                'total': 1,
                'pages': 1,
                'records': <Object?>[_dynamicFeedPost],
                'list': <Object?>[_dynamicFeedPost],
              },
            }),
          ),
        ),
      );

  static const Map<String, Object?> _dynamicFeedPost = <String, Object?>{
    'dynamicId': 'server-post-1',
    'userId': 20001,
    'nickName': '服务端真实动态',
    'content': '这条内容来自 live dynamic backend feed',
    'createdAt': '2026-08-25T08:00:00Z',
    'likeCount': 3,
    'commentCount': 1,
    'liked': false,
    'category': 'CHAT',
    'images': <Object?>[],
  };

  @override
  int get statusCode => HttpStatus.ok;

  @override
  final HttpHeaders headers = _DynamicFeedHttpHeaders();

  @override
  bool get isRedirect => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnknownCountDiscoveryRepository extends MockDiscoveryRepository {
  @override
  Future<List<DiscoveryRoom>> fetchHomeRooms({
    int page = 1,
    int pageSize = 20,
  }) async => <DiscoveryRoom>[
    const DiscoveryRoom(
      id: 'room-unknown',
      code: 'room-unknown',
      title: '实时房间',
      topic: '人数暂不可用',
      onlineCount: null,
      occupiedSeats: 0,
      isSpeaking: false,
      isFavorite: true,
    ),
  ];
}

RoomController _snapshotOnlyController({
  bool allowSyntheticPublicMessages = true,
}) {
  final _SnapshotOnlyRoomRepository repository = _SnapshotOnlyRoomRepository();
  return RoomController(
    roomId: 'live-room',
    title: '服务端房间快照',
    currentUserId: 10001,
    accessToken: 'test-token',
    repository: repository,
    rtcAdapter: const SnapshotOnlyRtcAdapter(),
    realtimeGateway: const SnapshotOnlyRoomRealtimeGateway(),
    allowSyntheticPublicMessages: allowSyntheticPublicMessages,
  );
}

class _SnapshotOnlyRoomRepository extends MockRoomRepository {
  static final RoomSnapshot _snapshot = RoomSnapshot(
    roomId: 'live-room',
    roomCode: 'live-room',
    title: '服务端房间快照',
    topic: '只展示已确认的房间信息',
    ownerId: 20001,
    role: RoomRole.listener,
    seats: <MicSeat>[
      for (int number = 1; number <= 8; number += 1)
        MicSeat(
          number: number,
          backendIndex: number,
          state: MicSeatState.available,
        ),
    ],
    rtc: const RtcCredentials(
      solution: RtcSolution.unknown,
      token: '',
      channelId: '',
      userId: 10001,
    ),
    transportMode: RoomTransportMode.snapshotOnly,
    publicScreenEnabled: false,
    pictureMessagesAllowed: false,
    autoLockMic: true,
    giftCatalogAvailable: false,
    giftBalance: null,
    onlineCount: null,
  );

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => _snapshot;

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async => _snapshot;
}
