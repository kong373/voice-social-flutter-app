import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';

void main() {
  test('mock owned closed room stays closed until explicit reopen', () async {
    final lifecycle = MockRoomLifecycleRepository();
    final owned = (await lifecycle.fetchOwnedRoom())!;
    await lifecycle.closeRoom(owned.roomId!, expectedVersion: owned.version);
    final repository = MockRoomRepository(lifecycleRepository: lifecycle);
    final closed = await repository.enterRoom(
      roomId: owned.roomId!,
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10001,
    );
    expect(closed.ownerClosedAccess, isTrue);
    expect(closed.role, RoomRole.owner);
    expect(closed.ownerId, 10001);
    expect(closed.roomLease, isNull);
    expect((await lifecycle.fetchOwnedRoom())!.isOpen, isFalse);
    final saved = (await lifecycle.fetchOwnedRoom())!;
    await lifecycle.reopenRoom(owned.roomId!, expectedVersion: saved.version!);
    final reopened = await repository.enterRoom(
      roomId: owned.roomId!,
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10001,
    );
    expect(reopened.ownerClosedAccess, isFalse);
  });
  for (final mode in ['PUBLIC', 'PASSWORD', 'APPROVAL']) {
    for (final role in [
      RoomRole.listener,
      RoomRole.owner,
      RoomRole.moderator,
    ]) {
      test('$role microphone policy independent of $mode entry', () async {
        final repository = _Room(mode)..seedEntryRoleForQa(role);
        final operations = MockRoomOperationsRepository();
        final realtime = MockRoomRealtimeGateway();
        final controller = RoomController(
          roomId: '9527',
          title: '房间',
          currentUserId: 10001,
          accessToken: 'test',
          repository: repository,
          rtcAdapter: const SnapshotOnlyRtcAdapter(),
          realtimeGateway: realtime,
          roomOperationsRepository: operations,
        );
        addTearDown(() async {
          controller.dispose();
          await realtime.dispose();
        });
        await controller.join();
        final ordinary = role == RoomRole.listener;
        expect(
          controller.micCoordinationMode,
          ordinary ? MicCoordinationMode.approval : MicCoordinationMode.direct,
        );
        expect(await controller.requestMic(4), isTrue);
        expect(repository.selfUpCalls, ordinary ? 0 : 1);
        final requests = await operations.fetchMicRequests('9527');
        expect(requests.length, ordinary ? 1 : 0);
        if (ordinary) {
          expect(controller.isOnMic, isFalse);
          expect(requests.single.status, MicRequestStatus.pending);
        } else {
          expect(controller.role, role);
        }
      });
    }
  }
}

class _Room extends MockRoomRepository {
  _Room(this.mode);
  final String mode;
  int selfUpCalls = 0;
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => (await super.enterRoom(
    roomId: roomId,
    password: password,
    source: source,
    currentUserId: currentUserId,
  )).copyWith(accessMode: mode, transportMode: RoomTransportMode.snapshotOnly);
  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async => (await super.reconnectRoom(
    roomId: roomId,
    currentUserId: currentUserId,
  )).copyWith(accessMode: mode, transportMode: RoomTransportMode.snapshotOnly);
  @override
  Future<void> requestMic(int backendMicIndex) async {
    selfUpCalls++;
    await super.requestMic(backendMicIndex);
  }
}
