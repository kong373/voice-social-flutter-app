import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';

void main() {
  test('mock closed save stays closed until explicit reopen', () async {
    final repository = MockRoomLifecycleRepository();
    final original = (await repository.fetchOwnedRoom())!;
    await repository.closeRoom(
      original.roomId!,
      expectedVersion: original.version,
    );
    final closed = await repository.fetchRoom(original.roomId!);
    await repository.saveRoom(
      closed.copyWith(
        title: '关闭后修改',
        accessMode: RoomAccessMode.password,
        password: '1234',
      ),
    );
    final saved = await repository.fetchRoom(original.roomId!);
    expect(saved.availability, RoomAvailability.closed);
    expect(saved.title, '关闭后修改');
    expect(saved.accessMode, RoomAccessMode.password);
    await repository.reopenRoom(saved.roomId!, expectedVersion: saved.version!);
    expect((await repository.fetchRoom(saved.roomId!)).isOpen, isTrue);
  });

  test(
    'mock rejects legacy approval without changing stored configuration',
    () async {
      final repository = MockRoomLifecycleRepository();
      final original = (await repository.fetchOwnedRoom())!;
      await expectLater(
        repository.saveRoom(
          original.copyWith(accessMode: RoomAccessMode.approval),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(await repository.fetchOwnedRoom(), same(original));
      expect(repository.capabilities.supportsApprovalAccessMode, isFalse);
    },
  );
}
