// Entry approval coverage is SUPERSEDED_SCOPE by the 2026-09-09 contract.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';

void main() {
  for (final mode in MicCoordinationMode.values) {
    testWidgets('mic queue refreshes without entry reads in $mode', (
      tester,
    ) async {
      final repo = _Repository();
      await _open(tester, repo, mode: mode);
      expect(repo.joinReads, 0);
      expect(repo.micReads, greaterThan(0));
      expect(find.textContaining('入房申请'), findsNothing);
      repo.seedMicRequestForQa(
        MicAccessRequest(
          id: 'request-1',
          member: const RoomMember(
            userId: 20005,
            name: '阿岚',
            role: RoomRole.listener,
            presence: RoomMemberPresence.listener,
          ),
          seatNumber: 4,
          status: MicRequestStatus.pending,
          createdAt: DateTime.now(),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('上麦申请 1'), findsOneWidget);
      await tester.tap(find.text('上麦申请 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同意'));
      await tester.pumpAndSettle();
      expect(find.text('上麦申请 0'), findsOneWidget);
      expect(repo.joinReads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('manager cannot govern owner or managers or appoint', (
    tester,
  ) async {
    final repo = _Repository();
    await _open(tester, repo, role: RoomRole.moderator);
    for (final name in ['房主 · 鹿屿', '清禾']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.text('移出房间'), findsNothing);
      expect(find.text('解除房管'), findsNothing);
      expect(find.text('禁言用户'), findsNothing);
    }
    await tester.tap(find.text('阿岚'));
    await tester.pumpAndSettle();
    expect(find.text('设为房管'), findsNothing);
    expect(find.text('安排上麦'), findsOneWidget);
    await tester.tap(find.text('安排上麦'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 号麦'));
    await tester.pumpAndSettle();
    expect(repo.assignedIndex, 7);
    expect(find.text('已安排 阿岚 上麦'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('owner appoints removes and kicks with ten minute expiry', (
    tester,
  ) async {
    final repo = _Repository();
    await _open(tester, repo);
    await tester.tap(find.text('阿岚'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设为房管'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认任命'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阿岚'));
    await tester.pumpAndSettle();
    expect(find.text('安排上麦'), findsNothing);
    await tester.tap(find.text('解除房管'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认解除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阿岚'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出房间'));
    await tester.pumpAndSettle();
    expect(find.textContaining('10 分钟内不能再次进入本房间'), findsOneWidget);
    await tester.tap(find.text('确认移出并限制'));
    await tester.pumpAndSettle();
    final ban = (await repo.fetchBannedUsers(roomId: '9527')).items.single;
    expect(
      ban.expiresAt!.difference(ban.bannedAt!),
      const Duration(minutes: 10),
    );
    await tester.tap(find.text('房间限制 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解除限制'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认解除'));
    await tester.pumpAndSettle();
    expect(find.text('10 分钟禁入冷却期尚未结束，不能提前解除'), findsOneWidget);
    expect((await repo.fetchBannedUsers(roomId: '9527')).items, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _open(
  WidgetTester tester,
  _Repository repo, {
  RoomRole role = RoomRole.owner,
  MicCoordinationMode mode = MicCoordinationMode.direct,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RoomManagementPage(
        roomId: '9527',
        currentUserId: role == RoomRole.owner ? 20001 : 90000,
        currentRole: role,
        coordinationMode: mode,
        repositoryOverride: repo,
        seats: const [
          MicSeat(number: 4, backendIndex: 7, state: MicSeatState.available),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Repository extends MockRoomOperationsRepository {
  int joinReads = 0;
  int micReads = 0;
  int? assignedIndex;
  @override
  Future<RoomJoinRequestPage> fetchJoinRequests({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async {
    joinReads++;
    throw StateError('Entry approval reads are forbidden');
  }

  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) {
    micReads++;
    return super.fetchMicRequests(roomId);
  }

  @override
  Future<void> assignUserToMic({
    required String roomId,
    required int userId,
    required int backendMicIndex,
  }) async {
    assignedIndex = backendMicIndex;
    await super.assignUserToMic(
      roomId: roomId,
      userId: userId,
      backendMicIndex: backendMicIndex,
    );
  }
}
