import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/domain/fixed_eight_seat_adapter.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';

/// M3.2A live repository.
///
/// It exposes the authoritative HTTP room snapshot while every RTC, IM and
/// economic write remains fail-closed until a vendor adapter is configured.
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
  }) {
    return _fetchSnapshot(roomId: roomId, currentUserId: currentUserId);
  }

  @override
  Future<RoomSnapshot> reconnectRoom({
    required String roomId,
    required int currentUserId,
  }) {
    return _fetchSnapshot(roomId: roomId, currentUserId: currentUserId);
  }

  Future<RoomSnapshot> _fetchSnapshot({
    required String roomId,
    required int currentUserId,
  }) async {
    final ApiResponse response = await _apiClient.get(
      _routes.roomById,
      query: <String, String>{'roomId': roomId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final String resolvedRoomId = _nonEmptyString(data['roomIdStr']) ??
        _nonEmptyString(data['roomId']) ??
        _nonEmptyString(data['id']) ??
        '';
    if (resolvedRoomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间快照缺少房间 ID',
      );
    }
    final int ownerId = _asInt(data['ownerId']) ??
        _asInt(data['userId']) ??
        0;
    final List<BackendMicSeat> backendSeats = <BackendMicSeat>[
      for (final Object? raw in _asList(data['seats']))
        if (raw is Map<String, Object?>)
          BackendMicSeat(
            index: _asInt(raw['index']) ?? -1,
            // M3.2A snapshot uses 1 for occupied; the fixed-seat adapter uses
            // legacy status 3 for occupied.
            status: _asInt(raw['status']) == 1 ? 3 : 0,
            userId: _asInt(raw['userId']),
            userName: _nonEmptyString(raw['userName']),
            avatarUrl: _nonEmptyString(raw['avatarUrl']),
            userRoleCode: _asInt(raw['userId']) == ownerId ? 3 : null,
          ),
    ];
    return RoomSnapshot(
      roomId: resolvedRoomId,
      roomCode: _nonEmptyString(data['roomCode']) ?? resolvedRoomId,
      title: _nonEmptyString(data['roomName']) ??
          _nonEmptyString(data['name']) ??
          '语音房',
      topic: _nonEmptyString(data['topicContent']) ??
          _nonEmptyString(data['description']) ??
          '',
      ownerId: ownerId,
      role: ownerId == currentUserId ? RoomRole.owner : RoomRole.listener,
      seats: _seatAdapter.adapt(backendSeats),
      rtc: RtcCredentials(
        solution: RtcSolution.unknown,
        token: '',
        channelId: resolvedRoomId,
        userId: currentUserId,
      ),
      transportMode: RoomTransportMode.snapshotOnly,
      publicScreenEnabled: false,
      pictureMessagesAllowed: false,
      autoLockMic: false,
      giftCatalogAvailable: false,
      giftBalance: null,
      onlineCount: _asInt(data['onlineNum']) ?? _asInt(data['liveCount']),
      coverUrl: _nonEmptyString(data['coverImgUrl']) ??
          _nonEmptyString(data['coverImage']),
    );
  }

  @override
  Future<void> exitRoom(String roomId) async {
    // Snapshot-only viewing has no server-side membership to tear down.
  }

  @override
  Future<void> requestMic(int backendMicIndex) async => _vendorBlocked();

  @override
  Future<void> leaveMic() async => _vendorBlocked();

  @override
  Future<void> setSelfMicrophoneMuted({
    required int backendMicIndex,
    required bool muted,
  }) async => _vendorBlocked();

  @override
  Future<void> sendPublicMessage({
    required String roomId,
    required String content,
  }) async => _vendorBlocked();

  @override
  Future<GiftReceipt> sendGift({
    required String roomId,
    required int giftId,
    required List<int> receiverUserIds,
    required int quantity,
    required int giftFrom,
  }) async => _vendorBlocked();

  Never _vendorBlocked() => throw const ApiException(
        kind: ApiFailureKind.configuration,
        code: 503,
        message: 'VENDOR_BLOCKED：RTC、IM 与房间写入适配器尚未配置',
      );

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};

  static List<Object?> _asList(Object? value) =>
      value is List<Object?> ? value : <Object?>[];

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
