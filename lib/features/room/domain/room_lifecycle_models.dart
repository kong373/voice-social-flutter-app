enum RoomAccessMode { publicRoom, password, approval }

/// Declares which room-configuration operations the selected repository can
/// actually persist, so presentation code can hide or disable unsupported
/// controls instead of claiming a setting was saved.
class RoomLifecycleCapabilities {
  const RoomLifecycleCapabilities({
    required this.supportsApprovalAccessMode,
    required this.supportsTopicTitle,
    required this.supportsAutoLockMic,
    required this.supportsReopen,
  });

  final bool supportsApprovalAccessMode;
  final bool supportsTopicTitle;
  final bool supportsAutoLockMic;
  final bool supportsReopen;
}

enum RoomAvailability { open, closed, unavailable }

class RoomConfiguration {
  const RoomConfiguration({
    required this.title,
    required this.topicTitle,
    required this.topicContent,
    required this.welcomeMessage,
    required this.accessMode,
    required this.password,
    this.passwordConfigured = false,
    required this.showInHall,
    required this.autoLockMic,
    required this.availability,
    this.roomId,
    this.roomCode,
    this.coverUrl,
    // Null is retained for fixture/mocked configurations created before the
    // first-party room version contract. Live backend reads always populate
    // this field, and live writes reject a missing version for existing rooms.
    this.version,
  });

  final String? roomId;
  final String? roomCode;
  final String title;
  final String topicTitle;
  final String topicContent;
  final String welcomeMessage;
  final RoomAccessMode accessMode;
  final String password;

  /// True when the server already has a password hash for this room. The
  /// hash is never sent to the client; a blank edit keeps the existing hash.
  final bool passwordConfigured;
  final bool showInHall;
  final bool autoLockMic;
  final RoomAvailability availability;
  final String? coverUrl;
  final int? version;

  bool get hasExistingRoom => roomId != null && roomId!.isNotEmpty;
  bool get isOpen => availability == RoomAvailability.open;

  RoomConfiguration copyWith({
    String? roomId,
    String? roomCode,
    String? title,
    String? topicTitle,
    String? topicContent,
    String? welcomeMessage,
    RoomAccessMode? accessMode,
    String? password,
    bool? passwordConfigured,
    bool? showInHall,
    bool? autoLockMic,
    RoomAvailability? availability,
    String? coverUrl,
    int? version,
  }) {
    return RoomConfiguration(
      roomId: roomId ?? this.roomId,
      roomCode: roomCode ?? this.roomCode,
      title: title ?? this.title,
      topicTitle: topicTitle ?? this.topicTitle,
      topicContent: topicContent ?? this.topicContent,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      accessMode: accessMode ?? this.accessMode,
      password: password ?? this.password,
      passwordConfigured: passwordConfigured ?? this.passwordConfigured,
      showInHall: showInHall ?? this.showInHall,
      autoLockMic: autoLockMic ?? this.autoLockMic,
      availability: availability ?? this.availability,
      coverUrl: coverUrl ?? this.coverUrl,
      version: version ?? this.version,
    );
  }
}

class RoomLifecycleSaveResult {
  const RoomLifecycleSaveResult({
    required this.roomId,
    required this.roomCode,
    required this.created,
  });

  final String roomId;
  final String roomCode;
  final bool created;
}

enum RoomLinkStatus { valid, invalid, unavailable, closed }

class RoomLinkResolution {
  const RoomLinkResolution({
    required this.status,
    required this.input,
    this.room,
    this.message,
  });

  final RoomLinkStatus status;
  final String input;
  final RoomConfiguration? room;
  final String? message;

  bool get canEnter => status == RoomLinkStatus.valid && room != null;
}
