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
    // HTTP_STATE_ONLY means only the vendor transports are unavailable. The
    // first-party room routes still own persisted chat, ordinary gifts,
    // direct self mic placement, moderation, topic edits and PK. Keep audio
    // mute itself disabled because it would claim an RTC side effect.
    if (snapshot.isSnapshotOnly) {
      final RoomRole snapshotRole = snapshot.role;
      final bool signedIn = snapshotRole != RoomRole.guest;
      final bool canManage =
          snapshotRole == RoomRole.owner ||
          snapshotRole == RoomRole.moderator ||
          snapshotRole == RoomRole.platformModerator;
      return switch (capability) {
        RoomCapability.sendPublicMessage =>
          signedIn && snapshot.publicScreenEnabled,
        RoomCapability.requestMic => signedIn && !isOnMic,
        RoomCapability.leaveMic => signedIn && isOnMic,
        RoomCapability.toggleMicrophone => false,
        RoomCapability.viewMembers => true,
        RoomCapability.sendGift => signedIn && snapshot.giftCatalogAvailable,
        RoomCapability.manageMembers => canManage,
        RoomCapability.editRoom => snapshotRole == RoomRole.owner,
        RoomCapability.closeRoom => snapshotRole == RoomRole.owner,
        RoomCapability.startPk => snapshotRole == RoomRole.owner,
      };
    }

    final RoomRole role = snapshot.role;
    final bool signedIn = role != RoomRole.guest;
    final bool canManage =
        role == RoomRole.owner ||
        role == RoomRole.moderator ||
        role == RoomRole.platformModerator;

    return switch (capability) {
      RoomCapability.sendPublicMessage =>
        signedIn && snapshot.publicScreenEnabled,
      RoomCapability.requestMic => signedIn && !isOnMic,
      RoomCapability.leaveMic => signedIn && isOnMic,
      RoomCapability.toggleMicrophone => signedIn && isOnMic,
      RoomCapability.viewMembers => true,
      RoomCapability.sendGift => signedIn && snapshot.giftCatalogAvailable,
      RoomCapability.manageMembers => canManage,
      RoomCapability.editRoom => role == RoomRole.owner,
      RoomCapability.closeRoom => role == RoomRole.owner,
      RoomCapability.startPk => role == RoomRole.owner,
    };
  }
}
