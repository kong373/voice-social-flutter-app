import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

void main() {
  test('room controller keeps eight seats and supports the core flow', () async {
    final RoomController controller = RoomController();
    addTearDown(controller.dispose);

    expect(controller.seats, hasLength(8));
    expect(controller.status, RoomSessionStatus.joined);
    expect(controller.role, RoomRole.listener);

    final bool joinedMic = await controller.requestMic(4);
    expect(joinedMic, isTrue);
    expect(controller.role, RoomRole.speaker);
    expect(
      controller.seats
          .singleWhere((MicSeat seat) => seat.number == 4)
          .userName,
      '我',
    );

    controller.toggleMicrophone();
    expect(controller.micMuted, isTrue);

    final int balanceBefore = controller.giftBalance;
    final bool sent = await controller.sendGift(
      giftName: '玫瑰',
      targetName: '房主 · 鹿屿',
      unitPrice: 10,
      quantity: 1,
    );
    expect(sent, isTrue);
    expect(controller.giftBalance, balanceBefore - 10);

    await controller.leaveRoom();
    expect(controller.status, RoomSessionStatus.left);
  });
}
