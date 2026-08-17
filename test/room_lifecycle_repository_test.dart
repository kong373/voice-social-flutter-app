import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';

void main() {
  test('room lifecycle saves, closes, and resolves without vendor SDKs', () async {
    final MockRoomLifecycleRepository repository =
        MockRoomLifecycleRepository();
    final RoomConfiguration room = (await repository.fetchOwnedRoom())!;

    final RoomLifecycleSaveResult result = await repository.saveRoom(
      room.copyWith(
        title: '新的房间名称',
        topicContent: '只测试平台业务状态。',
        accessMode: RoomAccessMode.password,
        password: '2468',
      ),
    );
    expect(result.roomId, room.roomId);
    expect((await repository.fetchRoom(result.roomId)).title, '新的房间名称');

    RoomLinkResolution resolution =
        await repository.resolveRoomLink('voice-social://room/${result.roomId}');
    expect(resolution.canEnter, isTrue);

    await repository.closeRoom(result.roomId);
    resolution = await repository.resolveRoomLink(result.roomId);
    expect(resolution.status, RoomLinkStatus.closed);
  });

  test('password rooms require four numeric digits', () async {
    final MockRoomLifecycleRepository repository =
        MockRoomLifecycleRepository();
    final RoomConfiguration room = (await repository.fetchOwnedRoom())!;

    await expectLater(
      repository.saveRoom(
        room.copyWith(
          accessMode: RoomAccessMode.password,
          password: '12',
        ),
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
