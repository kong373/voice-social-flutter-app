import 'dart:async';

import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_repository.dart';

class MockRoomPkRepository implements RoomPkRepository {
  MockRoomPkRepository()
    : _incoming = RoomPkInvitation(
        id: 'pk-incoming-1',
        direction: RoomPkInvitationDirection.incoming,
        currentRoomId: '880217',
        opponent: const RoomPkOpponent(
          roomId: '660318',
          roomCode: '660318',
          roomName: '下班后的松弛时刻',
          onlineUsers: 24,
        ),
        punishmentTheme: '输的一方分享今天最想放下的事',
        durationMinutes: 5,
        status: RoomPkInvitationStatus.pending,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      );

  final List<RoomPkOpponent> _opponents = const <RoomPkOpponent>[
    RoomPkOpponent(
      roomId: '660318',
      roomCode: '660318',
      roomName: '下班后的松弛时刻',
      label: '陪伴',
      onlineUsers: 24,
    ),
    RoomPkOpponent(
      roomId: '520906',
      roomCode: '520906',
      roomName: '安静音乐电台',
      label: '音乐',
      onlineUsers: 18,
    ),
    RoomPkOpponent(
      roomId: '731105',
      roomCode: '731105',
      roomName: '城市夜谈',
      label: '聊天',
      onlineUsers: 31,
      isInPk: true,
    ),
  ];

  RoomPkInvitation? _incoming;
  RoomPkInvitation? _outgoing;
  RoomPkBattle? _battle;
  int _outgoingRefreshes = 0;
  int _battleRefreshes = 0;

  @override
  bool get supportsRealtimeInvitations => false;

  @override
  bool get supportsSurrender => true;

  void seedBattleForQa(RoomPkBattle battle) {
    _battle = battle;
    _battleRefreshes = 0;
  }

  @override
  Future<List<RoomPkOpponent>> fetchHotOpponents({
    required String roomId,
  }) async {
    await _delay();
    return _opponents
        .where((RoomPkOpponent item) => item.roomId != roomId)
        .toList(growable: false);
  }

  @override
  Future<List<RoomPkOpponent>> searchOpponents({
    required String roomId,
    required String keyword,
  }) async {
    await _delay();
    final String query = keyword.trim().toLowerCase();
    if (query.isEmpty) {
      return fetchHotOpponents(roomId: roomId);
    }
    return _opponents
        .where(
          (RoomPkOpponent item) =>
              item.roomId != roomId &&
              (item.roomCode.toLowerCase().contains(query) ||
                  item.roomName.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  @override
  Future<RoomPkInvitation?> fetchIncomingInvitation({
    required String roomId,
  }) async {
    await _delay();
    final RoomPkInvitation? incoming = _incoming;
    if (incoming == null || incoming.currentRoomId != roomId) {
      return null;
    }
    if (incoming.expiresAt?.isBefore(DateTime.now()) ?? false) {
      _incoming = incoming.copyWith(status: RoomPkInvitationStatus.expired);
    }
    return _incoming;
  }

  @override
  Future<RoomPkInvitation> sendInvitation({
    required String roomId,
    required int inviterUserId,
    required RoomPkOpponent opponent,
    required String punishmentTheme,
    required int durationMinutes,
  }) async {
    await _delay();
    final String punishment = punishmentTheme.trim();
    if (inviterUserId <= 0 || opponent.roomId == roomId) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: 'PK 对手或邀请人信息无效',
      );
    }
    if (opponent.isInPk) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '对方房间正在 PK，请选择其他房间',
      );
    }
    if (punishment.isEmpty || punishment.length > 20) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '惩罚主题需为 1～20 个字',
      );
    }
    if (!const <int>{5, 10, 15}.contains(durationMinutes)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择有效的 PK 时长',
      );
    }
    if (_battle?.isActive ?? false) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '当前房间已经在 PK 中',
      );
    }
    _outgoingRefreshes = 0;
    _outgoing = RoomPkInvitation(
      id: 'pk-outgoing-${DateTime.now().millisecondsSinceEpoch}',
      direction: RoomPkInvitationDirection.outgoing,
      currentRoomId: roomId,
      opponent: opponent,
      punishmentTheme: punishment,
      durationMinutes: durationMinutes,
      status: RoomPkInvitationStatus.pending,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );
    return _outgoing!;
  }

  @override
  Future<RoomPkInvitation> refreshInvitation(
    RoomPkInvitation invitation,
  ) async {
    await _delay();
    final RoomPkInvitation? current =
        invitation.direction == RoomPkInvitationDirection.outgoing
        ? _outgoing
        : _incoming;
    if (current == null || current.id != invitation.id) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 邀请状态已变化，请刷新后重试',
      );
    }
    if (current.status != RoomPkInvitationStatus.pending) {
      return current;
    }
    if (current.expiresAt?.isBefore(DateTime.now()) ?? false) {
      final RoomPkInvitation expired = current.copyWith(
        status: RoomPkInvitationStatus.expired,
      );
      if (current.direction == RoomPkInvitationDirection.outgoing) {
        _outgoing = expired;
      } else {
        _incoming = expired;
      }
      return expired;
    }
    if (current.direction == RoomPkInvitationDirection.outgoing) {
      _outgoingRefreshes += 1;
      if (_outgoingRefreshes >= 2) {
        final RoomPkInvitation accepted = current.copyWith(
          status: RoomPkInvitationStatus.accepted,
        );
        _outgoing = accepted;
        _battle = _battleForInvitation(accepted);
        return accepted;
      }
    }
    return current;
  }

  @override
  Future<RoomPkBattle> acceptInvitation(RoomPkInvitation invitation) async {
    await _delay();
    final RoomPkInvitation? current = _incoming;
    if (current == null ||
        current.id != invitation.id ||
        current.status != RoomPkInvitationStatus.pending) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '邀请已处理或已过期',
      );
    }
    _incoming = current.copyWith(status: RoomPkInvitationStatus.accepted);
    _battle = _battleForInvitation(_incoming!);
    return _battle!;
  }

  @override
  Future<void> rejectInvitation(RoomPkInvitation invitation) async {
    await _delay();
    final RoomPkInvitation? current = _incoming;
    if (current == null ||
        current.id != invitation.id ||
        current.status != RoomPkInvitationStatus.pending) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '邀请已处理或已过期',
      );
    }
    _incoming = current.copyWith(status: RoomPkInvitationStatus.rejected);
  }

  @override
  Future<RoomPkBattle?> fetchActiveBattle({required String roomId}) async {
    await _delay();
    final RoomPkBattle? battle = _battle;
    if (battle == null || battle.currentRoomId != roomId) {
      return null;
    }
    return battle;
  }

  @override
  Future<RoomPkBattle> refreshBattle({
    required String roomId,
    required String battleId,
  }) async {
    await _delay();
    final RoomPkBattle? current = _battle;
    if (current == null ||
        current.id != battleId ||
        current.currentRoomId != roomId) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 对局已结束或状态已变化',
      );
    }
    if (!current.isActive) {
      return current;
    }
    _battleRefreshes += 1;
    final int remaining = (current.remainingSeconds - 60)
        .clamp(0, 24 * 60 * 60)
        .toInt();
    final RoomPkSide sender = current.sender.copyWith(
      score: current.sender.score + 120 + _battleRefreshes * 15,
    );
    final RoomPkSide receiver = current.receiver.copyWith(
      score: current.receiver.score + 105 + _battleRefreshes * 12,
    );
    if (remaining > 0) {
      _battle = current.copyWith(
        sender: sender,
        receiver: receiver,
        remainingSeconds: remaining,
        stage: RoomPkBattleStage.fighting,
        updatedAt: DateTime.now(),
      );
      return _battle!;
    }
    final int currentScore = sender.roomId == roomId
        ? sender.score
        : receiver.score;
    final int opponentScore = sender.roomId == roomId
        ? receiver.score
        : sender.score;
    final RoomPkResult result = currentScore == opponentScore
        ? RoomPkResult.draw
        : currentScore > opponentScore
        ? RoomPkResult.win
        : RoomPkResult.lose;
    _battle = current.copyWith(
      sender: sender,
      receiver: receiver,
      remainingSeconds: 0,
      stage: RoomPkBattleStage.completed,
      result: result,
      updatedAt: DateTime.now(),
    );
    return _battle!;
  }

  @override
  Future<RoomPkBattle> surrender({
    required String roomId,
    required String battleId,
  }) async {
    await _delay();
    final RoomPkBattle? current = _battle;
    if (current == null ||
        current.id != battleId ||
        current.currentRoomId != roomId ||
        !current.isActive) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 状态已变化，无法认输',
      );
    }
    _battle = current.copyWith(
      remainingSeconds: 0,
      stage: RoomPkBattleStage.completed,
      result: RoomPkResult.surrendered,
      updatedAt: DateTime.now(),
    );
    return _battle!;
  }

  @override
  Future<List<RoomPkRecord>> fetchHistory({required String roomId}) async {
    await _delay();
    return <RoomPkRecord>[
      RoomPkRecord(
        id: 'record-1',
        opponentRoomName: '安静音乐电台',
        completedAt: DateTime.now().subtract(const Duration(days: 1)),
        result: RoomPkResult.win,
        currentScore: 3680,
        opponentScore: 2940,
      ),
      RoomPkRecord(
        id: 'record-2',
        opponentRoomName: '城市夜谈',
        completedAt: DateTime.now().subtract(const Duration(days: 3)),
        result: RoomPkResult.draw,
        currentScore: 2120,
        opponentScore: 2120,
      ),
    ];
  }

  RoomPkBattle _battleForInvitation(RoomPkInvitation invitation) {
    final bool currentIsSender =
        invitation.direction == RoomPkInvitationDirection.outgoing;
    final RoomPkSide current = RoomPkSide(
      roomId: invitation.currentRoomId,
      roomCode: '880217',
      roomName: '深夜温柔陪伴',
      score: 0,
      supporters: const <RoomPkSupporter>[
        RoomPkSupporter(userId: 20011, nickname: '鹿屿', value: 0),
      ],
    );
    final RoomPkSide opponent = RoomPkSide(
      roomId: invitation.opponent.roomId,
      roomCode: invitation.opponent.roomCode,
      roomName: invitation.opponent.roomName,
      coverUrl: invitation.opponent.coverUrl,
      score: 0,
      supporters: const <RoomPkSupporter>[
        RoomPkSupporter(userId: 20012, nickname: '青禾', value: 0),
      ],
    );
    _battleRefreshes = 0;
    return RoomPkBattle(
      id: 'battle-${invitation.id}',
      currentRoomId: invitation.currentRoomId,
      sender: currentIsSender ? current : opponent,
      receiver: currentIsSender ? opponent : current,
      remainingSeconds: invitation.durationMinutes * 60,
      punishmentTheme: invitation.punishmentTheme,
      stage: RoomPkBattleStage.fighting,
      updatedAt: DateTime.now(),
    );
  }

  static Future<void> _delay() =>
      Future<void>.delayed(const Duration(milliseconds: 35));
}
