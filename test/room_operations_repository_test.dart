import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

void main() {
  test(
    'S02 uses current target role and never treats staff as room moderator',
    () async {
      final repo = MockRoomOperationsRepository();
      await repo.takeUserOffMic(
        roomId: '9527',
        backendMicIndex: 1,
        userId: 20001,
      );
      repo.seedMemberForQa(
        const RoomMember(
          userId: 30001,
          name: 'staff',
          role: RoomRole.platformModerator,
          presence: RoomMemberPresence.listener,
        ),
      );
      await expectLater(
        repo.assignUserToMic(roomId: '9527', userId: 30001, backendMicIndex: 1),
        throwsA(isA<Exception>()),
      );
      await repo.setUserRole(roomId: '9527', userId: 20004, manager: false);
      await expectLater(
        repo.assignUserToMic(roomId: '9527', userId: 20004, backendMicIndex: 1),
        throwsA(isA<Exception>()),
      );
      expect(
        (await repo.fetchOnlineMembers(
          roomId: '9527',
          page: 1,
        )).items.where((m) => m.seatNumber == 1),
        isEmpty,
      );
    },
  );
  for (final target in [20001, 20004]) {
    test(
      'S02 permits current privileged target $target on special seat without demotion',
      () async {
        final repo = MockRoomOperationsRepository();
        await repo.takeUserOffMic(
          roomId: '9527',
          backendMicIndex: 1,
          userId: 20001,
        );
        await repo.assignUserToMic(
          roomId: '9527',
          userId: target,
          backendMicIndex: 1,
        );
        final member = (await repo.fetchOnlineMembers(
          roomId: '9527',
          page: 1,
        )).items.singleWhere((m) => m.userId == target);
        expect(member.seatNumber, 1);
        expect(
          member.role,
          target == 20001 ? RoomRole.owner : RoomRole.moderator,
        );
        await expectLater(
          repo.assignUserToMic(
            roomId: '9527',
            userId: 20004,
            backendMicIndex: 1,
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          (await repo.fetchOnlineMembers(
            roomId: '9527',
            page: 1,
          )).items.where((m) => m.seatNumber == 1),
          hasLength(1),
        );
      },
    );
  }
  test('S02 rejects ordinary target on empty special seat', () async {
    final repo = MockRoomOperationsRepository();
    await repo.takeUserOffMic(
      roomId: '9527',
      backendMicIndex: 1,
      userId: 20001,
    );
    await expectLater(
      repo.assignUserToMic(roomId: '9527', userId: 20005, backendMicIndex: 1),
      throwsA(isA<Exception>()),
    );
    expect(
      (await repo.fetchOnlineMembers(
        roomId: '9527',
        page: 1,
      )).items.where((m) => m.seatNumber == 1),
      isEmpty,
    );
  });
  test('mock room operations preserve authoritative member changes', () async {
    final MockRoomOperationsRepository repository =
        MockRoomOperationsRepository();

    RoomMemberPage page = await repository.fetchOnlineMembers(
      roomId: '9527',
      page: 1,
    );
    expect(page.total, greaterThan(3));

    await repository.setUserMuted(roomId: '9527', userId: 20005, muted: true);
    expect(
      (await repository.fetchMutedUsers(
        '9527',
      )).any((RoomMember member) => member.userId == 20005),
      isTrue,
    );

    await repository.setUserRole(roomId: '9527', userId: 20005, manager: true);
    expect(
      (await repository.fetchManagers(
        '9527',
      )).any((RoomMember member) => member.userId == 20005),
      isTrue,
    );

    await repository.takeUserOffMic(
      roomId: '9527',
      backendMicIndex: 2,
      userId: 20002,
    );
    page = await repository.fetchOnlineMembers(roomId: '9527', page: 1);
    final RoomMember moved = page.items.firstWhere(
      (RoomMember member) => member.userId == 20002,
    );
    expect(moved.presence, RoomMemberPresence.listener);
    expect(moved.role, RoomRole.listener);

    await repository.kickUser(roomId: '9527', userId: 20006);
    page = await repository.fetchOnlineMembers(roomId: '9527', page: 1);
    expect(
      page.items.any((RoomMember member) => member.userId == 20006),
      isFalse,
    );
  });

  test('topic and consent-based mic coordination remain explicit', () async {
    final MockRoomOperationsRepository repository =
        MockRoomOperationsRepository();
    expect(repository.micCoordinationMode, MicCoordinationMode.approval);

    const RoomTopic topic = RoomTopic(title: '新的话题', content: '请友善交流');
    await repository.updateTopic(roomId: '9527', topic: topic);
    final RoomTopic loaded = await repository.fetchTopic('9527');
    expect(loaded.title, topic.title);
    expect(loaded.content, topic.content);

    await repository.submitMicRequest(
      roomId: '9527',
      userId: 10001,
      seatNumber: 6,
    );
    final MicAccessRequest ownRequest = (await repository.fetchMicRequests(
      '9527',
    )).single;
    expect(ownRequest.status, MicRequestStatus.pending);
    await repository.cancelMicRequest(requestId: ownRequest.id);
    expect(
      (await repository.fetchMicRequests('9527')).single.status,
      MicRequestStatus.cancelled,
    );

    await expectLater(
      repository.inviteUserToMic(roomId: '9527', userId: 20005, seatNumber: 4),
      throwsA(isA<ApiException>()),
    );
    final List<MicAccessRequest> requests = await repository.fetchMicRequests(
      '9527',
    );
    expect(requests, hasLength(1));
    final MicAccessRequest pendingInvite = requests.last;
    expect(pendingInvite.status, MicRequestStatus.cancelled);

    await expectLater(
      repository.resolveMicRequest(
        requestId: pendingInvite.id,
        accepted: true,
        expectedVersion: pendingInvite.version,
      ),
      throwsA(isA<ApiException>()),
    );
    expect(
      (await repository.fetchMicRequests('9527')).last.status,
      MicRequestStatus.cancelled,
    );
  });
}
