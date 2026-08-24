import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/room_write_guard.dart';

class BackendRoomOperationsRepository
    implements
        RoomOperationsRepository,
        RoomJoinRequestRepository,
        RoomBanRepository {
  static const int _memberPageSize = 50;
  static const int _maximumMemberPages = 100;

  BackendRoomOperationsRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  }) : _apiClient = apiClient,
       _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final RoomWriteGuard _writeGuard = RoomWriteGuard(scope: 'room-operations');
  final Map<String, Map<int, int>> _seatOccupantsByRoom =
      <String, Map<int, int>>{};

  @override
  MicCoordinationMode get micCoordinationMode => MicCoordinationMode.direct;

  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    required int page,
    int pageSize = 20,
  }) async {
    _validateMemberPageRequest(page: page, pageSize: pageSize);
    final ApiResponse response = await _apiClient.post(
      _routes.roomOnlineMembers,
      body: <String, Object?>{
        'roomId': roomId,
        'pageNum': page,
        'pageSize': pageSize,
        'isSearchCount': true,
      },
    );
    final _MemberPageEnvelope envelope = _memberPageEnvelope(
      response.data,
      requestedPage: page,
      requestedPageSize: pageSize,
    );
    final List<RoomMember> members = envelope.items
        .map(_memberFromOnline)
        .toList(growable: false);
    final Map<int, int> seatOccupants = _seatOccupantsByRoom.putIfAbsent(
      roomId,
      () => <int, int>{},
    );
    if (page <= 1) {
      seatOccupants.clear();
    }
    for (final RoomMember member in members) {
      final int? seatNumber = member.seatNumber;
      if (member.userId > 0 && seatNumber != null) {
        seatOccupants[seatNumber] = member.userId;
      }
    }
    return RoomMemberPage(
      items: members,
      page: envelope.current,
      total: envelope.total,
      pages: envelope.pages,
    );
  }

  @override
  Future<List<RoomMember>> fetchOffMicListeners(String roomId) async {
    final List<Map<String, Object?>> items = await _fetchAllMemberPages(
      fetchPage: (int page, int pageSize) => _apiClient.post(
        _routes.roomOffMicMembers,
        body: <String, Object?>{
          'roomId': roomId,
          'pageNum': page,
          'pageSize': pageSize,
        },
      ),
    );
    return items.map(_memberFromOnline).toList(growable: false);
  }

  @override
  Future<List<RoomMember>> fetchManagers(String roomId) async {
    final List<Map<String, Object?>> items = await _fetchAllMemberPages(
      fetchPage: (int page, int pageSize) => _apiClient.get(
        _routes.roomManagers,
        query: <String, String>{
          'roomId': roomId,
          'pageNum': '$page',
          'pageSize': '$pageSize',
        },
      ),
    );
    return items
        .map(
          (Map<String, Object?> item) =>
              _memberFromOnline(item, fallbackRole: RoomRole.moderator),
        )
        .toList(growable: false);
  }

  @override
  Future<List<RoomMember>> fetchMutedUsers(String roomId) async {
    final List<Map<String, Object?>> items = await _fetchAllMemberPages(
      fetchPage: (int page, int pageSize) => _apiClient.get(
        _routes.roomMutedUsers,
        query: <String, String>{
          'roomId': roomId,
          'pageNum': '$page',
          'pageSize': '$pageSize',
        },
      ),
    );
    return items
        .map(
          (Map<String, Object?> item) => RoomMember(
            userId: _requiredMemberId(item),
            name: _string(
              item['nickName'] ?? item['niceName'],
              fallback: '已禁言成员',
            ),
            avatarUrl: _optionalString(item['headImgUrl'] ?? item['avatarUrl']),
            role: _roleFromServer(item['role'] ?? item['userRoomRole']),
            presence: _presenceFrom(item),
            seatNumber: _seatNumber(item),
            isMuted: true,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<RoomJoinRequestPage> fetchJoinRequests({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async {
    _validatePageRequest(page: page, pageSize: pageSize);
    final ApiResponse response = await _apiClient.get(
      _routes.roomJoinRequests,
      query: <String, String>{
        'roomId': roomId,
        'pageNum': '$page',
        'pageSize': '$pageSize',
      },
    );
    final _MemberPageEnvelope envelope = _memberPageEnvelope(
      response.data,
      requestedPage: page,
      requestedPageSize: pageSize,
    );
    return RoomJoinRequestPage(
      items: envelope.items.map(_joinRequestFrom).toList(growable: false),
      page: envelope.current,
      total: envelope.total,
      pages: envelope.pages,
    );
  }

  @override
  Future<RoomJoinRequestApplicantStatus> fetchJoinRequestStatus({
    String? roomId,
    String? joinRequestId,
  }) async {
    final String normalizedRoomId = _optionalIdentifier(roomId, '房间 ID');
    final String normalizedJoinRequestId = _optionalIdentifier(
      joinRequestId,
      '入房申请 ID',
    );
    if (normalizedRoomId.isEmpty && normalizedJoinRequestId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间 ID 或入房申请 ID 至少提供一个',
      );
    }
    final Map<String, String> query = <String, String>{
      if (normalizedRoomId.isNotEmpty) 'roomId': normalizedRoomId,
      if (normalizedJoinRequestId.isNotEmpty)
        'joinRequestId': normalizedJoinRequestId,
    };
    final ApiResponse response = await _apiClient.get(
      _routes.roomJoinRequestStatus,
      query: query,
    );
    final Map<String, Object?> data = _requiredResponseMap(
      response,
      operation: '查询入房申请状态',
      requiredFields: const <String>[
        'roomId',
        'joinRequestId',
        'status',
        'roomState',
        'banned',
        'canCancel',
      ],
    );
    final String responseRoomId = _requiredExactNonEmptyString(data, 'roomId');
    final String responseJoinRequestId = _requiredExactNonEmptyString(
      data,
      'joinRequestId',
    );
    if (normalizedRoomId.isNotEmpty && responseRoomId != normalizedRoomId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '入房申请状态响应房间 ID 不一致',
      );
    }
    if (normalizedJoinRequestId.isNotEmpty &&
        responseJoinRequestId != normalizedJoinRequestId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '入房申请状态响应申请 ID 不一致',
      );
    }
    final RoomJoinRequestStatus status = _roomJoinRequestStatusFrom(
      data['status'],
    );
    final String roomState = _requiredExactNonEmptyString(
      data,
      'roomState',
    ).toUpperCase();
    if (roomState != 'OPEN' && roomState != 'CLOSED') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '入房申请状态包含未知房间状态',
      );
    }
    final bool banned = _requiredBool(data, 'banned');
    final bool canCancel = _requiredBool(data, 'canCancel');
    final bool expectedCanCancel =
        status == RoomJoinRequestStatus.pending &&
        roomState == 'OPEN' &&
        !banned;
    if (canCancel != expectedCanCancel) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '入房申请状态 canCancel 与权威状态不一致',
      );
    }
    return RoomJoinRequestApplicantStatus(
      roomId: responseRoomId,
      joinRequestId: responseJoinRequestId,
      status: status,
      roomState: roomState,
      banned: banned,
      canCancel: canCancel,
      message: _optionalString(data['message']),
      createdAt: _optionalDateTime(data['createdAt']),
      resolvedAt: _optionalDateTime(data['resolvedAt']),
    );
  }

  @override
  Future<RoomJoinRequestCancellation> cancelJoinRequest({
    required String roomId,
    required String joinRequestId,
    String? requestId,
  }) async {
    final String normalizedRoomId = _requiredIdentifier(roomId, '房间 ID');
    final String normalizedJoinRequestId = _requiredIdentifier(
      joinRequestId,
      '入房申请 ID',
    );
    return _writeGuard.run<RoomJoinRequestCancellation>(
      intent:
          'room-join-request-cancel:$normalizedRoomId:$normalizedJoinRequestId',
      requestId: requestId,
      fingerprint:
          'ROOM_JOIN_REQUEST_CANCEL|$normalizedRoomId|$normalizedJoinRequestId',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.cancelRoomJoinRequest,
          headers: headers,
          body: <String, Object?>{
            'roomId': normalizedRoomId,
            'joinRequestId': normalizedJoinRequestId,
          },
        );
        final Map<String, Object?> data = _requiredResponseMap(
          response,
          operation: '撤收入房申请',
          requiredFields: const <String>[
            'roomId',
            'joinRequestId',
            'status',
            'cancelled',
            'alreadyCancelled',
          ],
        );
        if (_requiredExactNonEmptyString(data, 'roomId') != normalizedRoomId) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '撤回申请响应房间 ID 不一致',
          );
        }
        if (_requiredExactNonEmptyString(data, 'joinRequestId') !=
            normalizedJoinRequestId) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '撤回申请响应申请 ID 不一致',
          );
        }
        final RoomJoinRequestStatus status = _roomJoinRequestStatusFrom(
          data['status'],
        );
        if (status != RoomJoinRequestStatus.cancelled) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '撤回申请响应状态不一致',
          );
        }
        final bool cancelled = _requiredBool(data, 'cancelled');
        if (!cancelled) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '撤回申请响应未确认已撤回',
          );
        }
        return RoomJoinRequestCancellation(
          roomId: normalizedRoomId,
          joinRequestId: normalizedJoinRequestId,
          status: status,
          cancelled: cancelled,
          alreadyCancelled: _requiredBool(data, 'alreadyCancelled'),
        );
      },
    );
  }

  @override
  Future<void> resolveJoinRequest({
    required String joinRequestId,
    required bool approved,
    String? requestId,
  }) async {
    final String normalizedId = joinRequestId.trim();
    if (normalizedId.isEmpty || normalizedId.length > 64) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '入房申请 ID 无效',
      );
    }
    await _writeGuard.run<void>(
      intent: 'room-join-request:$normalizedId:$approved',
      action: (Map<String, String> headers) async {
        if (requestId != null && requestId.trim().isNotEmpty) {
          headers['X-Request-Id'] = requestId.trim();
        }
        final ApiResponse response = await _apiClient.post(
          _routes.resolveRoomJoinRequest,
          headers: headers,
          body: <String, Object?>{
            'joinRequestId': normalizedId,
            'approved': approved,
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: approved ? '同意入房申请' : '拒绝入房申请',
          requiredFields: <String>['joinRequestId', 'status'],
        );
        if (_requiredExactNonEmptyString(data, 'joinRequestId') !=
            normalizedId) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '入房申请审核响应与请求 ID 不一致',
          );
        }
        final String expected = approved ? 'APPROVED' : 'REJECTED';
        if (_string(data['status'], fallback: '').toUpperCase() != expected) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '入房申请审核响应状态不一致',
          );
        }
      },
    );
  }

  @override
  Future<RoomBannedUserPage> fetchBannedUsers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async {
    _validatePageRequest(page: page, pageSize: pageSize);
    final ApiResponse response = await _apiClient.get(
      _routes.roomBannedUsers,
      query: <String, String>{
        'roomId': roomId,
        'pageNum': '$page',
        'pageSize': '$pageSize',
      },
    );
    final _MemberPageEnvelope envelope = _memberPageEnvelope(
      response.data,
      requestedPage: page,
      requestedPageSize: pageSize,
    );
    return RoomBannedUserPage(
      items: envelope.items.map(_bannedUserFrom).toList(growable: false),
      page: envelope.current,
      total: envelope.total,
      pages: envelope.pages,
    );
  }

  @override
  Future<void> unbanUser({
    required String roomId,
    required int userId,
    String? requestId,
  }) async {
    final String normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || userId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '解封目标无效',
      );
    }
    await _writeGuard.run<void>(
      intent: 'room-unban:$normalizedRoomId:$userId',
      action: (Map<String, String> headers) async {
        if (requestId != null && requestId.trim().isNotEmpty) {
          headers['X-Request-Id'] = requestId.trim();
        }
        final ApiResponse response = await _apiClient.post(
          _routes.unbanRoomUser,
          headers: headers,
          body: <String, Object?>{'roomId': normalizedRoomId, 'userId': userId},
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: '解除房间限制',
          requiredFields: <String>['roomId', 'userId', 'banned'],
        );
        _assertRoom(data, normalizedRoomId, operation: '解除房间限制');
        _assertUser(data, userId, operation: '解除房间限制');
        if (_asBool(data['banned'])) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '解除房间限制响应仍为 banned=true',
          );
        }
      },
    );
  }

  @override
  Future<RoomTopic> fetchTopic(String roomId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.roomTopic,
      query: <String, String>{'roomId': roomId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (_requiredExactNonEmptyString(data, 'roomId') != roomId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间话题响应与请求房间 ID 不一致',
      );
    }
    return RoomTopic(
      title: _string(data['topicTitle'], fallback: ''),
      content: _string(data['topic'] ?? data['topicContent'], fallback: ''),
      version: _requiredNonNegativeInt(data, 'version'),
    );
  }

  @override
  Future<void> updateTopic({
    required String roomId,
    required RoomTopic topic,
  }) async {
    final String normalizedTopic = topic.content.trim().isEmpty
        ? topic.title.trim()
        : topic.content.trim();
    final int expectedVersion = _requireExpectedVersion(
      topic.version,
      operation: '更新房间话题',
    );
    await _writeGuard.run<void>(
      intent: 'topic:$roomId:$normalizedTopic:$expectedVersion',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.updateRoomTopic,
          headers: headers,
          body: <String, Object?>{
            'roomId': roomId,
            'topic': normalizedTopic,
            'expectedVersion': expectedVersion,
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: '更新房间话题',
          requiredFields: <String>['roomId', 'topic', 'welcomeText', 'version'],
        );
        _assertRoom(data, roomId, operation: '更新房间话题');
        final int responseVersion = _requiredNonNegativeInt(data, 'version');
        if (_string(data['topic'], fallback: '') != normalizedTopic ||
            responseVersion != _nextVersion(expectedVersion)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '更新房间话题响应与请求不一致',
          );
        }
      },
    );
  }

  @override
  Future<void> setUserMuted({
    required String roomId,
    required int userId,
    required bool muted,
  }) async {
    await _writeGuard.run<void>(
      intent: 'mute:$roomId:$userId:$muted',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.setRoomUserMuted,
          headers: headers,
          body: <String, Object?>{
            'roomId': roomId,
            'targetUserId': userId,
            'muted': muted,
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: muted ? '禁言成员' : '解除成员禁言',
          requiredFields: <String>['roomId', 'userId', 'muted'],
        );
        _assertRoom(data, roomId, operation: '成员禁言');
        _assertUser(data, userId, operation: '成员禁言');
        if (_asBool(data['muted']) != muted) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '成员禁言响应与请求不一致',
          );
        }
      },
    );
  }

  @override
  Future<void> setUserRole({
    required String roomId,
    required int userId,
    required bool manager,
  }) async {
    await _writeGuard.run<void>(
      intent: 'role:$roomId:$userId:$manager',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.setRoomUserRole,
          headers: headers,
          body: <String, Object?>{
            'roomId': roomId,
            'targetUserId': userId,
            'role': manager ? 'MANAGER' : 'MEMBER',
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: manager ? '设置房管' : '解除房管',
          requiredFields: <String>['roomId', 'userId', 'role'],
        );
        _assertRoom(data, roomId, operation: '成员角色变更');
        _assertUser(data, userId, operation: '成员角色变更');
        final String expectedRole = manager ? 'MANAGER' : 'MEMBER';
        if (_string(data['role'], fallback: '').toUpperCase() != expectedRole) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '成员角色变更响应与请求不一致',
          );
        }
      },
    );
  }

  @override
  Future<void> kickUser({required String roomId, required int userId}) async {
    await _writeGuard.run<void>(
      intent: 'kick:$roomId:$userId',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.kickRoomUser,
          headers: headers,
          body: <String, Object?>{
            'roomId': roomId,
            'targetUserId': userId,
            'ban': true,
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: '移出成员',
          requiredFields: <String>['roomId', 'userId', 'kicked'],
        );
        _assertRoom(data, roomId, operation: '移出成员');
        _assertUser(data, userId, operation: '移出成员');
        if (!_asBool(data['kicked'])) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '移出成员响应未确认 kicked=true',
          );
        }
      },
    );
  }

  @override
  Future<void> takeUserOffMic({
    required String roomId,
    required int backendMicIndex,
    required int userId,
  }) async {
    await _writeGuard.run<void>(
      intent: 'off-mic:$roomId:$userId:$backendMicIndex',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.takeUserOffMic,
          headers: headers,
          body: <String, Object?>{
            'roomId': roomId,
            'targetUserId': userId,
            'seatNumber': backendMicIndex,
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: '移下成员麦位',
          requiredFields: <String>['roomId', 'userId', 'offMic'],
        );
        _assertRoom(data, roomId, operation: '移下成员麦位');
        _assertUser(data, userId, operation: '移下成员麦位');
        if (!_asBool(data['offMic'])) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '移下成员麦位响应未确认 offMic=true',
          );
        }
      },
    );
  }

  @override
  Future<void> setSeatLocked({
    required String roomId,
    required int backendMicIndex,
    required bool locked,
  }) async {
    await _writeGuard.run<void>(
      intent: 'seat-lock:$roomId:$backendMicIndex:$locked',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          locked ? _routes.lockMic : _routes.unlockMic,
          headers: headers,
          body: <String, Object?>{
            'roomId': roomId,
            'seatNumber': backendMicIndex,
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: locked ? '锁定麦位' : '解锁麦位',
          requiredFields: <String>['roomId', 'seatNumber', 'locked'],
        );
        _assertRoom(data, roomId, operation: '麦位锁定');
        _assertSeat(data, backendMicIndex, operation: '麦位锁定');
        if (_asBool(data['locked']) != locked) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '麦位锁定响应与请求不一致',
          );
        }
      },
    );
  }

  @override
  Future<void> setSeatMuted({
    required String roomId,
    required int backendMicIndex,
    required bool muted,
  }) async {
    final int? userId = _seatOccupantsByRoom[roomId]?[backendMicIndex];
    if (userId == null) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '该麦位当前没有可确认的成员，拒绝对错误用户执行闭麦操作',
      );
    }
    await _writeGuard.run<void>(
      intent: 'seat-mute:$roomId:$backendMicIndex:$userId:$muted',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          muted ? _routes.closeMic : _routes.openMic,
          headers: headers,
          body: <String, Object?>{
            'roomId': roomId,
            'userId': userId,
            'seatNumber': backendMicIndex,
            'muted': muted,
          },
        );
        final Map<String, Object?> data = _requiredMutationMap(
          response,
          operation: muted ? '闭麦' : '开麦',
          requiredFields: <String>['roomId', 'seatNumber', 'userId', 'muted'],
        );
        _assertRoom(data, roomId, operation: '麦位闭麦');
        _assertSeat(data, backendMicIndex, operation: '麦位闭麦');
        _assertUser(data, userId, operation: '麦位闭麦');
        if (_asBool(data['muted']) != muted) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '麦位闭麦响应与请求不一致',
          );
        }
      },
    );
  }

  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) async =>
      const <MicAccessRequest>[];

  @override
  Future<void> submitMicRequest({
    required String roomId,
    required int userId,
    required int seatNumber,
  }) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '当前后端普通房为直接上麦模式，不存在申请队列',
    );
  }

  @override
  Future<void> cancelMicRequest({required String requestId}) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '当前后端普通房为直接上麦模式，不存在申请队列',
    );
  }

  @override
  Future<void> resolveMicRequest({
    required String requestId,
    required bool accepted,
  }) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '当前后端未提供普通房上麦申请审批协议',
    );
  }

  @override
  Future<void> inviteUserToMic({
    required String roomId,
    required int userId,
    required int seatNumber,
  }) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '当前后端只存在强制抱麦接口，客户端不会将其作为邀请上麦使用',
    );
  }

  Future<List<Map<String, Object?>>> _fetchAllMemberPages({
    required Future<ApiResponse> Function(int page, int pageSize) fetchPage,
  }) async {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    final Set<int> seenUserIds = <int>{};
    _MemberPageEnvelope? expected;
    int requestedPage = 1;

    while (true) {
      if (requestedPage > _maximumMemberPages) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间成员分页超过客户端安全上限',
        );
      }
      final _MemberPageEnvelope envelope = _memberPageEnvelope(
        (await fetchPage(requestedPage, _memberPageSize)).data,
        requestedPage: requestedPage,
        requestedPageSize: _memberPageSize,
      );
      if (envelope.pages > _maximumMemberPages) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间成员分页超过客户端安全上限',
        );
      }
      if (expected == null) {
        expected = envelope;
      } else if (envelope.total != expected.total ||
          envelope.pages != expected.pages ||
          envelope.pageSize != expected.pageSize ||
          envelope.size != expected.size) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间成员分页元数据在请求间发生变化',
        );
      }

      for (final Map<String, Object?> item in envelope.items) {
        final int userId = _requiredMemberId(item);
        if (!seenUserIds.add(userId)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '房间成员分页包含重复成员',
          );
        }
        items.add(item);
      }

      if (envelope.pages == 0 || envelope.current == envelope.pages) {
        if (items.length != envelope.total) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '房间成员记录总数与服务端 total 不一致',
          );
        }
        return items;
      }
      if (envelope.items.isEmpty) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间成员分页仍有后续页但当前页为空',
        );
      }
      final int nextPage = envelope.current + 1;
      if (nextPage <= requestedPage || nextPage > _maximumMemberPages) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间成员分页未向前推进',
        );
      }
      requestedPage = nextPage;
    }
  }

  static RoomMember _memberFromOnline(
    Map<String, Object?> item, {
    RoomRole fallbackRole = RoomRole.listener,
  }) {
    final int userId = _requiredMemberId(item);
    return RoomMember(
      userId: userId,
      name: _string(item['nickName'] ?? item['name'], fallback: '房间成员'),
      avatarUrl: _optionalString(item['headImgUrl'] ?? item['avatarUrl']),
      role: item.containsKey('role') || item.containsKey('userRoomRole')
          ? _roleFromServer(item['role'] ?? item['userRoomRole'])
          : fallbackRole,
      presence: _presenceFrom(item),
      seatNumber: _seatNumber(item),
      isMuted: _asBool(item['muted']) || _asBool(item['isMuted']),
      wealthLevel: _asInt(item['wealthLevel']) ?? 0,
      charmLevel: _asInt(item['charmLevel']) ?? 0,
    );
  }

  static RoomJoinRequest _joinRequestFrom(Map<String, Object?> item) {
    final String id = _requiredExactNonEmptyString(item, 'joinRequestId');
    final RoomJoinRequestStatus status = _roomJoinRequestStatusFrom(
      item['status'],
    );
    final int userId = _requiredMemberId(item);
    return RoomJoinRequest(
      id: id,
      member: RoomMember(
        userId: userId,
        name: _string(item['nickName'] ?? item['name'], fallback: '申请用户'),
        avatarUrl: _optionalString(item['headImgUrl'] ?? item['avatarUrl']),
        role: RoomRole.listener,
        presence: RoomMemberPresence.listener,
      ),
      status: status,
      message: _optionalString(item['message']),
      createdAt: _optionalDateTime(item['createdAt']),
      resolvedAt: _optionalDateTime(item['resolvedAt']),
    );
  }

  static RoomBannedUser _bannedUserFrom(Map<String, Object?> item) {
    final int userId = _requiredMemberId(item);
    return RoomBannedUser(
      member: RoomMember(
        userId: userId,
        name: _string(item['nickName'] ?? item['name'], fallback: '受限用户'),
        avatarUrl: _optionalString(item['headImgUrl'] ?? item['avatarUrl']),
        role: RoomRole.listener,
        presence: RoomMemberPresence.listener,
      ),
      reason: _optionalString(item['reason']),
      bannedAt: _optionalDateTime(item['bannedAt']),
      expiresAt: _optionalDateTime(item['expiresAt']),
    );
  }

  static RoomRole _roleFromServer(Object? role) {
    final int? numeric = _asInt(role);
    if (numeric != null) {
      return switch (numeric) {
        1 || 5 => RoomRole.moderator,
        2 => RoomRole.platformModerator,
        3 => RoomRole.owner,
        _ => RoomRole.listener,
      };
    }
    return switch (role?.toString().trim().toUpperCase()) {
      'OWNER' => RoomRole.owner,
      'MANAGER' || 'MODERATOR' => RoomRole.moderator,
      'PLATFORM_MODERATOR' => RoomRole.platformModerator,
      'SPEAKER' => RoomRole.speaker,
      _ => RoomRole.listener,
    };
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};

  static String _requiredExactNonEmptyString(
    Map<String, Object?> data,
    String field,
  ) {
    final Object? value = data[field];
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应字段 $field 必须为无空白非空字符串',
      );
    }
    return value;
  }

  static int _requiredNonNegativeInt(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! int || value < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应字段 $field 必须为非负整数',
      );
    }
    return value;
  }

  static int _requireExpectedVersion(
    int? version, {
    required String operation,
  }) {
    if (version == null || version < 0) {
      throw ApiException(
        kind: ApiFailureKind.validation,
        message: '$operation 缺少有效的房间版本，请刷新后重试',
      );
    }
    return version;
  }

  static int _nextVersion(int version) => version + 1;

  static Map<String, Object?> _requiredMutationMap(
    ApiResponse response, {
    required String operation,
    required Iterable<String> requiredFields,
  }) {
    RoomWriteGuard.validateMutationResponse(
      response,
      operation: operation,
      requiredFields: requiredFields,
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$operation 响应结构为空',
      );
    }
    return data;
  }

  static Map<String, Object?> _requiredResponseMap(
    ApiResponse response, {
    required String operation,
    required Iterable<String> requiredFields,
  }) {
    final Object? rawData = response.data;
    if (rawData is! Map) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$operation 响应结构无法识别',
      );
    }
    final Map<String, Object?> data = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in rawData.entries)
        entry.key.toString(): entry.value,
    };
    if (data.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$operation 响应结构为空',
      );
    }
    for (final String field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$operation 响应缺少权威字段 $field',
        );
      }
    }
    final Object? successValue = data.containsKey('success')
        ? data['success']
        : data.containsKey('isSuccess')
        ? data['isSuccess']
        : null;
    if (data.containsKey('success') || data.containsKey('isSuccess')) {
      if (successValue is! bool) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$operation 成功字段无法识别',
        );
      }
      if (!successValue) {
        throw ApiException(
          kind: ApiFailureKind.business,
          message: '$operation 未被服务端接受',
        );
      }
    }
    return data;
  }

  static RoomJoinRequestStatus _roomJoinRequestStatusFrom(Object? value) {
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '入房申请状态字段无法识别',
      );
    }
    return switch (value.toUpperCase()) {
      'PENDING' => RoomJoinRequestStatus.pending,
      'CANCELLED' => RoomJoinRequestStatus.cancelled,
      'APPROVED' => RoomJoinRequestStatus.approved,
      'REJECTED' => RoomJoinRequestStatus.rejected,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '入房申请包含未知状态',
      ),
    };
  }

  static bool _requiredBool(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! bool) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应字段 $field 必须为布尔值',
      );
    }
    return value;
  }

  static String _optionalIdentifier(String? value, String label) {
    if (value == null) {
      return '';
    }
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized.length > 64 || normalized != value) {
      throw ApiException(kind: ApiFailureKind.validation, message: '$label 无效');
    }
    return normalized;
  }

  static String _requiredIdentifier(String value, String label) {
    final String normalized = _optionalIdentifier(value, label);
    if (normalized.isEmpty) {
      throw ApiException(kind: ApiFailureKind.validation, message: '$label 无效');
    }
    return normalized;
  }

  static void _assertRoom(
    Map<String, Object?> data,
    String roomId, {
    required String operation,
  }) {
    if (_string(data['roomId'], fallback: '') != roomId) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$operation 响应房间 ID 不一致',
      );
    }
  }

  static void _assertUser(
    Map<String, Object?> data,
    int userId, {
    required String operation,
  }) {
    if (_asInt(data['userId']) != userId) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$operation 响应用户 ID 不一致',
      );
    }
  }

  static void _assertSeat(
    Map<String, Object?> data,
    int seatNumber, {
    required String operation,
  }) {
    if (_asInt(data['seatNumber']) != seatNumber) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$operation 响应麦位编号不一致',
      );
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return switch (value?.toString().trim().toLowerCase()) {
      'true' || '1' || 'yes' => true,
      _ => false,
    };
  }

  static RoomMemberPresence _presenceFrom(Map<String, Object?> item) {
    if (_asBool(item['onMic']) || _seatNumber(item) != null) {
      return RoomMemberPresence.onMic;
    }
    return switch (item['presence']?.toString().trim().toUpperCase()) {
      'ON_MIC' || 'MIC' || 'SPEAKING' => RoomMemberPresence.onMic,
      _ => RoomMemberPresence.listener,
    };
  }

  static int? _seatNumber(Map<String, Object?> item) {
    final int value = _asInt(item['seatNumber']) ?? 0;
    return value > 0 ? value : null;
  }

  static _MemberPageEnvelope _memberPageEnvelope(
    Object? value, {
    required int requestedPage,
    required int requestedPageSize,
  }) {
    final Map<String, Object?> data = _requiredObjectMap(value);
    final List<Object?> rawItems = _requiredMemberItems(data);
    final int current = _requiredMemberPageField(
      data,
      field: 'current',
      allowZero: false,
    );
    final int pageSize = _requiredMemberPageField(
      data,
      field: 'pageSize',
      allowZero: false,
    );
    final int size = _requiredMemberPageField(
      data,
      field: 'size',
      allowZero: false,
    );
    final int total = _requiredMemberPageField(
      data,
      field: 'total',
      allowZero: true,
    );
    final int pages = _requiredMemberPageField(
      data,
      field: 'pages',
      allowZero: true,
    );
    if (current != requestedPage ||
        pageSize != requestedPageSize ||
        size != requestedPageSize ||
        pageSize != size) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员分页 current 或 pageSize 与请求不一致',
      );
    }
    final int expectedPages = total == 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    if (pages != expectedPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员分页 pages 与 total 不一致',
      );
    }
    final int expectedItemCount = _expectedMemberItemCount(
      current: current,
      pageSize: pageSize,
      total: total,
      pages: pages,
    );
    if (rawItems.length != expectedItemCount) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员分页记录数量与 total 不一致',
      );
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (final Object? rawItem in rawItems) _requiredObjectMap(rawItem),
    ];
    return _MemberPageEnvelope(
      items: items,
      current: current,
      pageSize: pageSize,
      size: size,
      total: total,
      pages: pages,
    );
  }

  static List<Object?> _requiredMemberItems(Map<String, Object?> data) {
    final bool hasList = data.containsKey('list');
    final bool hasRecords = data.containsKey('records');
    if (!hasList || !hasRecords) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员分页必须同时包含 list 与 records',
      );
    }
    final List<Object?> list = _requiredObjectList(data['list']);
    final List<Object?> records = _requiredObjectList(data['records']);
    if (!_sameValue(list, records)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员分页 list 与 records 不一致',
      );
    }
    return list;
  }

  static Map<String, Object?> _requiredObjectMap(Object? value) {
    if (value is! Map) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员响应包含非对象结构',
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间成员响应包含非字符串字段名',
        );
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _requiredObjectList(Object? value) {
    if (value is! List) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员分页列表结构无法识别',
      );
    }
    return value.toList(growable: false);
  }

  static bool _sameValue(Object? left, Object? right) {
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final Object? key in left.keys) {
        if (!right.containsKey(key) || !_sameValue(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (int index = 0; index < left.length; index++) {
        if (!_sameValue(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  static int _requiredMemberPageField(
    Map<String, Object?> data, {
    required String field,
    required bool allowZero,
  }) {
    final int? value = _asInt(data[field]);
    if (value == null || value < (allowZero ? 0 : 1)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员分页 $field 不是有效服务端数字',
      );
    }
    return value;
  }

  static int _expectedMemberItemCount({
    required int current,
    required int pageSize,
    required int total,
    required int pages,
  }) {
    if (pages == 0) return 0;
    final int offset = (current - 1) * pageSize;
    return (total - offset).clamp(0, pageSize).toInt();
  }

  static int _requiredMemberId(Map<String, Object?> item) {
    final int? userId = _asInt(item['userId']);
    final int? legacyId = _asInt(item['id']);
    if (userId != null && legacyId != null && userId != legacyId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员 userId 与 id 不一致',
      );
    }
    final int? resolved = userId ?? legacyId;
    if (resolved == null || resolved <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间成员缺少有效 userId',
      );
    }
    return resolved;
  }

  static void _validateMemberPageRequest({
    required int page,
    required int pageSize,
  }) {
    if (page < 1 || pageSize < 1 || pageSize > _memberPageSize) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间成员分页请求参数无效',
      );
    }
  }

  static String _string(Object? value, {required String fallback}) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _optionalString(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _optionalDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    final String text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(text);
    if (parsed == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间运营时间字段无法解析',
      );
    }
    return parsed;
  }

  static void _validatePageRequest({required int page, required int pageSize}) {
    if (page < 1 || pageSize < 1 || pageSize > _memberPageSize) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间运营分页请求参数无效',
      );
    }
  }
}

class _MemberPageEnvelope {
  const _MemberPageEnvelope({
    required this.items,
    required this.current,
    required this.pageSize,
    required this.size,
    required this.total,
    required this.pages,
  });

  final List<Map<String, Object?>> items;
  final int current;
  final int pageSize;
  final int size;
  final int total;
  final int pages;
}
