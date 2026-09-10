import 'package:voice_social_app/features/room/domain/room_models.dart';

enum RoomCapability {
  sendPublicMessage,
  requestMic,
  leaveMic,
  toggleMicrophone,
  viewMembers,
  sendGift,
  manageMembers,
  editRoom,
  closeRoom,
  startPk,
}

class RoomPermissionPolicy {
  const RoomPermissionPolicy();

  bool allows({
    required RoomSnapshot snapshot,
    required RoomCapability capability,
    required bool isOnMic,
  }) {
    if (snapshot.closedRoomAccess && !snapshot.ownerClosedAccess) {
      return snapshot.platformStaff &&
          snapshot.canControlRoomLifecycle &&
          capability == RoomCapability.closeRoom;
    }
    if (snapshot.ownerClosedAccess) {
      return snapshot.role == RoomRole.owner &&
          capability == RoomCapability.editRoom;
    }
    // HTTP_STATE_ONLY means only the vendor transports are unavailable. The
    // first-party room routes still own persisted chat, ordinary gifts,
    // direct self mic placement, moderation, topic edits and PK. Keep audio
    // mute itself disabled because it would claim an RTC side effect.
    if (snapshot.isSnapshotOnly) {
      final RoomRole snapshotRole = snapshot.role;
      final bool signedIn = snapshotRole != RoomRole.guest;
      final bool canManage =
          snapshotRole == RoomRole.owner || snapshotRole == RoomRole.moderator;
      return switch (capability) {
        RoomCapability.sendPublicMessage =>
          signedIn && snapshot.publicScreenEnabled,
        RoomCapability.requestMic => signedIn,
        RoomCapability.leaveMic => signedIn && isOnMic,
        RoomCapability.toggleMicrophone => false,
        RoomCapability.viewMembers => true,
        RoomCapability.sendGift => signedIn && snapshot.giftCatalogAvailable,
        RoomCapability.manageMembers => canManage,
        RoomCapability.editRoom => canManage,
        RoomCapability.closeRoom =>
          snapshotRole == RoomRole.owner ||
              (snapshot.platformStaff && snapshot.canControlRoomLifecycle),
        RoomCapability.startPk => canManage,
      };
    }

    final RoomRole role = snapshot.role;
    final bool signedIn = role != RoomRole.guest;
    final bool canManage = role == RoomRole.owner || role == RoomRole.moderator;

    return switch (capability) {
      RoomCapability.sendPublicMessage =>
        signedIn && snapshot.publicScreenEnabled,
      RoomCapability.requestMic => signedIn,
      RoomCapability.leaveMic => signedIn && isOnMic,
      RoomCapability.toggleMicrophone => signedIn && isOnMic,
      RoomCapability.viewMembers => true,
      RoomCapability.sendGift => signedIn && snapshot.giftCatalogAvailable,
      RoomCapability.manageMembers => canManage,
      RoomCapability.editRoom => canManage,
      RoomCapability.closeRoom =>
        role == RoomRole.owner ||
            (snapshot.platformStaff && snapshot.canControlRoomLifecycle),
      RoomCapability.startPk => canManage,
    };
  }
}
