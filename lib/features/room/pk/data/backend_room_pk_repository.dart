import 'dart:async';

import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_repository.dart';

/// First-party HTTP adapter for the authoritative Room PK state machine.
///
/// The backend contract deliberately has no client-side fallback routes and
/// no vendor/RTC success path. Reads consume the backend projection as-is;
/// writes retain one request id for an ambiguous retry and let [ApiClient]
/// replay authentication failures with that same id.
class BackendRoomPkRepository implements RoomPkRepository {
  BackendRoomPkRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
  }) : _apiClient = apiClient,
       _routes = routes;

  static const String _invitePath = '/app-api/activityPk/inviteRoomPk';
  static const String _acceptPath =
      '/app-api/activityPk/acceptRoomPkInvitation';
  static const String _rejectPath =
      '/app-api/activityPk/rejectRoomPkInvitation';
  static const String _surrenderPath = '/app-api/activityPk/surrenderRoomPk';
  static const String _endPath = '/app-api/activityPk/endRoomPk';
  static const String _processPath = '/app-api/activityPk/queryRoomPkProcess';
  static const String _historyPath = '/app-api/activityPk/queryRoomPkHistory';
  static const String _hotPath = '/app-api/activityPk/getRoomPkHotRoomList';
  static const String _searchPath = '/app-api/activityPk/searchRoomPk';

  static final RegExp _canonicalUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static int _requestSequence = 0;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final Map<String, String> _retainedRequestIds = <String, String>{};
  final Map<String, Future<Object?>> _inFlightWrites =
      <String, Future<Object?>>{};
  final Map<String, DateTime> _latestBattleUpdates = <String, DateTime>{};
  final Map<String, RoomPkBattleStage> _latestBattleStages =
      <String, RoomPkBattleStage>{};

  @override
  bool get supportsRealtimeInvitations => false;

  @override
  bool get supportsSurrender => true;

  @override
  Future<List<RoomPkOpponent>> fetchHotOpponents({
    required String roomId,
  }) async {
    final String currentRoomId = _roomId(roomId, '当前房间 ID');
    final ApiResponse response = await _apiClient.get(
      _route(_routes.roomPkHotRooms, _hotPath),
    );
    final _PageEnvelope page = _pageFromResponse(
      response.data,
      expectedPage: 1,
      expectedPageSize: 20,
    );
    return page.records
        .map(_opponentFromMap)
        .where((RoomPkOpponent item) => item.roomId != currentRoomId)
        .toList(growable: false);
  }

  @override
  Future<List<RoomPkOpponent>> searchOpponents({
    required String roomId,
    required String keyword,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final String currentRoomId = _roomId(roomId, '当前房间 ID');
    final _PageRequest page = _pageRequest(pageNum, pageSize);
    final String value = keyword.trim();
    if (value.length > 80) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '搜索关键词不能超过 80 个字符',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _route(_routes.roomPkSearch, _searchPath),
      query: <String, String>{
        'keyword': value,
        'pageNum': '${page.page}',
        'pageSize': '${page.size}',
      },
    );
    final _PageEnvelope result = _pageFromResponse(
      response.data,
      expectedPage: page.page,
      expectedPageSize: page.size,
    );
    return result.records
        .map(_opponentFromMap)
        .where((RoomPkOpponent item) => item.roomId != currentRoomId)
        .toList(growable: false);
  }

  @override
  Future<RoomPkInvitation?> fetchIncomingInvitation({
    required String roomId,
  }) async {
    // The HTTP projection does not identify inviter vs invitee. Returning an
    // invented direction would allow the UI to accept an invitation it does
    // not own, so the real-time inbox remains explicitly unavailable.
    _roomId(roomId, '当前房间 ID');
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
    final String currentRoomId = _roomId(roomId, '当前房间 ID');
    final String targetRoomId = _roomId(opponent.roomId, '目标房间 ID');
    if (currentRoomId == targetRoomId) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '不能邀请同一个房间进行 PK',
      );
    }
    final String punishment = punishmentTheme.trim();
    if (punishment.isEmpty || punishment.length > 20) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '惩罚主题需为 1～20 个字',
      );
    }
    if (!const <int>{5, 10, 15}.contains(durationMinutes)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: 'PK 时长仅支持 5、10 或 15 分钟',
      );
    }
    return _runWrite<RoomPkInvitation>(
      operation: 'invite',
      intentParts: <Object?>[
        currentRoomId,
        targetRoomId,
        punishment,
        durationMinutes,
      ],
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _route(_routes.roomPkInvite, _invitePath),
          headers: headers,
          body: <String, Object?>{
            'roomId': currentRoomId,
            'targetRoomId': targetRoomId,
            'punishmentTheme': punishment,
            'durationMinutes': durationMinutes,
          },
        );
        return _invitationFromProjection(
          response.data,
          expectedRoomId: currentRoomId,
          expectedTargetRoomId: targetRoomId,
          direction: RoomPkInvitationDirection.outgoing,
          opponent: opponent,
          punishmentTheme: punishment,
          durationMinutes: durationMinutes,
        );
      },
    );
  }

  @override
  Future<RoomPkInvitation> refreshInvitation(
    RoomPkInvitation invitation,
  ) async {
    final String currentRoomId = _roomId(invitation.currentRoomId, '当前房间 ID');
    final Map<String, Object?> projection = await _process(
      roomId: currentRoomId,
    );
    final String? returnedId = _optionalUuid(
      projection['invitationId'],
      '邀请 ID',
    );
    if (returnedId == null || returnedId != invitation.id) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 邀请状态已变化，请刷新后重试',
      );
    }
    return _invitationFromProjection(
      projection,
      expectedRoomId: currentRoomId,
      expectedTargetRoomId: invitation.opponent.roomId,
      expectedInvitationId: invitation.id,
      direction: invitation.direction,
      opponent: invitation.opponent,
      punishmentTheme: invitation.punishmentTheme,
      durationMinutes: invitation.durationMinutes,
    );
  }

  @override
  Future<RoomPkBattle> acceptInvitation(RoomPkInvitation invitation) async {
    final String invitationId = _uuid(invitation.id, '邀请 ID');
    final String currentRoomId = _roomId(invitation.currentRoomId, '当前房间 ID');
    return _runWrite<RoomPkBattle>(
      operation: 'accept',
      intentParts: <Object?>[invitationId],
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _route(_routes.roomPkAccept, _acceptPath),
          headers: headers,
          body: <String, Object?>{'invitationId': invitationId},
        );
        return _battleFromProjection(
          response.data,
          expectedRoomId: currentRoomId,
          expectedInvitationId: invitationId,
          expectedTargetRoomId: invitation.opponent.roomId,
          expectedBattleStatus: 'IN_PROGRESS',
        );
      },
    );
  }

  @override
  Future<void> rejectInvitation(RoomPkInvitation invitation) async {
    final String invitationId = _uuid(invitation.id, '邀请 ID');
    final String currentRoomId = _roomId(invitation.currentRoomId, '当前房间 ID');
    return _runWrite<void>(
      operation: 'reject',
      intentParts: <Object?>[invitationId],
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _route(_routes.roomPkReject, _rejectPath),
          headers: headers,
          body: <String, Object?>{'invitationId': invitationId},
        );
        final RoomPkInvitation result = _invitationFromProjection(
          response.data,
          expectedRoomId: currentRoomId,
          expectedTargetRoomId: invitation.opponent.roomId,
          expectedInvitationId: invitationId,
          direction: invitation.direction,
          opponent: invitation.opponent,
          punishmentTheme: invitation.punishmentTheme,
          durationMinutes: invitation.durationMinutes,
        );
        if (result.status != RoomPkInvitationStatus.rejected) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '拒绝邀请响应未返回 REJECTED 状态',
          );
        }
      },
    );
  }

  @override
  Future<RoomPkBattle?> fetchActiveBattle({required String roomId}) async {
    final String currentRoomId = _roomId(roomId, '当前房间 ID');
    final Map<String, Object?> projection = await _process(
      roomId: currentRoomId,
    );
    final Object? rawBattleId = projection['battleId'];
    if (rawBattleId == null || rawBattleId.toString().trim().isEmpty) {
      return null;
    }
    return _battleFromProjection(projection, expectedRoomId: currentRoomId);
  }

  @override
  Future<RoomPkBattle> refreshBattle({
    required String roomId,
    required String battleId,
  }) async {
    final String currentRoomId = _roomId(roomId, '当前房间 ID');
    final String expectedBattleId = _uuid(battleId, '对战 ID');
    final RoomPkBattle? battle = await fetchActiveBattle(roomId: currentRoomId);
    if (battle == null || battle.id != expectedBattleId) {
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
  }) async => _finishBattle(
    roomId: roomId,
    battleId: battleId,
    operation: 'surrender',
    path: _surrenderPath,
    expectedStatus: 'SURRENDERED',
  );

  @override
  Future<RoomPkBattle> end({
    required String roomId,
    required String battleId,
  }) async => _finishBattle(
    roomId: roomId,
    battleId: battleId,
    operation: 'end',
    path: _endPath,
    expectedStatus: 'COMPLETED',
  );

  @override
  Future<List<RoomPkRecord>> fetchHistory({
    required String roomId,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final String currentRoomId = _roomId(roomId, '当前房间 ID');
    final _PageRequest page = _pageRequest(pageNum, pageSize);
    final ApiResponse response = await _apiClient.get(
      _historyPath,
      query: <String, String>{
        'roomId': currentRoomId,
        'pageNum': '${page.page}',
        'pageSize': '${page.size}',
      },
    );
    final _PageEnvelope result = _pageFromResponse(
      response.data,
      expectedPage: page.page,
      expectedPageSize: page.size,
    );
    return result.records
        .map((Map<String, Object?> item) => _recordFromMap(currentRoomId, item))
        .toList(growable: false);
  }

  Future<RoomPkBattle> _finishBattle({
    required String roomId,
    required String battleId,
    required String operation,
    required String path,
    required String expectedStatus,
  }) {
    final String currentRoomId = _roomId(roomId, '当前房间 ID');
    final String expectedBattleId = _uuid(battleId, '对战 ID');
    return _runWrite<RoomPkBattle>(
      operation: operation,
      intentParts: <Object?>[expectedBattleId],
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          path,
          headers: headers,
          body: <String, Object?>{'battleId': expectedBattleId},
        );
        final RoomPkBattle battle = _battleFromProjection(
          response.data,
          expectedRoomId: currentRoomId,
          expectedBattleId: expectedBattleId,
          expectedBattleStatus: expectedStatus,
        );
        if (!battle.isActive && battle.stage != RoomPkBattleStage.completed) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '结束 PK 响应状态无法识别',
          );
        }
        return battle;
      },
    );
  }

  Future<Map<String, Object?>> _process({required String roomId}) async {
    final ApiResponse response = await _apiClient.get(
      _processPath,
      query: <String, String>{'roomId': roomId},
    );
    final Map<String, Object?> projection = _requiredMap(
      response.data,
      'PK 状态响应',
    );
    _assertVendorBlocked(projection);
    final String responseRoomId = _uuid(
      _requiredText(projection['roomId'], '房间 ID'),
      '房间 ID',
    );
    if (responseRoomId != roomId) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 状态响应属于其他房间',
      );
    }
    return projection;
  }

  RoomPkInvitation _invitationFromProjection(
    Object? raw, {
    required String expectedRoomId,
    required String expectedTargetRoomId,
    String? expectedInvitationId,
    required RoomPkInvitationDirection direction,
    required RoomPkOpponent opponent,
    required String punishmentTheme,
    required int durationMinutes,
  }) {
    final Map<String, Object?> data = _requiredMap(raw, 'PK 邀请响应');
    _assertVendorBlocked(data);
    final String roomId = _uuid(
      _requiredText(data['roomId'], '房间 ID'),
      '房间 ID',
    );
    final String targetRoomId = _uuid(
      _requiredText(data['targetRoomId'], '目标房间 ID'),
      '目标房间 ID',
    );
    final String invitationId = _uuid(
      _requiredText(data['invitationId'], '邀请 ID'),
      '邀请 ID',
    );
    final bool directOrientation =
        roomId == expectedRoomId && targetRoomId == expectedTargetRoomId;
    final bool reversedOrientation =
        roomId == expectedTargetRoomId && targetRoomId == expectedRoomId;
    if (!directOrientation && !reversedOrientation) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 邀请响应的房间已变化',
      );
    }
    if (expectedInvitationId != null && invitationId != expectedInvitationId) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 邀请响应的 ID 已变化',
      );
    }
    final RoomPkInvitationStatus? status = _invitationStatus(
      data['invitationStatus'],
    );
    final DateTime createdAt = _requiredDate(data['createdAt'], '创建时间');
    final DateTime? expiresAt = _optionalDate(data['expiresAt'], '过期时间');
    final DateTime? resolvedAt = _optionalDate(data['resolvedAt'], '处理时间');
    final String authoritativePunishment = _requiredText(
      data['punishmentTheme'],
      '惩罚主题',
    );
    final int authoritativeDuration = _requiredInt(
      data['durationMinutes'],
      'PK 时长',
    );
    if (status == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 邀请响应缺少有效 invitationStatus',
      );
    }
    if (authoritativePunishment != punishmentTheme ||
        authoritativeDuration != durationMinutes ||
        !const <int>{5, 10, 15}.contains(authoritativeDuration)) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 邀请响应的惩罚主题或时长已变化',
      );
    }
    return RoomPkInvitation(
      id: invitationId,
      direction: direction,
      currentRoomId: expectedRoomId,
      opponent: opponent,
      punishmentTheme: authoritativePunishment,
      durationMinutes: authoritativeDuration,
      status: status,
      createdAt: createdAt,
      expiresAt: expiresAt,
      resolvedAt: resolvedAt,
    );
  }

  RoomPkBattle _battleFromProjection(
    Object? raw, {
    required String expectedRoomId,
    String? expectedInvitationId,
    String? expectedBattleId,
    String? expectedTargetRoomId,
    String? expectedBattleStatus,
  }) {
    final Map<String, Object?> data = _requiredMap(raw, 'PK 对战响应');
    _assertVendorBlocked(data);
    final String responseRoomId = _uuid(
      _requiredText(data['roomId'], '房间 ID'),
      '房间 ID',
    );
    final String responseTargetRoomId = _uuid(
      _requiredText(data['targetRoomId'], '目标房间 ID'),
      '目标房间 ID',
    );
    final String battleId = _uuid(
      _requiredText(data['battleId'], '对战 ID'),
      '对战 ID',
    );
    final String? invitationId = _optionalUuid(data['invitationId'], '邀请 ID');
    final bool directOrientation =
        responseRoomId == expectedRoomId &&
        (expectedTargetRoomId == null ||
            responseTargetRoomId == expectedTargetRoomId);
    final bool reversedOrientation =
        responseTargetRoomId == expectedRoomId &&
        (expectedTargetRoomId == null ||
            responseRoomId == expectedTargetRoomId);
    if (responseRoomId == responseTargetRoomId ||
        (!directOrientation && !reversedOrientation)) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 对战响应的房间已变化',
      );
    }
    // Mutation projections are rooted at the inviter/left room, while a
    // caller may be the invited/right room. Normalize both orientations to
    // the caller before deriving sides and result ownership.
    final String roomId = expectedRoomId;
    final String targetRoomId = directOrientation
        ? responseTargetRoomId
        : responseRoomId;
    if (expectedInvitationId != null && invitationId != expectedInvitationId) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 对战响应缺少匹配的邀请',
      );
    }
    if (expectedBattleId != null && battleId != expectedBattleId) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 对战响应的 ID 已变化',
      );
    }
    final String status = _requiredStatus(data['battleStatus'], '对战状态');
    if (expectedBattleStatus != null && status != expectedBattleStatus) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: 'PK 对战状态已变化',
      );
    }
    final RoomPkBattleStage? stage = _battleStage(status);
    if (stage == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 对战响应缺少有效 battleStatus',
      );
    }
    final DateTime updatedAt = _requiredDate(
      data['startedAt'] ?? data['completedAt'] ?? data['endsAt'],
      '对战时间',
    );
    _assertBattleFresh(battleId, updatedAt, stage);
    final int remainingSeconds = _requiredInt(
      data['countdownSeconds'],
      '倒计时',
    ).clamp(0, 24 * 60 * 60).toInt();
    final RoomPkResult? result = _resultFromProjection(
      data,
      currentRoomId: roomId,
      targetRoomId: targetRoomId,
    );
    final RoomPkSide left = _sideFromProjection(data['leftRoom'], '左侧房间');
    final RoomPkSide right = _sideFromProjection(data['rightRoom'], '右侧房间');
    if (left.roomId == right.roomId ||
        !<String>{left.roomId, right.roomId}.contains(roomId) ||
        !<String>{left.roomId, right.roomId}.contains(targetRoomId) ||
        _uuid(data['leftRoomId'], '左侧房间 ID') != left.roomId ||
        _uuid(data['rightRoomId'], '右侧房间 ID') != right.roomId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 对战双方权威投影不一致',
      );
    }
    final String punishmentTheme = _requiredText(
      data['punishmentTheme'],
      '惩罚主题',
    );
    final int durationMinutes = _requiredInt(data['durationMinutes'], 'PK 时长');
    if (!const <int>{5, 10, 15}.contains(durationMinutes)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 对战响应的时长无效',
      );
    }
    return RoomPkBattle(
      id: battleId,
      invitationId: invitationId,
      currentRoomId: roomId,
      targetRoomId: targetRoomId,
      sender: left,
      receiver: right,
      remainingSeconds: remainingSeconds,
      punishmentTheme: punishmentTheme,
      stage: stage,
      result: result,
      resultCode: _optionalText(data['resultCode']),
      status: status,
      startedAt: _optionalDate(data['startedAt'], '开始时间'),
      endsAt: _optionalDate(data['endsAt'], '结束时间'),
      completedAt: _optionalDate(data['completedAt'], '完成时间'),
      updatedAt: updatedAt,
    );
  }

  RoomPkRecord _recordFromMap(String currentRoomId, Map<String, Object?> data) {
    _assertVendorBlocked(data);
    final String recordRoomId = _uuid(
      _requiredText(data['roomId'], '历史房间 ID'),
      '历史房间 ID',
    );
    final String targetRoomId = _uuid(
      _requiredText(data['targetRoomId'], '历史目标房间 ID'),
      '历史目标房间 ID',
    );
    final String leftRoomId = _uuid(
      _requiredText(data['leftRoomId'], '左侧房间 ID'),
      '左侧房间 ID',
    );
    final String rightRoomId = _uuid(
      _requiredText(data['rightRoomId'], '右侧房间 ID'),
      '右侧房间 ID',
    );
    final String battleId = _uuid(
      _requiredText(data['battleId'], '历史对战 ID'),
      '历史对战 ID',
    );
    final String? invitationId = _optionalUuid(data['invitationId'], '历史邀请 ID');
    if (recordRoomId != currentRoomId ||
        leftRoomId == rightRoomId ||
        !<String>{leftRoomId, rightRoomId}.contains(currentRoomId) ||
        !<String>{leftRoomId, rightRoomId}.contains(targetRoomId)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 历史记录的房间关系无效',
      );
    }
    final String status = _requiredStatus(
      data['battleStatus'] ?? data['status'],
      '历史对战状态',
    );
    final DateTime completedAt = _requiredDate(data['completedAt'], '完成时间');
    final RoomPkResult? result = _resultFromProjection(
      data,
      currentRoomId: currentRoomId,
      targetRoomId: targetRoomId,
    );
    if (result == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 历史记录缺少有效 resultCode',
      );
    }
    final RoomPkSide left = _sideFromProjection(data['leftRoom'], '历史左侧房间');
    final RoomPkSide right = _sideFromProjection(data['rightRoom'], '历史右侧房间');
    if (left.roomId != leftRoomId ||
        right.roomId != rightRoomId ||
        left.roomId == right.roomId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 历史双方权威投影不一致',
      );
    }
    final RoomPkSide currentSide = left.roomId == currentRoomId ? left : right;
    final RoomPkSide opponentSide = left.roomId == targetRoomId ? left : right;
    return RoomPkRecord(
      id: battleId,
      invitationId: invitationId,
      targetRoomId: targetRoomId,
      battleStatus: status,
      resultCode: _requiredText(data['resultCode'], '结果编码'),
      opponentRoomName: opponentSide.roomName,
      opponentCoverUrl: opponentSide.coverUrl,
      completedAt: completedAt,
      result: result,
      currentScore: currentSide.score,
      opponentScore: opponentSide.score,
    );
  }

  static RoomPkSide _sideFromProjection(Object? raw, String label) {
    final Map<String, Object?> data = _requiredMap(raw, '$label投影');
    final String roomId = _uuid(data['roomId'], '$label ID');
    final String roomCode = _requiredText(data['roomCode'], '$label房间号');
    final String roomName = _requiredText(data['roomName'], '$label名称');
    final int score = _requiredInt(data['score'], '$label比分');
    if (score < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$label比分不能为负数',
      );
    }
    final Object? rawSupporters = data['supporters'];
    if (rawSupporters is! List) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$label缺少支持榜');
    }
    final List<RoomPkSupporter> supporters = <RoomPkSupporter>[];
    final Set<int> seenUsers = <int>{};
    num? previousValue;
    for (final Object? rawSupporter in rawSupporters) {
      final Map<String, Object?> supporter = _requiredMap(
        rawSupporter,
        '$label支持者',
      );
      final int userId = _requiredInt(supporter['userId'], '$label支持者 ID');
      final int value = _requiredInt(supporter['value'], '$label支持值');
      if (userId <= 0 || value < 0 || !seenUsers.add(userId)) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$label支持榜包含无效记录',
        );
      }
      if (previousValue != null && value > previousValue) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$label支持榜排序无效',
        );
      }
      previousValue = value;
      supporters.add(
        RoomPkSupporter(
          userId: userId,
          nickname: _requiredText(supporter['nickname'], '$label支持者昵称'),
          value: value,
          avatarUrl: _optionalText(supporter['avatarUrl']),
        ),
      );
    }
    return RoomPkSide(
      roomId: roomId,
      roomCode: roomCode,
      roomName: roomName,
      score: score,
      coverUrl: _optionalText(data['coverUrl']),
      supporters: List<RoomPkSupporter>.unmodifiable(supporters),
    );
  }

  RoomPkResult? _resultFromProjection(
    Map<String, Object?> data, {
    required String currentRoomId,
    required String targetRoomId,
  }) {
    final String resultCode = _optionalText(data['resultCode']) ?? '';
    if (resultCode == 'DRAW') {
      return RoomPkResult.draw;
    }
    final String? surrenderedRoomId = _optionalUuid(
      data['surrenderedRoomId'],
      '认输房间 ID',
    );
    if (surrenderedRoomId != null) {
      return surrenderedRoomId == currentRoomId
          ? RoomPkResult.surrendered
          : surrenderedRoomId == targetRoomId
          ? RoomPkResult.win
          : null;
    }
    final String? winnerRoomId = _optionalUuid(data['winnerRoomId'], '获胜房间 ID');
    if (winnerRoomId == null || resultCode == 'UNDECIDED') {
      return null;
    }
    if (winnerRoomId == currentRoomId) {
      return RoomPkResult.win;
    }
    if (winnerRoomId == targetRoomId) {
      return RoomPkResult.lose;
    }
    return null;
  }

  void _assertBattleFresh(
    String battleId,
    DateTime updatedAt,
    RoomPkBattleStage stage,
  ) {
    final DateTime? previous = _latestBattleUpdates[battleId];
    if (previous != null && updatedAt.isBefore(previous)) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '收到过期的 PK 对战响应',
      );
    }
    final RoomPkBattleStage? previousStage = _latestBattleStages[battleId];
    if (previousStage == RoomPkBattleStage.completed &&
        stage != RoomPkBattleStage.completed) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '收到过期的 PK 对战状态',
      );
    }
    _latestBattleUpdates[battleId] =
        previous == null || updatedAt.isAfter(previous) ? updatedAt : previous;
    _latestBattleStages[battleId] = stage;
  }

  Future<T> _runWrite<T>({
    required String operation,
    required List<Object?> intentParts,
    required Future<T> Function(Map<String, String> headers) action,
  }) {
    final String intent = _intentKey(operation, intentParts);
    final Future<Object?>? existing = _inFlightWrites[intent];
    if (existing != null) {
      return existing.then<T>((Object? value) => value as T);
    }
    final String requestId = _retainedRequestIds[intent] ??= _newRequestId(
      operation,
    );
    final Future<T> operationFuture =
        action(<String, String>{'X-Request-Id': requestId}).then<T>(
          (T value) {
            _retainedRequestIds.remove(intent);
            return value;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_retainRequestId(error)) {
              _retainedRequestIds.remove(intent);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    final Future<Object?> tracked = operationFuture.then<Object?>(
      (T value) => value,
    );
    _inFlightWrites[intent] = tracked;
    tracked.then<void>(
      (_) => _removeInFlight(intent, tracked),
      onError: (Object _, StackTrace __) => _removeInFlight(intent, tracked),
    );
    return operationFuture;
  }

  void _removeInFlight(String intent, Future<Object?> tracked) {
    if (identical(_inFlightWrites[intent], tracked)) {
      _inFlightWrites.remove(intent);
    }
  }

  static bool _retainRequestId(Object error) {
    if (error is! ApiException) {
      return true;
    }
    if (error.kind == ApiFailureKind.conflict) {
      // F3-A 40901/40902 mean the original operation is still unknown or in
      // progress. Rotating the key could execute the same state transition
      // twice. 40903 and state/business conflicts are definitive and must
      // release the key for a later, new intent.
      return error.code == 40901 || error.code == 40902;
    }
    return switch (error.kind) {
      ApiFailureKind.network ||
      ApiFailureKind.timeout ||
      ApiFailureKind.server ||
      ApiFailureKind.protocol ||
      ApiFailureKind.unauthorized => true,
      _ => false,
    };
  }

  static String _newRequestId(String operation) {
    _requestSequence += 1;
    return 'flutter-room-pk-$operation-${DateTime.now().microsecondsSinceEpoch}-${_requestSequence}';
  }

  static String _intentKey(String operation, List<Object?> values) {
    final String encoded = values.map((Object? value) => '$value').join('|');
    return '$operation:$encoded';
  }

  static _PageRequest _pageRequest(int page, int size) {
    if (page < 1 || size < 1 || size > 50) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '分页参数无效',
      );
    }
    return _PageRequest(page: page, size: size);
  }

  static _PageEnvelope _pageFromResponse(
    Object? raw, {
    required int expectedPage,
    required int expectedPageSize,
  }) {
    final Map<String, Object?> data = _requiredMap(raw, '分页响应');
    final Object? rawRecords = data['records'];
    if (rawRecords is! List) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '分页响应缺少 records',
      );
    }
    final int current = _requiredInt(data['current'], '当前页');
    final int pageSize = _requiredInt(data['pageSize'], '分页大小');
    final int total = _requiredInt(data['total'], '总数');
    if (current != expectedPage ||
        pageSize != expectedPageSize ||
        total < 0 ||
        rawRecords.length > pageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '分页响应与请求不一致',
      );
    }
    final List<Map<String, Object?>> records = <Map<String, Object?>>[];
    for (final Object? value in rawRecords) {
      records.add(_requiredMap(value, '分页记录'));
    }
    return _PageEnvelope(
      records: records,
      page: current,
      size: pageSize,
      total: total,
    );
  }

  static RoomPkOpponent _opponentFromMap(Map<String, Object?> data) {
    _assertVendorBlocked(data);
    final String roomId = _uuid(
      _requiredText(data['roomId'], '房间 ID'),
      '房间 ID',
    );
    final String roomCode = _requiredText(data['roomCode'], '房间号');
    final String roomName = _requiredText(data['roomName'], '房间名称');
    final int onlineUsers = _requiredInt(data['onlineNum'], '在线人数');
    final Object? active = data['hasActivePk'];
    if (active == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间列表缺少 hasActivePk',
      );
    }
    return RoomPkOpponent(
      roomId: roomId,
      roomCode: roomCode,
      roomName: roomName,
      coverUrl: _optionalText(data['coverImgUrl']),
      onlineUsers: onlineUsers,
      isInPk: _asBool(active),
    );
  }

  static RoomPkInvitationStatus? _invitationStatus(Object? value) {
    return switch (_normalizedStatus(value)) {
      'PENDING' => RoomPkInvitationStatus.pending,
      'ACCEPTED' => RoomPkInvitationStatus.accepted,
      'REJECTED' => RoomPkInvitationStatus.rejected,
      'EXPIRED' => RoomPkInvitationStatus.expired,
      'CANCELED' => RoomPkInvitationStatus.canceled,
      _ => null,
    };
  }

  static RoomPkBattleStage? _battleStage(String status) {
    return switch (status) {
      'IN_PROGRESS' => RoomPkBattleStage.fighting,
      'COMPLETED' || 'SURRENDERED' => RoomPkBattleStage.completed,
      'CANCELED' => RoomPkBattleStage.canceled,
      _ => null,
    };
  }

  static String _requiredStatus(Object? value, String label) {
    final String status = _normalizedStatus(value) ?? '';
    if (status.isEmpty) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$label无效');
    }
    return status;
  }

  static String? _normalizedStatus(Object? value) {
    final String text = value?.toString().trim().toUpperCase() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime _requiredDate(Object? value, String label) {
    final DateTime? result = _optionalDate(value, label);
    if (result == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 响应缺少$label',
      );
    }
    return result;
  }

  static DateTime? _optionalDate(Object? value, String label) {
    if (value == null) {
      return null;
    }
    final DateTime? result = value is DateTime
        ? value
        : DateTime.tryParse(value.toString().trim());
    if (result == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 响应的$label无效',
      );
    }
    return result;
  }

  static int _requiredInt(Object? value, String label) {
    final int? result = value is int
        ? value
        : value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (result == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 响应缺少$label',
      );
    }
    return result;
  }

  static String _roomId(String value, String label) => _uuid(value, label);

  static String _uuid(Object? value, String label) {
    final String text = value?.toString().trim() ?? '';
    if (!_canonicalUuid.hasMatch(text)) {
      throw ApiException(
        kind: ApiFailureKind.validation,
        message: '$label必须是小写 canonical UUID',
      );
    }
    return text;
  }

  static String? _optionalUuid(Object? value, String label) {
    if (value == null || value.toString().trim().isEmpty) {
      return null;
    }
    return _uuid(value, label);
  }

  static String _requiredText(Object? value, String label) {
    final String? text = _optionalText(value);
    if (text == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 响应缺少$label',
      );
    }
    return text;
  }

  static String? _optionalText(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static bool _asBool(Object value) {
    if (value is bool) {
      return value;
    }
    if (value is int) {
      return value == 1;
    }
    return value.toString().trim().toLowerCase() == 'true';
  }

  static Map<String, Object?> _requiredMap(Object? value, String label) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? item) => MapEntry(key.toString(), item),
      );
    }
    throw ApiException(kind: ApiFailureKind.protocol, message: '$label结构无法识别');
  }

  static void _assertVendorBlocked(Map<String, Object?> data) {
    if (data['providerInvocation'] != null &&
        data['providerInvocation'] != false) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 响应声明了未授权的 provider 调用',
      );
    }
    if (data['vendorInvocation'] != null && data['vendorInvocation'] != false) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 响应声明了未授权的 vendor 调用',
      );
    }
    for (final String key in <String>['rtcStatus', 'imStatus']) {
      final Object? status = data[key];
      if (status != null && status != 'VENDOR_BLOCKED') {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: 'PK 第三方能力必须保持 VENDOR_BLOCKED',
        );
      }
    }
    if (data['realtimeProvisioned'] != null &&
        data['realtimeProvisioned'] != false) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PK 响应不能伪造实时能力已开通',
      );
    }
  }

  static String _route(String configured, String canonical) {
    // A route catalog can still be supplied by app dependencies, but a stale
    // catalog value must never re-enable the old endpoint.
    return configured == canonical ? configured : canonical;
  }
}

class _PageRequest {
  const _PageRequest({required this.page, required this.size});

  final int page;
  final int size;
}

class _PageEnvelope {
  const _PageEnvelope({
    required this.records,
    required this.page,
    required this.size,
    required this.total,
  });

  final List<Map<String, Object?>> records;
  final int page;
  final int size;
  final int total;
}
