import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';

void main() {
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
        currentRole: RoomRole.owner,
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
        role: RoomRole.owner,
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
