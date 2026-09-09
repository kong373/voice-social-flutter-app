import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';

void main() {
  testWidgets('S05 absent seat role uses complete offline manager roster', (
    tester,
  ) async {
    final repo = _Repository()..role = RoomRole.moderator;
    repo.extraManagers = const [
      RoomMember(
        userId: 999,
        name: '离线房管',
        role: RoomRole.moderator,
        presence: RoomMemberPresence.onMic,
        seatNumber: 4,
      ),
    ];
    repo.seats = const [
      MicSeat(
        number: 4,
        backendIndex: 0,
        state: MicSeatState.occupied,
        userId: 999,
        userName: '离线房管',
        isOnline: false,
      ),
    ];
    await _open(tester, repo);
    await tester.tap(find.text('麦位管理'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, '移下麦位'), findsNothing);
    expect(find.widgetWithText(ActionChip, '移出房间'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('S05 failed offline kick retains authority seat', (tester) async {
    final repo = _Repository();
    repo.seats = const [
      MicSeat(
        number: 4,
        backendIndex: 0,
        state: MicSeatState.occupied,
        userId: 999,
        userName: '离线成员',
        isOnline: false,
      ),
    ];
    await _open(tester, repo);
    await tester.tap(find.text('麦位管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, '移出房间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移出并限制'));
    await tester.pumpAndSettle();
    expect(repo.kicked, 999);
    expect(find.text('离线成员'), findsOneWidget);
    expect(find.text('离线 · 占位保留'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final targetRole in [RoomRole.owner, RoomRole.moderator]) {
    testWidgets('S05 manager cannot govern offline $targetRole', (
      tester,
    ) async {
      final repo = _Repository()..role = RoomRole.moderator;
      repo.seats = [
        MicSeat(
          number: 4,
          backendIndex: 0,
          state: MicSeatState.occupied,
          userId: 999,
          userName: '离线管理',
          userRole: targetRole,
          isOnline: false,
        ),
      ];
      await _open(tester, repo);
      await tester.tap(find.text('麦位管理'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, '移下麦位'), findsNothing);
      expect(find.widgetWithText(ActionChip, '移出房间'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final role in [
    RoomRole.owner,
    RoomRole.moderator,
    RoomRole.listener,
    RoomRole.platformModerator,
  ]) {
    testWidgets('S05 offline seat governance as $role', (tester) async {
      final repo = _Repository()..role = role;
      repo.seats = const [
        MicSeat(
          number: 4,
          backendIndex: 0,
          state: MicSeatState.occupied,
          userId: 999,
          userName: '离线成员',
          isOnline: false,
        ),
      ];
      await _open(tester, repo);
      await tester.tap(find.text('麦位管理'));
      await tester.pumpAndSettle();
      expect(find.text('离线成员'), findsOneWidget);
      expect(find.text('离线 · 占位保留'), findsOneWidget);
      final allowed = role == RoomRole.owner || role == RoomRole.moderator;
      expect(
        find.widgetWithText(ActionChip, '移下麦位'),
        allowed ? findsOneWidget : findsNothing,
      );
      expect(
        find.widgetWithText(ActionChip, '移出房间'),
        allowed ? findsOneWidget : findsNothing,
      );
      if (allowed) {
        await tester.tap(find.widgetWithText(ActionChip, '移下麦位'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认移下麦'));
        await tester.pumpAndSettle();
        expect(repo.removed, (999, 0));
        expect(find.text('离线成员'), findsNothing);
      } else {
        expect(repo.removed, isNull);
        for (final chip in tester.widgetList<ActionChip>(
          find.byType(ActionChip),
        )) {
          expect(chip.onPressed, isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'assignment refreshes auto-locked seats and excludes them from the next picker',
    (tester) async {
      final repo = _Repository();
      await _open(tester, repo);
      await tester.tap(find.text('阿岚'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('安排上麦'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 号麦'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('麦位管理'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, '解锁'), findsOneWidget);
      await tester.tap(find.text('成员治理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('阿岚'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('安排上麦'));
      await tester.pumpAndSettle();
      expect(find.text('当前没有可安排的空麦位'), findsOneWidget);
      expect(repo.reads, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'manual refresh uses authoritative empty seat locks and occupied seats absent from member page',
    (tester) async {
      final repo = _Repository();
      await _open(tester, repo);
      repo.seats = const [
        MicSeat(number: 4, backendIndex: 4, state: MicSeatState.locked),
        MicSeat(
          number: 5,
          backendIndex: 5,
          state: MicSeatState.occupied,
          userId: 999,
          userName: '分页外成员',
        ),
      ];
      await tester.tap(find.byTooltip('刷新权威状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('麦位管理'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, '解锁'), findsOneWidget);
      expect(find.text('分页外成员'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed authority refresh shows error instead of actionable stale seats and recovers',
    (tester) async {
      final repo = _Repository();
      await _open(tester, repo);
      repo.failRead = true;
      await tester.tap(find.byTooltip('刷新权威状态'));
      await tester.pumpAndSettle();
      expect(find.text('麦位权威读取失败'), findsOneWidget);
      expect(find.text('阿岚'), findsNothing);
      repo.failRead = false;
      repo.seats = const [
        MicSeat(number: 4, backendIndex: 4, state: MicSeatState.locked),
      ];
      await tester.tap(find.byTooltip('刷新权威状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('麦位管理'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, '解锁'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'historical restrictions show actual expiry or no expiry, not kick duration',
    (tester) async {
      final repo = _Repository();
      await _open(tester, repo);
      await tester.tap(find.text('房间限制 2'));
      await tester.pumpAndSettle();
      expect(find.text('无期限'), findsOneWidget);
      expect(find.text('限制至 2030-01-02 03:04'), findsOneWidget);
      expect(find.textContaining('10 分钟'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _open(WidgetTester tester, _Repository repo) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RoomManagementPage(
        roomId: '9527',
        currentUserId: 20001,
        currentRole: repo.role,
        seats: List.of(repo.seats),
        repositoryOverride: repo,
        authorityRepositoryOverride: repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Repository extends MockRoomOperationsRepository
    implements RoomAuthorityRepository {
  int reads = 0;
  bool failRead = false;
  RoomRole role = RoomRole.owner;
  (int, int)? removed;
  int? kicked;
  List<RoomMember> extraManagers = [];

  @override
  Future<List<RoomMember>> fetchManagers(String roomId) async => [
    ...await super.fetchManagers(roomId),
    ...extraManagers,
  ];

  @override
  Future<void> kickUser({required String roomId, required int userId}) async {
    kicked = userId;
    throw const ApiException(
      kind: ApiFailureKind.business,
      code: 40936,
      message: 'ROOM_SESSION_EXPIRED',
    );
  }

  @override
  Future<void> takeUserOffMic({
    required String roomId,
    required int userId,
    required int backendMicIndex,
  }) async {
    removed = (userId, backendMicIndex);
    seats = [
      for (final seat in seats)
        if (seat.userId == userId)
          MicSeat(
            number: seat.number,
            backendIndex: seat.backendIndex,
            state: MicSeatState.available,
          )
        else
          seat,
    ];
  }

  List<MicSeat> seats = const [
    MicSeat(number: 4, backendIndex: 4, state: MicSeatState.available),
    MicSeat(number: 5, backendIndex: 5, state: MicSeatState.available),
  ];

  @override
  Future<RoomAuthorityProjection> fetchRoomAuthority({
    required String roomId,
    required int currentUserId,
  }) async {
    reads++;
    if (failRead)
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: '麦位权威读取失败',
      );
    return RoomAuthorityProjection(
      snapshot: RoomSnapshot(
        roomId: roomId,
        roomCode: roomId,
        title: '房间',
        topic: '',
        ownerId: currentUserId,
        role: role,
        seats: List.of(seats),
        rtc: const RtcCredentials(token: '', channelId: ''),
        publicScreenEnabled: false,
        pictureMessagesAllowed: false,
        autoLockMic: true,
        giftCatalogAvailable: false,
        giftBalance: 0,
      ),
      viewerUserId: currentUserId,
      memberActive: true,
      roomMuted: false,
      version: reads,
    );
  }

  @override
  Future<void> assignUserToMic({
    required String roomId,
    required int userId,
    required int backendMicIndex,
  }) async {
    // Keep the independently paginated member response stale: it is not seat authority.
    seats = [
      for (final seat in seats)
        seat.backendIndex == backendMicIndex
            ? MicSeat(
                number: seat.number,
                backendIndex: seat.backendIndex,
                state: MicSeatState.occupied,
                userId: userId,
                userName: '阿岚',
              )
            : MicSeat(
                number: seat.number,
                backendIndex: seat.backendIndex,
                state: MicSeatState.locked,
              ),
    ];
  }

  @override
  Future<RoomBannedUserPage> fetchBannedUsers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async => RoomBannedUserPage(
    items: [
      const RoomBannedUser(
        member: RoomMember(
          userId: 80,
          name: '历史无期限制',
          role: RoomRole.listener,
          presence: RoomMemberPresence.listener,
        ),
      ),
      RoomBannedUser(
        member: const RoomMember(
          userId: 81,
          name: '历史长期限制',
          role: RoomRole.listener,
          presence: RoomMemberPresence.listener,
        ),
        expiresAt: DateTime(2030, 1, 2, 3, 4),
      ),
    ],
    page: 1,
    total: 2,
    pages: 1,
  );
}
