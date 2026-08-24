import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_audio_page.dart';
import 'package:voice_social_app/features/room/presentation/edit_room_page.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';
import 'package:voice_social_app/features/room/presentation/room_topic_page.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';

void main() {
  testWidgets('RM-006 member filters retain on-mic and listener context', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RoomMembersPage(
            roomId: '9527',
            currentUserId: 10001,
            currentRole: RoomRole.listener,
            seats: <MicSeat>[
              MicSeat(
                number: 1,
                backendIndex: 1,
                state: MicSeatState.occupied,
                userId: 20001,
                userName: '房主 · 鹿屿',
                userRole: RoomRole.owner,
              ),
              MicSeat(
                number: 2,
                backendIndex: 2,
                state: MicSeatState.occupiedMuted,
                userId: 20002,
                userName: '南风',
                userRole: RoomRole.speaker,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('在线成员与听众席'), findsOneWidget);
    expect(find.textContaining('麦上'), findsWidgets);
    expect(find.text('房主 · 鹿屿'), findsOneWidget);

    await tester.tap(find.byType(ChoiceChip).at(2));
    await tester.pumpAndSettle();
    expect(find.text('阿岚'), findsOneWidget);
    expect(find.text('房主 · 鹿屿'), findsNothing);
  });

  testWidgets('RM room subpages never invent a sample room title', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RoomMembersPage(
            roomId: '9527',
            currentUserId: 10001,
            currentRole: RoomRole.listener,
            seats: <MicSeat>[],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('房间名称不可用'), findsOneWidget);
    expect(find.text('深夜温柔陪伴'), findsNothing);
  });

  testWidgets('RM-008 persists the authoritative topic before closing', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppDependencies dependencies = AppDependencies.mock();

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          const RoomTopicPage(roomId: '9527', canEdit: true),
                    ),
                  ),
                  child: const Text('打开公告'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开公告'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '公告标题'),
      '今晚只聊轻松的事',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '公告内容'),
      '尊重彼此，不讨论隐私。',
    );
    await tester.tap(find.text('保存公告'));
    await tester.pumpAndSettle();
    expect(find.byType(RoomTopicPage), findsNothing);
  });

  testWidgets(
    'RM-011 topic conflict refreshes authority and waits for resubmit',
    (WidgetTester tester) async {
      final _ConflictRoomTopicRepository repository =
          _ConflictRoomTopicRepository();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: _RouteLauncher(
            buttonLabel: '打开公告',
            pageBuilder: () => RoomTopicPage(
              roomId: '9527',
              canEdit: true,
              roomTitle: '夜聊房',
              repositoryOverride: repository,
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开公告'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '公告标题'),
        '我的新标题',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '公告内容'),
        '我的新内容',
      );

      await tester.tap(find.text('保存公告'));
      await tester.pumpAndSettle();

      expect(repository.updateVersions, <int?>[3]);
      expect(repository.fetchTopicCalls, 2);
      expect(find.byType(RoomTopicPage), findsOneWidget);
      expect(find.textContaining('内容已更新，请重新确认后提交'), findsWidgets);
      expect(find.text('载入最新内容'), findsOneWidget);
      expect(find.textContaining('服务端：服务端新标题'), findsOneWidget);
      expect(find.text('我的新标题'), findsWidgets);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-topic-submit-button')));
      await tester.pumpAndSettle();

      expect(repository.updateVersions, <int?>[3, 4]);
      expect(repository.fetchTopicCalls, 3);
      expect(find.byType(RoomTopicPage), findsNothing);
    },
  );

  testWidgets(
    'RM-012 room save conflict refreshes authority and waits for resubmit',
    (WidgetTester tester) async {
      final _ConflictRoomLifecycleRepository repository =
          _ConflictRoomLifecycleRepository();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: _RouteLauncher(
            buttonLabel: '打开房间设置',
            pageBuilder: () =>
                EditRoomPage(roomId: '9527', repositoryOverride: repository),
          ),
        ),
      );

      await tester.tap(find.text('打开房间设置'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '房间名称'),
        '我的新房间名',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '当前话题或房间说明'),
        '我的新房间内容',
      );

      await tester.tap(find.text('保存房间设置'));
      await tester.pumpAndSettle();

      expect(repository.savedVersions, <int?>[3]);
      expect(repository.fetchRoomCalls, 2);
      expect(find.byType(EditRoomPage), findsOneWidget);
      expect(find.textContaining('内容已更新，请重新确认后提交'), findsWidgets);
      expect(find.text('载入最新内容'), findsOneWidget);
      expect(find.textContaining('服务端：服务端房间标题'), findsOneWidget);
      expect(find.text('我的新房间名'), findsWidgets);

      await tester.tap(find.byKey(const Key('edit-room-save-button')));
      await tester.pumpAndSettle();

      expect(repository.savedVersions, <int?>[3, 4]);
      expect(find.byType(EditRoomPage), findsNothing);
    },
  );

  testWidgets(
    'RM-013 room close conflict refreshes authority and waits for explicit retry',
    (WidgetTester tester) async {
      final _ConflictRoomLifecycleRepository repository =
          _ConflictRoomLifecycleRepository();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: _RouteLauncher(
            buttonLabel: '打开房间设置',
            pageBuilder: () =>
                EditRoomPage(roomId: '9527', repositoryOverride: repository),
          ),
        ),
      );

      await tester.tap(find.text('打开房间设置'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-room-close-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认关闭'));
      await tester.pumpAndSettle();

      expect(repository.closedVersions, <int?>[3]);
      expect(repository.fetchRoomCalls, 2);
      expect(find.byType(EditRoomPage), findsOneWidget);
      expect(find.textContaining('内容已更新，请重新确认后提交'), findsWidgets);
      expect(find.text('载入最新内容'), findsOneWidget);
      expect(
        find.byKey(const Key('edit-room-close-retry-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('edit-room-close-retry-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认关闭'));
      await tester.pumpAndSettle();

      expect(repository.closedVersions, <int?>[3, 4]);
      expect(find.byType(EditRoomPage), findsNothing);
    },
  );

  testWidgets('RM-010 exposes only available audio routes', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock();
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RoomAudioPage(isOnMic: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('扬声器'), findsOneWidget);
    expect(find.text('蓝牙设备'), findsOneWidget);
    expect(find.text('有线耳机'), findsOneWidget);
    final ListTile wired = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '有线耳机'),
    );
    expect(wired.enabled, isFalse);
  });

  testWidgets('RM-007 exposes first-party approval and ban recovery actions', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.mock();
    final MockRoomOperationsRepository repository =
        dependencies.roomOperationsRepository as MockRoomOperationsRepository;
    repository.seedJoinRequestForQa(
      RoomJoinRequest(
        id: 'join-request-1',
        member: const RoomMember(
          userId: 30001,
          name: '申请用户',
          role: RoomRole.listener,
          presence: RoomMemberPresence.listener,
        ),
        status: RoomJoinRequestStatus.pending,
        message: '想加入房间聊天',
        createdAt: DateTime.utc(2026, 8, 25),
      ),
    );
    repository.seedBannedUserForQa(
      const RoomBannedUser(
        member: RoomMember(
          userId: 30002,
          name: '受限用户',
          role: RoomRole.listener,
          presence: RoomMemberPresence.listener,
        ),
        reason: '重复刷屏',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RoomManagementPage(
            roomId: '9527',
            currentUserId: 20001,
            currentRole: RoomRole.owner,
            seats: <MicSeat>[],
            roomTitle: '夜聊房',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('入房申请 1'), findsOneWidget);
    expect(find.text('房间限制 1'), findsOneWidget);

    await tester.tap(find.text('入房申请 1'));
    await tester.pumpAndSettle();
    expect(find.text('申请用户'), findsOneWidget);
    expect(find.text('同意'), findsOneWidget);
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();
    final RoomJoinRequestPage resolved = await repository.fetchJoinRequests(
      roomId: '9527',
    );
    expect(resolved.items.single.status, RoomJoinRequestStatus.approved);

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-320, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('房间限制 1'));
    await tester.pumpAndSettle();
    expect(find.text('受限用户'), findsOneWidget);
    await tester.tap(find.text('解除限制'));
    await tester.pumpAndSettle();
    expect(find.text('确认解除'), findsOneWidget);
    await tester.tap(find.text('确认解除'));
    await tester.pumpAndSettle();
    expect(find.text('受限用户'), findsNothing);
  });
}

class _RouteLauncher extends StatelessWidget {
  const _RouteLauncher({required this.buttonLabel, required this.pageBuilder});

  final String buttonLabel;
  final Widget Function() pageBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => pageBuilder(),
            ),
          ),
          child: Text(buttonLabel),
        ),
      ),
    );
  }
}

class _ConflictRoomTopicRepository implements RoomOperationsRepository {
  RoomTopic _authoritative = const RoomTopic(
    title: '服务端新标题',
    content: '服务端新内容',
    version: 4,
  );

  int fetchTopicCalls = 0;
  final List<int?> updateVersions = <int?>[];

  @override
  MicCoordinationMode get micCoordinationMode => MicCoordinationMode.direct;

  @override
  Future<RoomTopic> fetchTopic(String roomId) async {
    fetchTopicCalls += 1;
    if (fetchTopicCalls == 1) {
      return const RoomTopic(title: '旧标题', content: '旧内容', version: 3);
    }
    return _authoritative;
  }

  @override
  Future<void> updateTopic({
    required String roomId,
    required RoomTopic topic,
  }) async {
    updateVersions.add(topic.version);
    if (updateVersions.length == 1) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40945,
        message: 'ROOM_VERSION_CONFLICT',
      );
    }
    _authoritative = RoomTopic(
      title: topic.title,
      content: topic.content,
      version: (topic.version ?? 0) + 1,
    );
  }

  @override
  Future<List<RoomMember>> fetchOffMicListeners(String roomId) async =>
      throw UnimplementedError();

  @override
  Future<List<RoomMember>> fetchManagers(String roomId) async =>
      throw UnimplementedError();

  @override
  Future<List<RoomMember>> fetchMutedUsers(String roomId) async =>
      throw UnimplementedError();

  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    required int page,
    int pageSize = 20,
  }) async => throw UnimplementedError();

  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) async =>
      throw UnimplementedError();

  @override
  Future<void> inviteUserToMic({
    required String roomId,
    required int userId,
    required int seatNumber,
  }) async => throw UnimplementedError();

  @override
  Future<void> kickUser({required String roomId, required int userId}) async =>
      throw UnimplementedError();

  @override
  Future<void> cancelMicRequest({required String requestId}) async =>
      throw UnimplementedError();

  @override
  Future<void> resolveMicRequest({
    required String requestId,
    required bool accepted,
  }) async => throw UnimplementedError();

  @override
  Future<void> setSeatLocked({
    required String roomId,
    required int backendMicIndex,
    required bool locked,
  }) async => throw UnimplementedError();

  @override
  Future<void> setSeatMuted({
    required String roomId,
    required int backendMicIndex,
    required bool muted,
  }) async => throw UnimplementedError();

  @override
  Future<void> setUserMuted({
    required String roomId,
    required int userId,
    required bool muted,
  }) async => throw UnimplementedError();

  @override
  Future<void> setUserRole({
    required String roomId,
    required int userId,
    required bool manager,
  }) async => throw UnimplementedError();

  @override
  Future<void> submitMicRequest({
    required String roomId,
    required int userId,
    required int seatNumber,
  }) async => throw UnimplementedError();

  @override
  Future<void> takeUserOffMic({
    required String roomId,
    required int backendMicIndex,
    required int userId,
  }) async => throw UnimplementedError();
}

class _ConflictRoomLifecycleRepository implements RoomLifecycleRepository {
  static const RoomConfiguration _initial = RoomConfiguration(
    roomId: '9527',
    roomCode: 'R9527',
    title: '旧房间标题',
    topicTitle: '旧话题标题',
    topicContent: '旧话题内容',
    welcomeMessage: '旧欢迎语',
    accessMode: RoomAccessMode.publicRoom,
    password: '',
    showInHall: true,
    autoLockMic: false,
    availability: RoomAvailability.open,
    version: 3,
  );

  static const RoomConfiguration _refreshed = RoomConfiguration(
    roomId: '9527',
    roomCode: 'R9527',
    title: '服务端房间标题',
    topicTitle: '服务端话题标题',
    topicContent: '服务端话题内容',
    welcomeMessage: '服务端欢迎语',
    accessMode: RoomAccessMode.publicRoom,
    password: '',
    showInHall: true,
    autoLockMic: false,
    availability: RoomAvailability.open,
    version: 4,
  );

  RoomConfiguration _authoritative = _refreshed;
  int fetchRoomCalls = 0;
  final List<int?> savedVersions = <int?>[];
  final List<int?> closedVersions = <int?>[];

  @override
  final RoomLifecycleCapabilities capabilities =
      const RoomLifecycleCapabilities(
        supportsApprovalAccessMode: true,
        supportsTopicTitle: true,
        supportsAutoLockMic: true,
        supportsReopen: true,
      );

  @override
  Future<RoomConfiguration?> fetchOwnedRoom() async => _authoritative;

  @override
  Future<RoomConfiguration> fetchRoom(String roomId) async {
    fetchRoomCalls += 1;
    if (fetchRoomCalls == 1) {
      return _initial;
    }
    return _authoritative;
  }

  @override
  Future<RoomLifecycleSaveResult> saveRoom(
    RoomConfiguration configuration,
  ) async {
    savedVersions.add(configuration.version);
    if (savedVersions.length == 1) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40945,
        message: 'ROOM_VERSION_CONFLICT',
      );
    }
    _authoritative = configuration.copyWith(
      version: (configuration.version ?? 0) + 1,
    );
    return const RoomLifecycleSaveResult(
      roomId: '9527',
      roomCode: 'R9527',
      created: false,
    );
  }

  @override
  Future<void> closeRoom(String roomId, {int? expectedVersion}) async {
    closedVersions.add(expectedVersion);
    if (closedVersions.length == 1) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40945,
        message: 'ROOM_VERSION_CONFLICT',
      );
    }
    _authoritative = _authoritative.copyWith(
      availability: RoomAvailability.closed,
      version: (expectedVersion ?? _authoritative.version ?? 0) + 1,
    );
  }

  @override
  Future<RoomLinkResolution> resolveRoomLink(String input) async =>
      throw UnimplementedError();
}
