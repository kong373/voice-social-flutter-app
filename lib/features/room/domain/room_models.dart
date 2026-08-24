enum RoomRole { guest, listener, speaker, moderator, owner, platformModerator }

enum RoomSessionStatus {
  idle,
  joining,
  joined,
  reconnecting,
  leaving,
  left,
  closed,
  kicked,
  failed,
}

enum MicSeatState { available, locked, mutedAvailable, occupied, occupiedMuted }

enum RtcSolution { agora, zego, unknown }

enum RoomTransportMode { interactive, snapshotOnly }

enum RoomEntrySource {
  home(0),
  follow(1),
  search(2),
  loginRestore(3),
  share(4),
  campaign(5),
  guild(6),
  registrationRecommendation(7),
  groupMembers(8),
  friends(9),
  discoveryPost(10),
  leaderboard(11),
  guildRoomList(12),
  hotRanking(13),
  giftContext(14),
  publicProfile(15),
  message(19);

  const RoomEntrySource(this.backendCode);

  final int backendCode;
}

class RtcCredentials {
  const RtcCredentials({
    required this.solution,
    required this.token,
    required this.channelId,
    required this.userId,
  });

  final RtcSolution solution;
  final String token;
  final String channelId;
  final int userId;
}

class MicSeat {
  const MicSeat({
    required this.number,
    required this.backendIndex,
    required this.state,
    this.userId,
    this.userName,
    this.avatarUrl,
    this.isSpeaking = false,
    this.userRole = RoomRole.listener,
  });

  final int number;
  final int backendIndex;
  final MicSeatState state;
  final int? userId;
  final String? userName;
  final String? avatarUrl;
  final bool isSpeaking;
  final RoomRole userRole;

  bool get isAvailable => state == MicSeatState.available;

  bool get isOccupied =>
      state == MicSeatState.occupied || state == MicSeatState.occupiedMuted;

  MicSeat copyWith({
    int? backendIndex,
    MicSeatState? state,
    int? userId,
    bool clearUserId = false,
    String? userName,
    bool clearUserName = false,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    bool? isSpeaking,
    RoomRole? userRole,
  }) {
    return MicSeat(
      number: number,
      backendIndex: backendIndex ?? this.backendIndex,
      state: state ?? this.state,
      userId: clearUserId ? null : userId ?? this.userId,
      userName: clearUserName ? null : userName ?? this.userName,
      avatarUrl: clearAvatarUrl ? null : avatarUrl ?? this.avatarUrl,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      userRole: userRole ?? this.userRole,
    );
  }
}

class RoomMessage {
  const RoomMessage({
    required this.sender,
    required this.content,
    this.roomId,
    this.messageId,
    this.senderId,
    this.type,
    this.isSystem = false,
    this.createdAt,
    this.deliveryMode,
    this.realtimeStatus,
  });

  final String? roomId;
  final String? messageId;
  final int? senderId;
  final String sender;
  final String? type;
  final String content;
  final bool isSystem;
  final DateTime? createdAt;
  final String? deliveryMode;
  final String? realtimeStatus;
}

class RoomSnapshot {
  const RoomSnapshot({
    required this.roomId,
    required this.roomCode,
    required this.title,
    required this.topic,
    required this.ownerId,
    required this.role,
    required this.seats,
    required this.rtc,
    required this.publicScreenEnabled,
    required this.pictureMessagesAllowed,
    required this.autoLockMic,
    required this.giftCatalogAvailable,
    required this.giftBalance,
    this.transportMode = RoomTransportMode.interactive,
    this.onlineCount,
    this.coverUrl,
    this.backgroundUrl,
  });

  final String roomId;
  final String roomCode;
  final String title;
  final String topic;
  final int ownerId;
  final RoomRole role;
  final List<MicSeat> seats;
  final RtcCredentials rtc;
  final RoomTransportMode transportMode;
  final bool publicScreenEnabled;
  final bool pictureMessagesAllowed;
  final bool autoLockMic;
  final bool giftCatalogAvailable;
  final int? giftBalance;
  final int? onlineCount;
  final String? coverUrl;
  final String? backgroundUrl;

  bool get isSnapshotOnly => transportMode == RoomTransportMode.snapshotOnly;

  RoomSnapshot copyWith({
    String? title,
    String? topic,
    RoomRole? role,
    List<MicSeat>? seats,
    RtcCredentials? rtc,
    RoomTransportMode? transportMode,
    bool? publicScreenEnabled,
    bool? pictureMessagesAllowed,
    bool? autoLockMic,
    bool? giftCatalogAvailable,
    int? giftBalance,
    int? onlineCount,
  }) {
    return RoomSnapshot(
      roomId: roomId,
      roomCode: roomCode,
      title: title ?? this.title,
      topic: topic ?? this.topic,
      ownerId: ownerId,
      role: role ?? this.role,
      seats: seats ?? this.seats,
      rtc: rtc ?? this.rtc,
      transportMode: transportMode ?? this.transportMode,
      publicScreenEnabled: publicScreenEnabled ?? this.publicScreenEnabled,
      pictureMessagesAllowed:
          pictureMessagesAllowed ?? this.pictureMessagesAllowed,
      autoLockMic: autoLockMic ?? this.autoLockMic,
      giftCatalogAvailable: giftCatalogAvailable ?? this.giftCatalogAvailable,
      giftBalance: giftBalance ?? this.giftBalance,
      onlineCount: onlineCount ?? this.onlineCount,
      coverUrl: coverUrl ?? this.coverUrl,
      backgroundUrl: backgroundUrl ?? this.backgroundUrl,
    );
  }
}

class GiftReceipt {
  const GiftReceipt({
    required this.success,
    required this.remainingBalance,
    this.transferId,
    this.roomId,
    this.senderUserId,
    this.receiverUserId,
    this.giftId,
    this.giftName,
    this.quantity,
    this.source,
    this.deliveryMode,
    this.providerInvocation,
    this.providerStatus,
    this.status,
  });

  final bool success;
  final int? remainingBalance;
  final String? transferId;
  final String? roomId;
  final int? senderUserId;
  final int? receiverUserId;
  final String? giftId;
  final String? giftName;
  final int? quantity;
  final String? source;
  final String? deliveryMode;
  final bool? providerInvocation;
  final String? providerStatus;
  final String? status;
}
