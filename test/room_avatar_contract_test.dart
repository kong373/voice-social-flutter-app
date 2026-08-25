import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

void main() {
  test('mock room seats carry explicit local avatar fixtures', () async {
    final RoomSnapshot snapshot = await MockRoomRepository().enterRoom(
      roomId: '880217',
      password: null,
      source: RoomEntrySource.home,
      currentUserId: 10001,
    );

    expect(
      snapshot.seats
          .where((MicSeat seat) => seat.isOccupied)
          .map((MicSeat seat) => seat.avatarUrl),
      <String?>[
        'assets/runtime/avatar-copper.png',
        'assets/runtime/avatar-rose.png',
        'assets/runtime/avatar-copper.png',
        'assets/runtime/avatar-copper.png',
        'assets/runtime/avatar-rose.png',
        'assets/runtime/avatar-copper.png',
        'assets/runtime/avatar-rose.png',
      ],
    );
  });

  testWidgets('live empty avatar stays unavailable instead of a fake image', (
    WidgetTester tester,
  ) async {
    final RoomController controller = RoomController(
      roomId: 'live-room',
      title: '服务端房间快照',
      currentUserId: 10001,
      accessToken: 'test-token',
      repository: _LiveEmptyAvatarRepository(),
      rtcAdapter: const SnapshotOnlyRtcAdapter(),
      realtimeGateway: const SnapshotOnlyRoomRealtimeGateway(),
    );
    addTearDown(controller.dispose);
    await controller.join();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.room(),
        home: VideoRuntimeRoomPage(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.person_outline_rounded), findsAtLeastNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

class _LiveEmptyAvatarRepository extends MockRoomRepository {
  static final RoomSnapshot _snapshot = RoomSnapshot(
    roomId: 'live-room',
    roomCode: 'live-room',
    title: '服务端房间快照',
    topic: '只展示已确认的房间信息',
    ownerId: 20001,
    role: RoomRole.listener,
    seats: <MicSeat>[
      const MicSeat(
        number: 1,
        backendIndex: 1,
        state: MicSeatState.occupied,
        userId: 20001,
        userName: '服务端成员',
      ),
      for (int number = 2; number <= 8; number += 1)
        MicSeat(
          number: number,
          backendIndex: number,
          state: MicSeatState.available,
        ),
    ],
    rtc: const RtcCredentials(
      solution: RtcSolution.unknown,
      token: '',
      channelId: '',
      userId: 10001,
    ),
    transportMode: RoomTransportMode.snapshotOnly,
    publicScreenEnabled: false,
    pictureMessagesAllowed: false,
    autoLockMic: true,
    giftCatalogAvailable: false,
    giftBalance: null,
    onlineCount: null,
  );

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async => _snapshot;

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async => _snapshot;
}
