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
    // The M3.2A room is an authoritative HTTP snapshot only. Every action
    // that would require room membership, an online-member service, RTC, IM,
    // gifts or moderation remains disabled until its real service is wired.
    if (snapshot.isSnapshotOnly) {
      return false;
    }

    final RoomRole role = snapshot.role;
    final bool signedIn = role != RoomRole.guest;
    final bool canManage = role == RoomRole.owner ||
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
