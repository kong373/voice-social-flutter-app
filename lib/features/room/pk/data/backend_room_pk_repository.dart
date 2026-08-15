import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_repository.dart';

class BackendRoomPkRepository implements RoomPkRepository {
  BackendRoomPkRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
  })  : _apiClient = apiClient,
        _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;

  @override
  bool get supportsRealtimeInvitations => false;

  @override
  bool get supportsSurrender => false;

  @override
  Future<List<RoomPkOpponent>> fetchHotOpponents({
    required String roomId,
  }) async {
    final ApiResponse response = await _apiClient.get(
      _routes.roomPkHotRooms,
      query: <String, String>{'roomId': roomId},
    );
    return _extractList(response.data)
        .map(_opponentFromMap)
        .where((RoomPkOpponent item) =>
            item.roomId.isNotEmpty && item.roomId != roomId)
        .toList(growable: false);
  }

  @override
  Future<List<RoomPkOpponent>> searchOpponents({
    required String roomId,
    required String keyword,
  }) async {
    final String value = keyword.trim();
    if (value.isEmpty) {
      return fetchHotOpponents(roomId: roomId);
    }
    final ApiResponse response = await _apiClient.get(
      _routes.roomPkSearch,
      query: <String, String>{'roomCode': value},
    );
    final Object? data = response.data;
    final List<Map<String, Object?>> raw = data is List
        ? _asMapList(data)
        : <Map<String, Object?>>[_asMap(data)];
    return raw
        .where((Map<String, Object?> item) => item.isNotEmpty)
        .map(_opponentFromMap)
        .where((RoomPkOpponent item) =>
            item.roomId.isNotEmpty && item.roomId != roomId)
        .toList(growable: false);
  }

  @override
  Future<RoomPkInvitation?> fetchIncomingInvitation({
    required String roomId,
  }) async {
    // Incoming invitations are delivered by the room real-time channel in the
    // legacy product. Until that transport is connected, the client cannot
    // fabricate an inbox from unrelated HTTP data.
    return null;
  }

  @override
  Future<RoomPkInvitation> sendInvitation({
    required String roomId,
    required int inviterUserId,
    required RoomPkOpponent opponent,
    required String punishmentTheme,
    required int durationMinutes,
  }) async {
    final String punishment = punishmentTheme.trim();
    if (inviterUserId <= 0 || opponent.roomId.isEmpty || opponent.roomId == roomId) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: 'PK 对手或邀请人信息无效',
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
    final ApiResponse response = await _apiClient.post(
      _routes.roomPkInvite,
      body: <String, Object?>{
        'inviteUserId': inviterUserId,
        'currentRoomId': _numericId(roomId),
        'otherRoomId': _numericId(opponent.roomId),
        'punishmentTheme': punishment,
        'pkTime': durationMinutes,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final String id = _string(
      data['id'] ?? data['pkInviteId'] ?? data['invitationId'],
      fallback: 'pending-${DateTime.now().millisecondsSinceEpoch}',
    );
    return RoomPkInvitation(
      id: id,
      direction: RoomPkInvitationDirection.outgoing,
      currentRoomId: roomId,
      opponent: opponent,
      punishmentTheme: punishment,
      durationMinutes: durationMinutes,
      status: RoomPkInvitationStatus.pending,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );
  }

  @override
  Future<RoomPkInvitation> refreshInvitation(
    RoomPkInvitation invitation,
  ) async {
    if (invitation.status != RoomPkInvitationStatus.pending) {
      return invitation;
    }
    if (invitation.expiresAt?.isBefore(DateTime.now()) ?? false) {
      return invitation.copyWith(status: RoomPkInvitationStatus.expired);
    }
    final RoomPkBattle? battle =
        await fetchActiveBattle(roomId: invitation.currentRoomId);
    if (battle != null) {
      return invitation.copyWith(status: RoomPkInvitationStatus.accepted);
    }
    return invitation;
  }

  @override
  Future<RoomPkBattle> acceptInvitation(RoomPkInvitation invitation) async {
    await _apiClient.get(
      _routes.roomPkAccept,
      query: <String, String>{'id': invitation.id},
    );
    final RoomPkBattle? battle =
        await fetchActiveBattle(roomId: invitation.currentRoomId);
    if (battle == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '邀请已接受，但服务端尚未返回 PK 对局',
      );
    }
    return battle;
  }

  @override
  Future<void> rejectInvitation(RoomPkInvitation invitation) async {
    await _apiClient.get(
      _routes.roomPkReject,
      query: <String, String>{'id': invitation.id},
    );
  }

  @override
  Future<RoomPkBattle?> fetchActiveBattle({required String roomId}) async {
    final ApiResponse response = await _apiClient.get(
      _routes.roomPkProgress,
      query: <String, String>{'roomId': roomId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty ||
        _string(data['pkId'] ?? data['id']).isEmpty ||
        (_asMap(data['senderRoom']).isEmpty &&
            _asMap(data['receiverRoom']).isEmpty)) {
      return null;
    }
    return _battleFromMap(roomId, data);
  }

  @override
  Future<RoomPkBattle> refreshBattle({
    required String roomId,
    required String battleId,
  }) async {
    final RoomPkBattle? battle = await fetchActiveBattle(roomId: roomId);
    if (battle == null) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 对局已结束或状态已变化',
      );
    }
    if (battle.id != battleId) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '当前房间已经进入另一场 PK，请刷新状态',
      );
    }
    return battle;
  }

  @override
  Future<RoomPkBattle> surrender({
    required String roomId,
    required String battleId,
  }) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '当前后端未确认普通房 PK 主动认输接口',
    );
  }

  @override
  Future<List<RoomPkRecord>> fetchHistory({required String roomId}) async {
    final ApiResponse response = await _apiClient.post(
      _routes.roomPkHistory,
      body: <String, Object?>{
        'roomId': _numericId(roomId),
        'pageNum': 1,
        'pageSize': 20,
      },
    );
    return _extractList(response.data)
        .map((Map<String, Object?> item) => _recordFromMap(roomId, item))
        .where((RoomPkRecord item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  static RoomPkBattle _battleFromMap(
    String currentRoomId,
    Map<String, Object?> data,
  ) {
    final RoomPkSide sender = _sideFromMap(_asMap(data['senderRoom']));
    final RoomPkSide receiver = _sideFromMap(_asMap(data['receiverRoom']));
    final int remaining =
        (_asInt(data['remainingTime'] ?? data['remainingSeconds']) ?? 0)
            .clamp(0, 24 * 60 * 60)
            .toInt();
    final int? rawResult = _asInt(data['result'] ?? data['pkResult']);
    final RoomPkResult? result = switch (rawResult) {
      1 => RoomPkResult.win,
      2 => RoomPkResult.lose,
      3 => RoomPkResult.draw,
      4 => RoomPkResult.surrendered,
      5 => RoomPkResult.canceled,
      _ => null,
    };
    final RoomPkBattleStage stage = result != null
        ? RoomPkBattleStage.completed
        : remaining > 0
            ? RoomPkBattleStage.fighting
            : RoomPkBattleStage.settling;
    return RoomPkBattle(
      id: _string(data['pkId'] ?? data['id']),
      currentRoomId: currentRoomId,
      sender: sender,
      receiver: receiver,
      remainingSeconds: remaining,
      punishmentTheme: _string(
        data['punishment'] ?? data['punishmentTheme'],
      ),
      stage: stage,
      result: result,
      updatedAt: DateTime.now(),
    );
  }

  static RoomPkSide _sideFromMap(Map<String, Object?> item) {
    return RoomPkSide(
      roomId: _string(item['id'] ?? item['roomId']),
      roomCode: _string(item['code'] ?? item['roomCode']),
      roomName: _string(item['name'] ?? item['roomName'], fallback: '语音房'),
      coverUrl: _optionalString(item['headImgUrl'] ?? item['coverUrl']),
      score: _asInt(
            item['popularity'] ?? item['score'] ?? item['theVal'],
          ) ??
          0,
      supporters: _asMapList(
        item['sendUsers'] ?? item['receiveUsers'] ?? item['supporters'],
      ).map(_supporterFromMap).toList(growable: false),
    );
  }

  static RoomPkSupporter _supporterFromMap(Map<String, Object?> item) {
    return RoomPkSupporter(
      userId: _asInt(item['userId']) ?? 0,
      nickname: _string(
        item['nickname'] ?? item['nickName'],
        fallback: '支持者',
      ),
      avatarUrl: _optionalString(item['headImgUrl'] ?? item['avatarUrl']),
      value: _asNum(item['value'] ?? item['theVal'] ?? item['score']) ?? 0,
    );
  }

  static RoomPkOpponent _opponentFromMap(Map<String, Object?> item) {
    return RoomPkOpponent(
      roomId: _string(item['roomId'] ?? item['id']),
      roomCode: _string(item['roomCode'] ?? item['code']),
      roomName: _string(item['roomName'] ?? item['name'], fallback: '语音房'),
      coverUrl: _optionalString(
        item['roomHeadImgUrl'] ?? item['coverUrl'] ?? item['headImgUrl'],
      ),
      label: _string(item['label'] ?? item['tag']),
      onlineUsers: _asInt(
            item['roomOnlinePersonnelNumber'] ??
                item['onlineCount'] ??
                item['onlineUsers'],
          ) ??
          0,
      isInPk: _asBool(item['isInPK'] ?? item['isInPk']),
    );
  }

  static RoomPkRecord _recordFromMap(
    String currentRoomId,
    Map<String, Object?> item,
  ) {
    final String senderId = _string(item['senderRoomId']);
    final bool currentIsSender = senderId == currentRoomId;
    final int raw = _asInt(item['result']) ?? 3;
    final RoomPkResult senderResult = switch (raw) {
      1 => RoomPkResult.win,
      2 => RoomPkResult.lose,
      _ => RoomPkResult.draw,
    };
    final RoomPkResult result = currentIsSender
        ? senderResult
        : switch (senderResult) {
            RoomPkResult.win => RoomPkResult.lose,
            RoomPkResult.lose => RoomPkResult.win,
            _ => senderResult,
          };
    return RoomPkRecord(
      id: _string(item['id'] ?? item['pkId']),
      opponentRoomName: _string(
        currentIsSender
            ? item['receiverRoomName']
            : item['senderRoomName'],
        fallback: '对方房间',
      ),
      opponentCoverUrl: _optionalString(
        currentIsSender
            ? item['receiverRoomHeadImg']
            : item['senderRoomHeadImg'],
      ),
      completedAt: _asDateTime(
        item['pkDate'] ?? item['createTime'] ?? item['completedAt'],
      ),
      result: result,
      currentScore: _asInt(
            currentIsSender ? item['senderScore'] : item['receiverScore'],
          ) ??
          0,
      opponentScore: _asInt(
            currentIsSender ? item['receiverScore'] : item['senderScore'],
          ) ??
          0,
    );
  }

  static List<Map<String, Object?>> _extractList(Object? value) {
    final Map<String, Object?> map = _asMap(value);
    final Object? source = map['records'] ??
        map['list'] ??
        map['rows'] ??
        map['items'] ??
        map['data'] ??
        value;
    return _asMapList(source);
  }

  static Object _numericId(String value) => int.tryParse(value) ?? value;
  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};
  static List<Map<String, Object?>> _asMapList(Object? value) => value is List
      ? value.whereType<Map<String, Object?>>().toList(growable: false)
      : const <Map<String, Object?>>[];
  static String _string(Object? value, {String fallback = ''}) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
  static String? _optionalString(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
  static int? _asInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
  static num? _asNum(Object? value) =>
      value is num ? value : num.tryParse(value?.toString() ?? '');
  static bool _asBool(Object? value) =>
      value == true || value == 1 || value?.toString() == '1';
  static DateTime _asDateTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}
