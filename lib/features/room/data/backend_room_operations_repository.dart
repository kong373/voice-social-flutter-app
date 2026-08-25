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
  final Map<String, MicAccessRequest> _micRequestsById =
      <String, MicAccessRequest>{};
  MicCoordinationMode _micCoordinationMode = MicCoordinationMode.unavailable;

  @override
  MicCoordinationMode get micCoordinationMode => _micCoordinationMode;

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
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) async {
    final String normalizedRoomId = _requiredIdentifier(roomId, '房间 ID');
    final ApiResponse response = await _apiClient.get(
      _routes.roomMicRequests,
      query: <String, String>{'roomId': normalizedRoomId},
    );
    final Map<String, Object?> data = _requiredResponseMap(
      response,
      operation: '查询上麦申请队列',
      requiredFields: const <String>[
        'list',
        'records',
        'total',
        'roomId',
        'coordinationMode',
        'providerInvocation',
      ],
    );
    _assertRoom(data, normalizedRoomId, operation: '查询上麦申请队列');
    final Object? mode = data['coordinationMode'];
    if (mode is! String || mode != 'APPROVAL') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请队列未确认 APPROVAL 协调模式',
      );
    }
    if (data['providerInvocation'] is! bool ||
        data['providerInvocation'] != false) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请队列不允许调用音频或 RTC provider',
      );
    }
    final List<Object?> list = _requiredObjectList(data['list']);
    final List<Object?> records = _requiredObjectList(data['records']);
    if (!_sameValue(list, records)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请队列 list 与 records 不一致',
      );
    }
    final int? total = _strictInt(data['total']);
    if (total == null || total < 0 || total != list.length) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请队列 total 与记录数量不一致',
      );
    }
    final List<MicAccessRequest> requests = <MicAccessRequest>[
      for (final Object? raw in list)
        _micRequestFromMap(
          _requiredObjectMap(raw),
          expectedRoomId: normalizedRoomId,
        ),
    ];
    _micCoordinationMode = MicCoordinationMode.approval;
    _micRequestsById.addEntries(
      requests.map(
        (MicAccessRequest request) =>
            MapEntry<String, MicAccessRequest>(request.id, request),
      ),
    );
    return List<MicAccessRequest>.unmodifiable(requests);
  }

  @override
  Future<void> submitMicRequest({
    required String roomId,
    required int userId,
    required int seatNumber,
  }) async {
    final String normalizedRoomId = _requiredIdentifier(roomId, '房间 ID');
    if (userId <= 0 || seatNumber < 1 || seatNumber > 8) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '上麦申请成员或麦位无效',
      );
    }
    await _writeGuard.run<void>(
      intent: 'mic-request-submit:$normalizedRoomId:$userId:$seatNumber',
      fingerprint:
          'ROOM_MIC_REQUEST_SUBMIT|$normalizedRoomId|$userId|$seatNumber',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.roomMicRequests,
          headers: headers,
          // X-Request-Id is transport-only. The JSON requestId field is
          // reserved for the persisted entity ID on cancel/resolve.
          body: <String, Object?>{
            'roomId': normalizedRoomId,
            'seatNumber': seatNumber,
          },
        );
        final Map<String, Object?> data = _requiredMicMutationMap(
          response,
          operation: '提交上麦申请',
          requiredFields: const <String>[
            'requestId',
            'id',
            'roomId',
            'requestType',
            'type',
            'requestedByUserId',
            'subjectUserId',
            'seatNumber',
            'status',
            'providerInvocation',
          ],
        );
        final MicAccessRequest request = _micRequestFromMap(
          data,
          expectedRoomId: normalizedRoomId,
        );
        if (!request.isRequest ||
            request.requestedByUserId != userId ||
            request.subjectUserId != userId ||
            request.seatNumber != seatNumber ||
            request.status != MicRequestStatus.pending) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '提交上麦申请响应与请求意图不一致',
          );
        }
        _micCoordinationMode = MicCoordinationMode.approval;
        _micRequestsById[request.id] = request;
      },
    );
  }

  @override
  Future<void> cancelMicRequest({required String requestId}) async {
    final String normalizedRequestId = _requiredIdentifier(
      requestId,
      '上麦申请 ID',
    );
    await _writeGuard.run<void>(
      intent: 'mic-request-cancel:$normalizedRequestId',
      fingerprint: 'ROOM_MIC_REQUEST_CANCEL|$normalizedRequestId',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.cancelRoomMicRequest,
          headers: headers,
          body: <String, Object?>{'requestId': normalizedRequestId},
        );
        final Map<String, Object?> data = _requiredMicMutationMap(
          response,
          operation: '撤回上麦申请',
          requiredFields: const <String>[
            'requestId',
            'id',
            'roomId',
            'requestType',
            'type',
            'status',
            'providerInvocation',
          ],
        );
        final MicAccessRequest? known = _micRequestsById[normalizedRequestId];
        final MicAccessRequest request = _micRequestFromMap(
          data,
          expectedRoomId: known?.roomId,
        );
        if (request.id != normalizedRequestId ||
            !request.isRequest ||
            (known != null &&
                (request.type != known.type ||
                    request.subjectUserId != known.subjectUserId ||
                    request.seatNumber != known.seatNumber)) ||
            request.status != MicRequestStatus.cancelled) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '撤回上麦申请响应与请求不一致',
          );
        }
        _micRequestsById[request.id] = request;
      },
    );
  }

  @override
  Future<void> resolveMicRequest({
    required String requestId,
    required bool accepted,
  }) async {
    final String normalizedRequestId = _requiredIdentifier(
      requestId,
      '上麦申请 ID',
    );
    await _writeGuard.run<void>(
      intent: 'mic-request-resolve:$normalizedRequestId:$accepted',
      fingerprint: 'ROOM_MIC_REQUEST_RESOLVE|$normalizedRequestId|$accepted',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.resolveRoomMicRequest,
          headers: headers,
          // The backend accepts one strict boolean decision. Do not send both
          // accepted and approved aliases and never place the transport id in
          // this entity-id body field.
          body: <String, Object?>{
            'requestId': normalizedRequestId,
            'accepted': accepted,
          },
        );
        final Map<String, Object?> data = _requiredMicMutationMap(
          response,
          operation: accepted ? '接受上麦邀请/申请' : '拒绝上麦邀请/申请',
          requiredFields: const <String>[
            'requestId',
            'id',
            'roomId',
            'requestType',
            'type',
            'status',
            'providerInvocation',
          ],
        );
        _assertStrictDecisionAliases(data);
        final MicAccessRequest? known = _micRequestsById[normalizedRequestId];
        final MicAccessRequest request = _micRequestFromMap(
          data,
          expectedRoomId: known?.roomId,
        );
        final MicRequestStatus expected = accepted
            ? MicRequestStatus.approved
            : MicRequestStatus.rejected;
        if (request.id != normalizedRequestId ||
            (known != null &&
                (request.type != known.type ||
                    request.subjectUserId != known.subjectUserId ||
                    request.seatNumber != known.seatNumber)) ||
            request.status != expected) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '处理上麦申请响应状态与请求意图不一致',
          );
        }
        if (accepted) {
          final Object? assigned = data['seatAssigned'];
          if (assigned is! bool || !assigned) {
            throw const ApiException(
              kind: ApiFailureKind.protocol,
              message: '接受上麦申请响应未确认第一方麦位状态',
            );
          }
        } else if (data.containsKey('seatAssigned') &&
            data['seatAssigned'] is! bool) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '拒绝上麦申请响应 seatAssigned 类型无效',
          );
        }
        _micRequestsById[request.id] = request;
      },
    );
  }

  @override
  Future<void> inviteUserToMic({
    required String roomId,
    required int userId,
    required int seatNumber,
  }) async {
    final String normalizedRoomId = _requiredIdentifier(roomId, '房间 ID');
    if (userId <= 0 || seatNumber < 1 || seatNumber > 8) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '邀请成员或麦位无效',
      );
    }
    await _writeGuard.run<void>(
      intent: 'mic-invite:$normalizedRoomId:$userId:$seatNumber',
      fingerprint: 'ROOM_MIC_INVITE|$normalizedRoomId|$userId|$seatNumber',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.inviteRoomMicRequest,
          headers: headers,
          body: <String, Object?>{
            'roomId': normalizedRoomId,
            'userId': userId,
            'seatNumber': seatNumber,
          },
        );
        final Map<String, Object?> data = _requiredMicMutationMap(
          response,
          operation: '邀请成员上麦',
          requiredFields: const <String>[
            'requestId',
            'id',
            'roomId',
            'requestType',
            'type',
            'requestedByUserId',
            'subjectUserId',
            'seatNumber',
            'status',
            'providerInvocation',
          ],
        );
        final MicAccessRequest request = _micRequestFromMap(
          data,
          expectedRoomId: normalizedRoomId,
        );
        if (!request.isInvite ||
            request.subjectUserId != userId ||
            request.seatNumber != seatNumber ||
            request.status != MicRequestStatus.pending) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '邀请上麦响应与请求意图不一致',
          );
        }
        _micCoordinationMode = MicCoordinationMode.approval;
        _micRequestsById[request.id] = request;
      },
    );
  }

  static Map<String, Object?> _requiredMicMutationMap(
    ApiResponse response, {
    required String operation,
    required Iterable<String> requiredFields,
  }) => _requiredResponseMap(
    response,
    operation: operation,
    requiredFields: requiredFields,
  );

  static MicAccessRequest _micRequestFromMap(
    Map<String, Object?> data, {
    String? expectedRoomId,
  }) {
    final String id = _requiredStrictString(data, 'requestId');
    final String legacyId = _requiredStrictString(data, 'id');
    if (id != legacyId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 requestId 与 id 不一致',
      );
    }
    final String roomId = _requiredStrictString(data, 'roomId');
    if (expectedRoomId != null && roomId != expectedRoomId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请响应房间 ID 不一致',
      );
    }
    final String requestTypeValue = _requiredStrictString(data, 'requestType');
    final String typeAlias = _requiredStrictString(data, 'type');
    if (requestTypeValue != typeAlias) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请类型别名不一致',
      );
    }
    final MicRequestType type = switch (requestTypeValue) {
      'REQUEST' => MicRequestType.request,
      'INVITE' => MicRequestType.invite,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请包含未知 requestType',
      ),
    };
    final int requestedByUserId = _requiredAliasInt(
      data,
      const <String>['requestedByUserId', 'requesterUserId'],
      label: 'requestedByUserId',
      allowZero: false,
    );
    final int subjectUserId = _requiredAliasInt(
      data,
      const <String>['subjectUserId', 'targetUserId', 'userId'],
      label: 'subjectUserId',
      allowZero: false,
    );
    final int? inviterUserId = data.containsKey('inviterUserId')
        ? _requiredAliasInt(
            data,
            const <String>['inviterUserId'],
            label: 'inviterUserId',
            allowZero: true,
          )
        : null;
    if (type == MicRequestType.request && requestedByUserId != subjectUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'REQUEST 的申请人与目标成员不一致',
      );
    }
    if (type == MicRequestType.invite &&
        (inviterUserId == null || inviterUserId != requestedByUserId)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'INVITE 的邀请人身份不一致',
      );
    }
    if (type == MicRequestType.request &&
        inviterUserId != null &&
        inviterUserId != 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'REQUEST 不应包含邀请人身份',
      );
    }
    final int seatNumber = _requiredStrictInt(data, 'seatNumber');
    if (seatNumber < 1 || seatNumber > 8) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 seatNumber 超出 1 至 8',
      );
    }
    final String statusValue = _requiredStrictString(data, 'status');
    final MicRequestStatus status = switch (statusValue) {
      'PENDING' => MicRequestStatus.pending,
      'APPROVED' => MicRequestStatus.approved,
      'REJECTED' => MicRequestStatus.rejected,
      'EXPIRED' => MicRequestStatus.expired,
      'CANCELLED' => MicRequestStatus.cancelled,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请包含未知 status',
      ),
    };
    final Object? providerInvocation = data['providerInvocation'];
    if (providerInvocation is! bool || providerInvocation) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 providerInvocation 必须严格为 false',
      );
    }
    final DateTime createdAt = _requiredStrictDateTime(data, 'createdAt');
    final DateTime expiresAt = _requiredStrictDateTime(data, 'expiresAt');
    if (!expiresAt.isAfter(createdAt)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 expiresAt 不晚于 createdAt',
      );
    }
    final DateTime? resolvedAt = _optionalStrictDateTime(data, 'resolvedAt');
    final int? resolvedByUserId = _optionalStrictInt(data, 'resolvedByUserId');
    if (resolvedByUserId != null && resolvedByUserId < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 resolvedByUserId 不能为负数',
      );
    }
    if (status == MicRequestStatus.pending &&
        (resolvedAt != null || (resolvedByUserId ?? 0) != 0)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'PENDING 上麦申请不应包含处理时间或处理人',
      );
    }
    if ((status == MicRequestStatus.approved ||
            status == MicRequestStatus.rejected ||
            status == MicRequestStatus.cancelled) &&
        (resolvedAt == null || (resolvedByUserId ?? 0) <= 0)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '已处理上麦申请缺少权威处理时间或处理人',
      );
    }
    final Map<String, Object?> memberData = _requiredObjectMap(data['member']);
    final int memberUserId = _requiredStrictInt(memberData, 'userId');
    if (memberUserId != subjectUserId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 member 身份与 subjectUserId 不一致',
      );
    }
    final String nickname = _requiredStrictString(memberData, 'nickName');
    final String name = _requiredStrictString(memberData, 'name');
    if (nickname != name) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 member 名称别名不一致',
      );
    }
    final String avatarUrl = _requiredStrictString(memberData, 'headImgUrl');
    final String roleValue = _requiredStrictString(memberData, 'role');
    if (!_knownMicMemberRoles.contains(roleValue)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 member role 无法识别',
      );
    }
    final String presenceValue = _requiredStrictString(memberData, 'presence');
    final RoomMemberPresence presence = switch (presenceValue) {
      'ON_MIC' => RoomMemberPresence.onMic,
      'LISTENER' => RoomMemberPresence.listener,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 member presence 无法识别',
      ),
    };
    final int memberSeatNumber = _requiredStrictInt(memberData, 'seatNumber');
    if (memberSeatNumber < 0 ||
        memberSeatNumber > 8 ||
        (presence == RoomMemberPresence.onMic && memberSeatNumber < 1) ||
        (presence == RoomMemberPresence.listener && memberSeatNumber != 0)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 member seatNumber 与 presence 不一致',
      );
    }
    final Object? mutedValue = memberData['muted'];
    if (mutedValue is! bool) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请 member muted 必须为布尔值',
      );
    }
    final MicRequestTargetAction action = status != MicRequestStatus.pending
        ? MicRequestTargetAction.none
        : type == MicRequestType.invite
        ? MicRequestTargetAction.accept
        : MicRequestTargetAction.cancel;
    return MicAccessRequest(
      id: id,
      roomId: roomId,
      member: RoomMember(
        userId: memberUserId,
        name: nickname,
        avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
        role: _roleFromServer(roleValue),
        presence: presence,
        seatNumber: memberSeatNumber == 0 ? null : memberSeatNumber,
        isMuted: mutedValue,
      ),
      seatNumber: seatNumber,
      status: status,
      createdAt: createdAt,
      type: type,
      requestedByUserId: requestedByUserId,
      subjectUserId: subjectUserId,
      expiresAt: expiresAt,
      resolvedAt: resolvedAt,
      resolvedByUserId: resolvedByUserId == null || resolvedByUserId == 0
          ? null
          : resolvedByUserId,
      targetAction: action,
    );
  }

  static const Set<String> _knownMicMemberRoles = <String>{
    'OWNER',
    'MANAGER',
    'MODERATOR',
    'PLATFORM_MODERATOR',
    'SPEAKER',
    'MEMBER',
    'LISTENER',
  };

  static String _requiredStrictString(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! String || value.trim() != value) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请字段 $field 必须为字符串',
      );
    }
    return value;
  }

  static int _requiredStrictInt(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! int) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请字段 $field 必须为整数',
      );
    }
    return value;
  }

  static int? _strictInt(Object? value) => value is int ? value : null;

  static int _requiredAliasInt(
    Map<String, Object?> data,
    Iterable<String> fields, {
    required String label,
    required bool allowZero,
  }) {
    int? resolved;
    for (final String field in fields) {
      if (!data.containsKey(field)) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '上麦申请缺少权威字段 $field',
        );
      }
      final int value = _requiredStrictInt(data, field);
      if (value < (allowZero ? 0 : 1) ||
          (resolved != null && resolved != value)) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '上麦申请 $label 身份别名不一致',
        );
      }
      resolved = value;
    }
    return resolved!;
  }

  static DateTime _requiredStrictDateTime(
    Map<String, Object?> data,
    String field,
  ) {
    final String text = _requiredStrictString(data, field);
    if (text.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请字段 $field 不能为空',
      );
    }
    final DateTime? value = DateTime.tryParse(text);
    if (value == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请字段 $field 无法解析',
      );
    }
    return value;
  }

  static DateTime? _optionalStrictDateTime(
    Map<String, Object?> data,
    String field,
  ) {
    if (!data.containsKey(field)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请缺少权威字段 $field',
      );
    }
    final Object? raw = data[field];
    if (raw == null) {
      return null;
    }
    if (raw is! String || raw.trim() != raw) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请字段 $field 必须为字符串',
      );
    }
    if (raw.isEmpty) {
      return null;
    }
    final DateTime? value = DateTime.tryParse(raw);
    if (value == null) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请字段 $field 无法解析',
      );
    }
    return value;
  }

  static int? _optionalStrictInt(Map<String, Object?> data, String field) {
    if (!data.containsKey(field)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请缺少权威字段 $field',
      );
    }
    final Object? raw = data[field];
    if (raw == null) {
      return null;
    }
    if (raw is! int) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '上麦申请字段 $field 必须为整数',
      );
    }
    return raw;
  }

  static void _assertStrictDecisionAliases(Map<String, Object?> data) {
    final bool hasAccepted = data.containsKey('accepted');
    final bool hasApproved = data.containsKey('approved');
    if (!hasAccepted && !hasApproved) {
      return;
    }
    bool? accepted;
    bool? approved;
    if (hasAccepted) {
      if (data['accepted'] is! bool) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '响应 accepted 必须为严格 JSON 布尔值',
        );
      }
      accepted = data['accepted'] as bool;
    }
    if (hasApproved) {
      if (data['approved'] is! bool) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '响应 approved 必须为严格 JSON 布尔值',
        );
      }
      approved = data['approved'] as bool;
    }
    if (accepted != null && approved != null && accepted != approved) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应 accepted 与 approved 决策不一致',
      );
    }
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
