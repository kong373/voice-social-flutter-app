enum RoomPkInvitationDirection { outgoing, incoming }

enum RoomPkInvitationStatus {
  pending,
  accepted,
  rejected,
  expired,
  canceled,
}

enum RoomPkBattleStage {
  preparing,
  fighting,
  settling,
  completed,
  canceled,
}

enum RoomPkResult {
  win,
  lose,
  draw,
  surrendered,
  canceled,
}

class RoomPkOpponent {
  const RoomPkOpponent({
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    this.coverUrl,
    this.label = '',
    this.onlineUsers = 0,
    this.isInPk = false,
  });

  final String roomId;
  final String roomCode;
  final String roomName;
  final String? coverUrl;
  final String label;
  final int onlineUsers;
  final bool isInPk;
}

class RoomPkInvitation {
  const RoomPkInvitation({
    required this.id,
    required this.direction,
    required this.currentRoomId,
    required this.opponent,
    required this.punishmentTheme,
    required this.durationMinutes,
    required this.status,
    required this.createdAt,
    this.expiresAt,
  });

  final String id;
  final RoomPkInvitationDirection direction;
  final String currentRoomId;
  final RoomPkOpponent opponent;
  final String punishmentTheme;
  final int durationMinutes;
  final RoomPkInvitationStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;

  RoomPkInvitation copyWith({
    RoomPkInvitationStatus? status,
    DateTime? expiresAt,
  }) {
    return RoomPkInvitation(
      id: id,
      direction: direction,
      currentRoomId: currentRoomId,
      opponent: opponent,
      punishmentTheme: punishmentTheme,
      durationMinutes: durationMinutes,
      status: status ?? this.status,
      createdAt: createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

class RoomPkSupporter {
  const RoomPkSupporter({
    required this.userId,
    required this.nickname,
    required this.value,
    this.avatarUrl,
  });

  final int userId;
  final String nickname;
  final num value;
  final String? avatarUrl;
}

class RoomPkSide {
  const RoomPkSide({
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    required this.score,
    this.coverUrl,
    this.supporters = const <RoomPkSupporter>[],
  });

  final String roomId;
  final String roomCode;
  final String roomName;
  final int score;
  final String? coverUrl;
  final List<RoomPkSupporter> supporters;

  RoomPkSide copyWith({int? score, List<RoomPkSupporter>? supporters}) {
    return RoomPkSide(
      roomId: roomId,
      roomCode: roomCode,
      roomName: roomName,
      score: score ?? this.score,
      coverUrl: coverUrl,
      supporters: supporters ?? this.supporters,
    );
  }
}

class RoomPkBattle {
  const RoomPkBattle({
    required this.id,
    required this.currentRoomId,
    required this.sender,
    required this.receiver,
    required this.remainingSeconds,
    required this.punishmentTheme,
    required this.stage,
    required this.updatedAt,
    this.result,
  });

  final String id;
  final String currentRoomId;
  final RoomPkSide sender;
  final RoomPkSide receiver;
  final int remainingSeconds;
  final String punishmentTheme;
  final RoomPkBattleStage stage;
  final RoomPkResult? result;
  final DateTime updatedAt;

  RoomPkSide get currentSide =>
      sender.roomId == currentRoomId ? sender : receiver;

  RoomPkSide get opponentSide =>
      sender.roomId == currentRoomId ? receiver : sender;

  bool get isActive => stage == RoomPkBattleStage.preparing ||
      stage == RoomPkBattleStage.fighting ||
      stage == RoomPkBattleStage.settling;

  RoomPkBattle copyWith({
    RoomPkSide? sender,
    RoomPkSide? receiver,
    int? remainingSeconds,
    RoomPkBattleStage? stage,
    RoomPkResult? result,
    DateTime? updatedAt,
  }) {
    return RoomPkBattle(
      id: id,
      currentRoomId: currentRoomId,
      sender: sender ?? this.sender,
      receiver: receiver ?? this.receiver,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      punishmentTheme: punishmentTheme,
      stage: stage ?? this.stage,
      result: result ?? this.result,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class RoomPkRecord {
  const RoomPkRecord({
    required this.id,
    required this.opponentRoomName,
    required this.completedAt,
    required this.result,
    required this.currentScore,
    required this.opponentScore,
    this.opponentCoverUrl,
  });

  final String id;
  final String opponentRoomName;
  final String? opponentCoverUrl;
  final DateTime completedAt;
  final RoomPkResult result;
  final int currentScore;
  final int opponentScore;
}
