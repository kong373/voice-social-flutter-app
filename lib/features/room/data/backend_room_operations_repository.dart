import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';

class BackendRoomOperationsRepository implements RoomOperationsRepository {
  BackendRoomOperationsRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  })  : _apiClient = apiClient,
        _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;

  @override
  MicCoordinationMode get micCoordinationMode => MicCoordinationMode.direct;

  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    required int page,
    int pageSize = 20,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.roomOnlineMembers,
      body: <String, Object?>{
        'roomId': _numericId(roomId),
        'pageNum': page,
        'pageSize': pageSize,
        'isSearchCount': true,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<RoomMember> members = <RoomMember>[
      for (final Object? item in _asList(data['list']))
        if (item is Map<String, Object?>) _memberFromOnline(item),
    ];
    return RoomMemberPage(
      items: members,
      page: _asInt(data['current']) ?? page,
      total: _asInt(data['total']) ?? members.length,
      pages: _asInt(data['pages']) ?? 1,
    );
  }

  @override
  Future<List<RoomMember>> fetchOffMicListeners(String roomId) async {
    final ApiResponse response = await _apiClient.post(
      _routes.roomOffMicMembers,
      body: <String, Object?>{'roomId': _numericId(roomId)},
    );
    final Map<String, Object?> data = _asMap(response.data);
    return <RoomMember>[
      for (final Object? item in _asList(data['users']))
        if (item is Map<String, Object?>)
          RoomMember(
            userId: _asInt(item['userId']) ?? 0,
            name: _string(item['nickName'], fallback: '房间成员'),
            avatarUrl: _optionalString(item['headImgUrl']),
            role: RoomRole.listener,
            presence: RoomMemberPresence.listener,
          ),
    ].where((RoomMember member) => member.userId > 0).toList(growable: false);
  }

  @override
  Future<List<RoomMember>> fetchManagers(String roomId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.roomManagers,
      query: <String, String>{'roomId': roomId},
    );
    return <RoomMember>[
      for (final Object? item in _asList(response.data))
        if (item is Map<String, Object?>)
          RoomMember(
            userId: _asInt(item['id']) ?? 0,
            name: _string(item['nickName'], fallback: '房间管理员'),
            role: _roleFromServer(_asInt(item['userRoomRole']) ?? 1),
            presence: RoomMemberPresence.listener,
          ),
    ].where((RoomMember member) => member.userId > 0).toList(growable: false);
  }

  @override
  Future<List<RoomMember>> fetchMutedUsers(String roomId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.roomMutedUsers,
      query: <String, String>{'roomId': roomId},
    );
    return <RoomMember>[
      for (final Object? item in _asList(response.data))
        if (item is Map<String, Object?>)
          RoomMember(
            userId: _asInt(item['id']) ?? 0,
            name: _string(item['niceName'], fallback: '已禁言成员'),
            avatarUrl: _optionalString(item['headImgUrl']),
            role: RoomRole.listener,
            presence: RoomMemberPresence.listener,
            isMuted: true,
          ),
    ].where((RoomMember member) => member.userId > 0).toList(growable: false);
  }

  @override
  Future<RoomTopic> fetchTopic(String roomId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.roomTopic,
      query: <String, String>{'roomId': roomId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    return RoomTopic(
      title: _string(data['topicTitle'], fallback: ''),
      content: _string(data['topicContent'], fallback: ''),
    );
  }

  @override
  Future<void> updateTopic({
    required String roomId,
    required RoomTopic topic,
  }) async {
    await _apiClient.patch(
      _routes.updateRoomTopic,
      body: <String, Object?>{
        'roomId': _numericId(roomId),
        'topicTitle': topic.title,
        'topicContent': topic.content,
      },
    );
  }

  @override
  Future<void> setUserMuted({
    required String roomId,
    required int userId,
    required bool muted,
  }) async {
    await _apiClient.patch(
      _routes.setRoomUserMuted,
      body: <String, Object?>{
        'roomId': _numericId(roomId),
        'userId': userId,
        'isMuted': muted ? 1 : 0,
      },
    );
  }

  @override
  Future<void> setUserRole({
    required String roomId,
    required int userId,
    required bool manager,
  }) async {
    await _apiClient.patch(
      _routes.setRoomUserRole,
      body: <String, Object?>{
        'roomId': _numericId(roomId),
        'userId': userId,
        'userRoomRole': manager ? 1 : 0,
      },
    );
  }

  @override
  Future<void> kickUser({
    required String roomId,
    required int userId,
  }) async {
    await _apiClient.post(
      _routes.kickRoomUser,
      query: <String, String>{'roomId': roomId, 'beUserId': '$userId'},
    );
  }

  @override
  Future<void> takeUserOffMic({
    required int backendMicIndex,
    required int userId,
  }) async {
    await _apiClient.put(
      _routes.takeUserOffMic,
      query: <String, String>{
        'micIndex': '$backendMicIndex',
        'beUserId': '$userId',
      },
    );
  }

  @override
  Future<void> setSeatLocked({
    required int backendMicIndex,
    required bool locked,
  }) async {
    await _apiClient.put(
      locked ? _routes.lockMic : _routes.unlockMic,
      query: <String, String>{'micIndex': '$backendMicIndex'},
    );
  }

  @override
  Future<void> setSeatMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {
    await _apiClient.put(
      muted ? _routes.closeMic : _routes.openMic,
      query: <String, String>{'micIndex': '$backendMicIndex'},
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

  static RoomMember _memberFromOnline(Map<String, Object?> item) {
    return RoomMember(
      userId: _asInt(item['userId']) ?? 0,
      name: _string(item['nickName'], fallback: '房间成员'),
      avatarUrl: _optionalString(item['headImgUrl']),
      role: _roleFromServer(_asInt(item['userRoomRole']) ?? 0),
      presence: RoomMemberPresence.listener,
      wealthLevel: _asInt(item['wealthLevel']) ?? 0,
      charmLevel: _asInt(item['charmLevel']) ?? 0,
    );
  }

  static RoomRole _roleFromServer(int role) {
    return switch (role) {
      1 || 5 => RoomRole.moderator,
      2 => RoomRole.platformModerator,
      _ => RoomRole.listener,
    };
  }

  static Object _numericId(String value) => int.tryParse(value) ?? value;

  static List<Object?> _asList(Object? value) =>
      value is List<Object?> ? value : const <Object?>[];

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String _string(Object? value, {required String fallback}) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _optionalString(Object? value) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
