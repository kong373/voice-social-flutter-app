import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

void main() {
  test('room controller keeps eight seats and supports the core flow', () async {
    final MockRtcAdapter rtc = MockRtcAdapter();
    final MockRoomRealtimeGateway realtime = MockRoomRealtimeGateway();
    final RoomController controller = RoomController(
      roomId: '880217',
      title: '深夜温柔陪伴',
      currentUserId: 10001,
      accessToken: 'mock-access-token',
      repository: MockRoomRepository(),
      rtcAdapter: rtc,
      realtimeGateway: realtime,
    );
    addTearDown(() async {
      controller.dispose();
      await realtime.dispose();
    });

    expect(controller.seats, hasLength(8));
    expect(controller.status, RoomSessionStatus.idle);

    await controller.join();
    expect(controller.status, RoomSessionStatus.joined);
    expect(controller.seats, hasLength(8));
    expect(controller.role, RoomRole.listener);
    expect(rtc.joined, isTrue);

    final bool joinedMic = await controller.requestMic(4);
    expect(joinedMic, isTrue);
    expect(controller.role, RoomRole.speaker);
    expect(
      controller.seats
          .singleWhere((MicSeat seat) => seat.number == 4)
          .userName,
      '我',
    );

    final bool muted = await controller.toggleMicrophone();
    expect(muted, isTrue);
    expect(controller.micMuted, isTrue);

    final int balanceBefore = controller.giftBalance!;
    final bool sent = await controller.sendGift(
      giftId: 101,
      giftName: '玫瑰',
      receiverUserId: 20001,
      targetName: '房主 · 鹿屿',
      quantity: 1,
    );
    expect(sent, isTrue);
    expect(controller.giftBalance, balanceBefore - 10);

    realtime.emit(
      const RoomRealtimeEvent(
        code: RoomRealtimeEventCodes.publicChat,
        payload: <String, Object?>{
          'userId': 20003,
          'nickname': '晚星',
          'message': '欢迎来到房间',
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.messages.last.content, '欢迎来到房间');

    realtime.emit(
      const RoomRealtimeEvent(
        code: RoomRealtimeEventCodes.mutedInRoom,
        payload: <String, Object?>{},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.mutedInRoom, isTrue);
    expect(controller.canSendPublicMessage, isFalse);
    expect(await controller.sendPublicMessage('这条不应发送'), isFalse);

    realtime.emit(
      const RoomRealtimeEvent(
        code: RoomRealtimeEventCodes.unmutedInRoom,
        payload: <String, Object?>{},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.canSendPublicMessage, isTrue);

    final int messageCount = controller.messages.length;
    realtime.emit(
      const RoomRealtimeEvent(code: 999999, payload: <String, Object?>{}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.messages, hasLength(messageCount));

    await controller.reconnect();
    expect(controller.status, RoomSessionStatus.joined);
    expect(
      controller.messages.last.content,
      '已恢复连接。断线期间公屏消息可能未显示。',
    );

    final bool left = await controller.leaveRoom();
    expect(left, isTrue);
    expect(controller.status, RoomSessionStatus.left);
    expect(rtc.joined, isFalse);
  });
}
