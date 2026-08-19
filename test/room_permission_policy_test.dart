import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';

void main() {
  const RoomPermissionPolicy policy = RoomPermissionPolicy();

  RoomSnapshot snapshot(
    RoomRole role, {
    bool giftCatalogAvailable = true,
    RoomTransportMode transportMode = RoomTransportMode.interactive,
  }) => RoomSnapshot(
    roomId: '1',
    roomCode: '1',
    title: '房间',
    topic: '',
    ownerId: 1,
    role: role,
    seats: const <MicSeat>[],
    rtc: const RtcCredentials(
      solution: RtcSolution.agora,
      token: 'token',
      channelId: '1',
      userId: 2,
    ),
    transportMode: transportMode,
    publicScreenEnabled: true,
    pictureMessagesAllowed: false,
    autoLockMic: false,
    giftCatalogAvailable: giftCatalogAvailable,
    giftBalance: 100,
    onlineCount: 1,
  );

  test('listener can socialize but cannot manage the room', () {
    final RoomSnapshot room = snapshot(RoomRole.listener);
    expect(
      policy.allows(
        snapshot: room,
        capability: RoomCapability.sendGift,
        isOnMic: false,
      ),
      isTrue,
    );
    expect(
      policy.allows(
        snapshot: room,
        capability: RoomCapability.manageMembers,
        isOnMic: false,
      ),
      isFalse,
    );
  });

  test('gift capability fails closed without an authoritative catalog', () {
    final RoomSnapshot room = snapshot(
      RoomRole.listener,
      giftCatalogAvailable: false,
    );
    expect(
      policy.allows(
        snapshot: room,
        capability: RoomCapability.sendGift,
        isOnMic: false,
      ),
      isFalse,
    );
  });

  test('owner receives management and close capabilities', () {
    final RoomSnapshot room = snapshot(RoomRole.owner);
    expect(
      policy.allows(
        snapshot: room,
        capability: RoomCapability.manageMembers,
        isOnMic: true,
      ),
      isTrue,
    );
    expect(
      policy.allows(
        snapshot: room,
        capability: RoomCapability.closeRoom,
        isOnMic: true,
      ),
      isTrue,
    );
  });

  test('snapshot-only room denies every interactive capability', () {
    final RoomSnapshot room = snapshot(
      RoomRole.owner,
      transportMode: RoomTransportMode.snapshotOnly,
    );
    for (final RoomCapability capability in RoomCapability.values) {
      expect(
        policy.allows(snapshot: room, capability: capability, isOnMic: true),
        isFalse,
        reason: '$capability must remain fail-closed in snapshot-only mode',
      );
    }
  });
}
