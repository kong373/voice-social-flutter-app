enum RoomRole {
  guest,
  listener,
  speaker,
  moderator,
  owner,
}

enum RoomSessionStatus {
  joining,
  joined,
  reconnecting,
  leaving,
  left,
  closed,
  kicked,
  failed,
}

enum MicSeatState {
  available,
  locked,
  mutedAvailable,
  occupied,
  occupiedMuted,
}

class MicSeat {
  const MicSeat({
    required this.number,
    required this.state,
    this.userName,
    this.isSpeaking = false,
  });

  final int number;
  final MicSeatState state;
  final String? userName;
  final bool isSpeaking;

  bool get isAvailable =>
      state == MicSeatState.available ||
      state == MicSeatState.mutedAvailable;

  MicSeat copyWith({
    MicSeatState? state,
    String? userName,
    bool clearUserName = false,
    bool? isSpeaking,
  }) {
    return MicSeat(
      number: number,
      state: state ?? this.state,
      userName: clearUserName ? null : userName ?? this.userName,
      isSpeaking: isSpeaking ?? this.isSpeaking,
    );
  }
}

class RoomMessage {
  const RoomMessage({
    required this.sender,
    required this.content,
    this.isSystem = false,
  });

  final String sender;
  final String content;
  final bool isSystem;
}
