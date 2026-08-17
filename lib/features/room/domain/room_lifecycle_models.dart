enum RoomAccessMode { publicRoom, password }

enum RoomAvailability { open, closed, unavailable }

class RoomConfiguration {
  const RoomConfiguration({
    required this.title,
    required this.topicTitle,
    required this.topicContent,
    required this.welcomeMessage,
    required this.accessMode,
    required this.password,
    required this.showInHall,
    required this.autoLockMic,
    required this.availability,
    this.roomId,
    this.roomCode,
    this.coverUrl,
  });

  final String? roomId;
  final String? roomCode;
  final String title;
  final String topicTitle;
  final String topicContent;
  final String welcomeMessage;
  final RoomAccessMode accessMode;
  final String password;
  final bool showInHall;
  final bool autoLockMic;
  final RoomAvailability availability;
  final String? coverUrl;

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
    bool? showInHall,
    bool? autoLockMic,
    RoomAvailability? availability,
    String? coverUrl,
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
      showInHall: showInHall ?? this.showInHall,
      autoLockMic: autoLockMic ?? this.autoLockMic,
      availability: availability ?? this.availability,
      coverUrl: coverUrl ?? this.coverUrl,
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
