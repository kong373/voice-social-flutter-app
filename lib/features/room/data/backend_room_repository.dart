import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/domain/fixed_eight_seat_adapter.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';

class BackendRoomRepository implements RoomRepository {
  BackendRoomRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
    FixedEightSeatAdapter seatAdapter = const FixedEightSeatAdapter(),
  })  : _apiClient = apiClient,
        _routes = routes,
        _seatAdapter = seatAdapter;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final FixedEightSeatAdapter _seatAdapter;

  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) async {
    final ApiResponse enterResponse = await _apiClient.post(
      _routes.enterRoom,
      body: <String, Object?>{
        'roomId': int.tryParse(roomId) ?? roomId,
        'password': password ?? '',
        'vistWay': source.backendCode,
      },
    );
    final Map<String, Object?> enter = _asMap(enterResponse.data);
    final ApiResponse infoResponse = await _apiClient.get(
      _routes.queryRoomInfo,
      query: <String, String>{'roomId': roomId},
    );
    return _buildSnapshot(
      enter: enter,
      info: _asMap(infoResponse.data),
      currentUserId: currentUserId,
    );
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) async {
    final ApiResponse response = await _apiClient.get(
      _routes.reconnectRoom,
      query: <String, String>{'roomId': roomId},
    );
    final ApiResponse infoResponse = await _apiClient.get(
      _routes.queryRoomInfo,
      query: <String, String>{'roomId': roomId},
    );
    final ApiResponse otherInfoResponse = await _apiClient.get(
      _routes.queryRoomOtherInfo,
      query: <String, String>{'roomId': roomId},
    );
    final Map<String, Object?> otherInfo = _asMap(otherInfoResponse.data);
    final int rtcSolutionType = _asInt(otherInfo['rtcSolutionType']) ?? 0;
    Object? refreshedToken = _asMap(response.data)['agoraToken'];
    if (rtcSolutionType == 0) {
      final ApiResponse tokenResponse = await _apiClient.get(
        _routes.buildRtcToken,
        query: <String, String>{'roomId': roomId},
      );
      refreshedToken = _asMap(tokenResponse.data)['string'];
    }
    final Map<String, Object?> reconnect = Map<String, Object?>.of(
      _asMap(response.data),
    )
      ..['rtcSolutionType'] = rtcSolutionType
      ..['agoraToken'] = refreshedToken;
    return _buildSnapshot(
      enter: reconnect,
      info: _asMap(infoResponse.data),
      currentUserId: currentUserId,
      fallbackRoomId: roomId,
    );
  }

  @override
  Future<void> exitRoom(String roomId) async {
    await _apiClient.get(
      _routes.exitRoom,
      query: <String, String>{'roomId': roomId},
    );
  }

  @override
  Future<void> requestMic(int backendMicIndex) async {
    await _apiClient.put(
      _routes.userUpMic,
      query: <String, String>{'micIndex': '$backendMicIndex'},
    );
  }

  @override
  Future<void> leaveMic() async {
    await _apiClient.put(_routes.userLeaveMic);
  }

  @override
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async {
    await _apiClient.put(
      muted ? _routes.closeMic : _routes.openMic,
      query: <String, String>{'micIndex': '$backendMicIndex'},
    );
  }

  @override
  Future<void> sendPublicMessage({
    required String roomId,
    required String content,
  }) async {
    await _apiClient.post(
      _routes.sendPublicMessage,
      body: <String, Object?>{
        'roomId': int.tryParse(roomId) ?? roomId,
        'message': content,
        'messageType': 0,
        'quoteUserIds': '',
      },
    );
  }

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required int giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.sendGift,
      body: <String, Object?>{
        'roomId': int.tryParse(roomId) ?? roomId,
        'giftId': giftId,
        'receiveUserIds': receiverUserIds,
        'giftNum': quantity,
        'giftFrom': giftFrom,
        'content': '',
        'clientParam': '',
        'sendType': 0,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    return GiftReceipt(
      success: _asBool(data['sendFlag']),
      remainingBalance: _asInt(data['ownNCoin']),
    );
  }

  RoomSnapshot _buildSnapshot({
    required Map<String, Object?> enter,
    required Map<String, Object?> info,
    required int currentUserId,
    String? fallbackRoomId,
  }) {
    final Map<String, Object?> mic = _asMap(info['mic']);
    final List<BackendMicSeat> backendSeats = _parseBackendSeats(
      mic['micSeatList'],
    );
    final List<MicSeat> seats = _seatAdapter.adapt(backendSeats);
    final int serverRole = _asInt(info['roomRole']) ?? 0;
    RoomRole role = _roomRoleFromServer(serverRole);
    if (role == RoomRole.listener &&
        seats.any((MicSeat seat) => seat.userId == currentUserId)) {
      role = RoomRole.speaker;
    }

    final String roomId = _nonEmptyString(enter['roomIdStr']) ??
        _nonEmptyString(enter['roomId']) ??
        fallbackRoomId ??
        '';
    if (roomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '进房响应缺少房间 ID',
      );
    }
    final String roomCode = _nonEmptyString(enter['roomCode']) ?? roomId;
    final String token = _nonEmptyString(enter['agoraToken']) ?? '';
    final int solutionCode = _asInt(enter['rtcSolutionType']) ?? 0;
    if (token.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '进房响应缺少 RTC Token',
      );
    }
    return RoomSnapshot(
      roomId: roomId,
      roomCode: roomCode,
      title: _nonEmptyString(enter['roomName']) ?? '语音房',
      topic: _nonEmptyString(enter['topicContent']) ??
          _nonEmptyString(enter['topicTitle']) ??
          '',
      ownerId: _asInt(info['roomOwnerId']) ?? 0,
      role: role,
      seats: seats,
      rtc: RtcCredentials(
        solution: solutionCode == 0
            ? RtcSolution.agora
            : solutionCode == 1
                ? RtcSolution.zego
                : RtcSolution.unknown,
        token: token,
        channelId: roomId,
        userId: currentUserId,
      ),
      publicScreenEnabled: _asInt(info['isCloseScreen']) != 1,
      pictureMessagesAllowed: _asInt(info['isAllowSendPicture']) == 1,
      autoLockMic: _asInt(info['isAutoLockMic']) == 1,
      giftCatalogAvailable: false,
      giftBalance: null,
      onlineCount: _asInt(enter['onlineNum']) ??
          _asInt(info['onlineNum']) ??
          _asInt(info['onlineCount']),
      coverUrl: _nonEmptyString(enter['coverImgUrl']),
      backgroundUrl: _nonEmptyString(enter['roomBackageImg']),
    );
  }

  static List<BackendMicSeat> _parseBackendSeats(Object? value) {
    if (value is! List<Object?>) {
      return <BackendMicSeat>[
        for (int index = 1; index <= 8; index += 1)
          BackendMicSeat(index: index, status: 0),
      ];
    }
    return <BackendMicSeat>[
      for (final Object? item in value)
        if (item is Map<String, Object?>)
          BackendMicSeat(
            index: _asInt(item['index']) ?? -1,
            status: _asInt(item['status']) ?? 0,
            userId: _asInt(_asMap(item['userInfo'])['userId']),
            userName: _nonEmptyString(
              _asMap(item['userInfo'])['nickname'],
            ),
            avatarUrl: _nonEmptyString(
              _asMap(item['userInfo'])['headImageUrl'],
            ),
            userRoleCode: _asInt(
              _asMap(item['userInfo'])['userNewRole'],
            ),
          ),
    ];
  }

  static RoomRole _roomRoleFromServer(int role) {
    switch (role) {
      case 3:
        return RoomRole.owner;
      case 5:
        return RoomRole.moderator;
      case 4:
        return RoomRole.platformModerator;
      default:
        return RoomRole.listener;
    }
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    final int? parsed = _asInt(value);
    return parsed == 1;
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _nonEmptyString(Object? value) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
