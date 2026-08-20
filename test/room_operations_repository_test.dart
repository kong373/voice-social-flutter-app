import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

void main() {
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

    await repository.takeUserOffMic(backendMicIndex: 2, userId: 20002);
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

    await repository.inviteUserToMic(
      roomId: '9527',
      userId: 20005,
      seatNumber: 4,
    );
    final List<MicAccessRequest> requests = await repository.fetchMicRequests(
      '9527',
    );
    expect(requests, hasLength(2));
    final MicAccessRequest pendingInvite = requests.last;
    expect(pendingInvite.status, MicRequestStatus.pending);

    await repository.resolveMicRequest(
      requestId: pendingInvite.id,
      accepted: true,
    );
    expect(
      (await repository.fetchMicRequests('9527')).last.status,
      MicRequestStatus.accepted,
    );
  });
}
