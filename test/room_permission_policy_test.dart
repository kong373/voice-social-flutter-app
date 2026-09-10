import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_permission_policy.dart';

void main() {
  const RoomPermissionPolicy policy = RoomPermissionPolicy();

  RoomSnapshot snapshot(
    RoomRole role, {
    bool giftCatalogAvailable = true,
    RoomTransportMode transportMode = RoomTransportMode.interactive,
    bool ownerClosedAccess = false,
    bool closedRoomAccess = false,
    bool platformStaff = false,
  }) => RoomSnapshot(
    roomId: '1',
    roomCode: '1',
    title: '房间',
    topic: '',
    ownerId: 1,
    role: role,
    ownerClosedAccess: ownerClosedAccess,
    closedRoomAccess: closedRoomAccess,
    platformStaff: platformStaff,
    canControlRoomLifecycle: platformStaff,
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

  for (final mode in RoomTransportMode.values) {
    test('PK belongs only to current owner or room manager in $mode', () {
      for (final role in RoomRole.values) {
        expect(
          policy.allows(
            snapshot: snapshot(role, transportMode: mode),
            capability: RoomCapability.startPk,
            isOnMic: false,
          ),
          role == RoomRole.owner || role == RoomRole.moderator,
          reason: role.name,
        );
      }
      for (final role in [RoomRole.owner, RoomRole.moderator]) {
        expect(
          policy.allows(
            snapshot: snapshot(
              role,
              transportMode: mode,
              ownerClosedAccess: true,
            ),
            capability: RoomCapability.startPk,
            isOnMic: true,
          ),
          isFalse,
        );
      }
      expect(
        policy.allows(
          snapshot: snapshot(
            RoomRole.platformModerator,
            transportMode: mode,
            closedRoomAccess: true,
            platformStaff: true,
          ),
          capability: RoomCapability.startPk,
          isOnMic: false,
        ),
        isFalse,
      );
    });
    test('manager can open profile but cannot control lifecycle in $mode', () {
      final room = snapshot(RoomRole.moderator, transportMode: mode);
      expect(
        policy.allows(
          snapshot: room,
          capability: RoomCapability.editRoom,
          isOnMic: false,
        ),
        isTrue,
      );
      expect(
        policy.allows(
          snapshot: room,
          capability: RoomCapability.closeRoom,
          isOnMic: false,
        ),
        isFalse,
      );
      expect(
        policy.allows(
          snapshot: snapshot(RoomRole.listener, transportMode: mode),
          capability: RoomCapability.editRoom,
          isOnMic: false,
        ),
        isFalse,
      );
    });
    test('platform staff cannot govern retained seats in $mode', () {
      expect(
        policy.allows(
          snapshot: snapshot(RoomRole.platformModerator, transportMode: mode),
          capability: RoomCapability.manageMembers,
          isOnMic: false,
        ),
        isFalse,
      );
    });
  }

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

  test('snapshot-only room keeps HTTP capabilities and blocks RTC mute', () {
    final RoomSnapshot room = snapshot(
      RoomRole.owner,
      transportMode: RoomTransportMode.snapshotOnly,
    );
    expect(
      policy.allows(
        snapshot: room,
        capability: RoomCapability.sendPublicMessage,
        isOnMic: false,
      ),
      isTrue,
    );
    expect(
      policy.allows(
        snapshot: room,
        capability: RoomCapability.requestMic,
        isOnMic: false,
      ),
      isTrue,
    );
    expect(
      policy.allows(
        snapshot: room,
        capability: RoomCapability.leaveMic,
        isOnMic: true,
      ),
      isTrue,
    );
    expect(
      policy.allows(
        snapshot: room,
        capability: RoomCapability.toggleMicrophone,
        isOnMic: true,
      ),
      isFalse,
    );
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
        capability: RoomCapability.startPk,
        isOnMic: true,
      ),
      isTrue,
    );
  });
}
