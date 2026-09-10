import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/presentation/preset_avatar_view.dart';
import 'package:voice_social_app/features/account/presentation/user_avatar_view.dart';
import 'package:voice_social_app/features/media/private_media_host.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/im/domain/im_authoritative_refresh_bus.dart';
import 'package:voice_social_app/features/social/data/backend_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';
import 'package:voice_social_app/features/room/data/platform_room_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'support/media_http_fakes.dart';
import 'user_avatar_view_test.dart'
    show AvatarDependencies, preset, avatarSession, avatarPng, decoded;
import 'user_avatar_media_transport_test.dart' show avatarAsset, avatarResponse;
import 'user_avatar_projection_test.dart' show avatarProfile;
import 'decoration_profile_display_test.dart' show frame, frameKey;
import 'room_lease_controller_test.dart' as lease;

void main() {
  testWidgets(
    'actual public profile uploaded descriptor reads fixed content route and disposes on logout',
    (tester) async {
      final png = await tester.runAsync(avatarPng);
      final backing = await AvatarDependencies.create(
        (request) => request.uri.path.endsWith('/content')
            ? avatarResponse(bytes: png!)
            : MediaFakeResponse.json({
                ...avatarProfile(),
                'avatar': {
                  'kind': 'UPLOADED',
                  'reference': avatarAsset,
                  'version': 1,
                },
              }),
      );
      final deps = _UiDependencies(backing);
      addTearDown(() => backing.close(tester));
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: const MaterialApp(home: PublicProfilePage(userId: 1)),
        ),
      );
      await decoded(tester);
      final images = find.descendant(
        of: find.byType(UserAvatarView),
        matching: find.byType(RawImage),
      );
      final image = tester.widget<RawImage>(images).image!;
      expect(image.width, 2);
      expect(
        backing.http.requests
            .where((r) => r.uri.path.endsWith('/content'))
            .single
            .uri
            .path,
        '/app-api/media/v1/assets/$avatarAsset/content',
      );
      await deps.sessionManager.clear();
      await tester.pump();
      expect(images, findsNothing);
      expect(image.debugDisposed, true);
    },
  );
  testWidgets(
    'open conversation search cannot recreate old descriptors after ABA',
    (tester) async {
      final backing = await AvatarDependencies.create(
        (_) => throw StateError('no HTTP'),
      );
      final deps = _UiDependencies(backing);
      addTearDown(() => backing.close(tester));
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: const MaterialApp(home: MessageCenterPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索消息'));
      await tester.pumpAndSettle();
      expect(find.byType(PresetAvatarView), findsOneWidget);
      await deps.sessionManager.save(avatarSession(2));
      await deps.sessionManager.save(avatarSession(1));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'peer');
      await tester.pump();
      expect(find.byType(PresetAvatarView), findsNothing);
    },
  );
  testWidgets(
    'actual incoming and outgoing bubbles render their own current sender avatar',
    (tester) async {
      final backing = await AvatarDependencies.create(
        (_) => throw StateError('no HTTP'),
      );
      final deps = _UiDependencies(backing);
      deps.messageRepository.messages = [
        for (final mine in [true, false])
          ChatMessage(
            id: mine ? 'mine' : 'peer',
            conversationId: 'conversation',
            senderUserId: mine ? 1 : 2,
            senderName: mine ? 'me' : 'peer',
            content: mine ? 'mine' : 'peer',
            createdAt: DateTime.utc(2026, 9, 10),
            isMine: mine,
            status: ChatMessageStatus.sent,
            senderAvatar: preset(mine ? 'sun' : 'sea'),
            receiverAvatar: preset(mine ? 'sea' : 'sun'),
          ),
      ];
      addTearDown(() => backing.close(tester));
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: deps,
          child: MaterialApp(
            home: PrivateChatPage(conversation: _conversation()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<PresetAvatarView>(find.byType(PresetAvatarView))
            .map((v) => v.presetId),
        containsAll(['avatar-preset-sun', 'avatar-preset-sea']),
      );
      await deps.sessionManager.clear();
      await tester.pump();
      expect(find.byType(PresetAvatarView), findsNothing);
    },
  );
  for (final page in ['personal', 'public', 'mine', 'members', 'room']) {
    testWidgets(
      'actual $page uses formal avatar and retains independent decoration overlay',
      (tester) async {
        final backing = await AvatarDependencies.create(
          (_) => MediaFakeResponse.json({
            ...avatarProfile(),
            'equippedDecorations': [
              {
                'decorationId': frame.decorationId,
                'type': frame.type,
                'assetKey': frame.assetKey,
                'expiresAt': null,
              },
            ],
          }),
        );
        final deps = _UiDependencies(backing);
        final controller = RoomController(
          roomId: 'r',
          title: '',
          currentUserId: 1,
          accessToken: '',
          repository: _Room(),
          rtcAdapter: MockRtcAdapter(),
          realtimeGateway: SnapshotOnlyRoomRealtimeGateway(),
          sessionChanges: deps.sessionManager,
          activeUserId: () => deps.sessionManager.session?.userId,
          identityGeneration: () => deps.sessionManager.identityGeneration,
        );
        if (page == 'room') await controller.join();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await backing.close(tester);
        });
        final Widget child = switch (page) {
          'personal' => PersonalCenterPage(
            session: deps.sessionManager.session,
            onSignOut: () async {},
          ),
          'public' => const PublicProfilePage(userId: 1),
          'mine' => Scaffold(
            body: VideoRuntimeAccountPage(
              dependencies: deps,
              onOpenRoom: (_) {},
              onSignOut: () async {},
            ),
          ),
          'members' => const RoomMembersPage(
            roomId: 'r',
            currentUserId: 1,
            currentRole: RoomRole.listener,
            seats: [],
          ),
          _ => VideoRuntimeRoomPage(controller: controller),
        };
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: deps,
            child: MaterialApp(home: child),
          ),
        );
        for (
          var attempt = 0;
          attempt < 20 && find.byType(PresetAvatarView).evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          });
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.byType(PresetAvatarView), findsWidgets);
        expect(find.byKey(frameKey), findsWidgets);
        expect(
          tester
              .widgetList<PresetAvatarView>(find.byType(PresetAvatarView))
              .every((view) => view.presetId == 'avatar-preset-moon'),
          true,
        );
        await deps.sessionManager.clear();
        await tester.pump();
        expect(find.byType(PresetAvatarView), findsNothing);
      },
    );
  }
  for (final chat in [false, true]) {
    testWidgets(
      'actual ${chat ? "chat header" : "conversation list"} uses descriptor and clears on logout',
      (tester) async {
        final backing = await AvatarDependencies.create(
          (_) => throw StateError('no HTTP'),
        );
        final deps = _UiDependencies(backing);
        addTearDown(() => backing.close(tester));
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: deps,
            child: MaterialApp(
              home: chat
                  ? PrivateChatPage(conversation: _conversation())
                  : const MessageCenterPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PresetAvatarView), findsOneWidget);
        await deps.sessionManager.clear();
        await tester.pump();
        expect(find.byType(PresetAvatarView), findsNothing);
      },
    );
  }
  for (final error in [false, true]) {
    testWidgets(
      'conversation late ${error ? "error" : "success"} across ABA cannot recreate old avatar',
      (tester) async {
        final backing = await AvatarDependencies.create(
          (_) => throw StateError('no HTTP'),
        );
        final deps = _UiDependencies(backing);
        final old = Completer<List<ConversationSummary>>();
        deps.messageRepository.load = () => old.future;
        addTearDown(() => backing.close(tester));
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: deps,
            child: const MaterialApp(home: MessageCenterPage()),
          ),
        );
        await tester.pump();
        await deps.sessionManager.save(avatarSession(2));
        await deps.sessionManager.save(avatarSession(1));
        if (error)
          old.completeError(StateError('OLD-AVATAR-ERROR'));
        else
          old.complete([_conversation()]);
        await tester.pump();
        await tester.pump();
        expect(find.byType(PresetAvatarView), findsNothing);
        expect(find.textContaining('OLD-AVATAR-ERROR'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

ConversationSummary _conversation() => ConversationSummary.draft(
  kind: ConversationKind.privateChat,
  title: 'peer',
  lastMessage: '',
  unreadCount: 0,
  targetUserId: 2,
  avatar: preset('moon'),
);

class _Messages extends MockMessageRepository {
  Future<List<ConversationSummary>> Function() load = () async => [
    _conversation(),
  ];
  @override
  Future<List<ConversationSummary>> fetchConversations() => load();
  List<ChatMessage> messages = [];
  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) async => messages;
}

class _UiDependencies extends Fake implements AppDependencies {
  _UiDependencies(this.backing);
  final AvatarDependencies backing;
  @override
  AuthSessionManager get sessionManager => backing.sessionManager;
  @override
  AppEnvironment get environment => backing.backing.environment;
  @override
  PrivateMediaHost get privateMediaHost => backing.privateMediaHost;
  @override
  late final SocialRepository socialRepository = BackendSocialRepository(
    apiClient: privateMediaHost.api,
    currentUserIdProvider: () => 1,
  );
  @override
  PlatformRoomRepository get platformRoomRepository =>
      backing.backing.platformRoomRepository;
  @override
  final roomOperationsRepository = _Members();
  @override
  final _Messages messageRepository = _Messages();
  @override
  ImAuthoritativeRefreshBus get imAuthoritativeRefreshBus =>
      backing.backing.imAuthoritativeRefreshBus;
  @override
  DateTime Function() get currentTime => backing.backing.currentTime;
}

class _Members extends MockRoomOperationsRepository {
  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async => RoomMemberPage(
    items: [
      RoomMember(
        userId: 2,
        name: 'member',
        role: RoomRole.listener,
        presence: RoomMemberPresence.listener,
        avatar: preset('moon'),
        equippedDecorations: [frame],
      ),
    ],
    page: 1,
    total: 1,
    pages: 1,
  );
}

class _Room extends lease.Repo {
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async =>
      (await super.enterRoom(
        roomId: roomId,
        password: password,
        source: source,
        currentUserId: currentUserId,
      )).copyWith(
        seats: [
          MicSeat(
            number: 1,
            backendIndex: 1,
            state: MicSeatState.occupied,
            userId: 2,
            userName: 'member',
            avatar: preset('moon'),
            equippedDecorations: [frame],
          ),
        ],
      );
}
