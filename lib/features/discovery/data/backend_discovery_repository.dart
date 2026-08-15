import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';

class BackendDiscoveryRepository implements DiscoveryRepository {
  BackendDiscoveryRepository({
    required ApiClient apiClient,
    required String clientType,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  })  : _apiClient = apiClient,
        _routes = routes,
        _platformCode = clientType.toLowerCase().contains('ios') ? 2 : 1;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final int _platformCode;

  @override
  Future<List<DiscoveryRoom>> fetchHomeRooms({
    int page = 1,
    int pageSize = 20,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.homeRecommendedRooms,
      body: <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        'platform': _platformCode,
        'rtcSolutionType': 0,
      },
    );
    return _roomList(_pagedItems(response.data), favorite: false);
  }

  @override
  Future<DiscoverySearchResult> search({
    required String keyword,
    required SearchEntityType type,
    int page = 1,
    int pageSize = 20,
  }) async {
    final String normalized = keyword.trim();
    if (normalized.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请输入房间、用户或房间号',
      );
    }
    final ApiResponse response = await _apiClient.post(
      _routes.globalSearch,
      body: <String, Object?>{
        'keyword': normalized,
        'type': type.backendCode,
        'pageNo': page,
        'pageSize': pageSize,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<DiscoveryRoom> rooms = _roomList(
      _asList(data['roomsList']),
      favorite: false,
    );
    final List<DiscoveryUser> users = <DiscoveryUser>[
      for (final Object? value in _asList(data['usersList']))
        if (value is Map<String, Object?>) _userFromMap(value),
    ];
    final int total = _asInt(data['total']) ?? rooms.length + users.length;
    return DiscoverySearchResult(
      rooms: rooms,
      users: users,
      page: _asInt(data['pageNo']) ?? page,
      pageSize: _asInt(data['pageSize']) ?? pageSize,
      hasMore: page * pageSize < total,
    );
  }

  @override
  Future<RoomCollectionSnapshot> fetchRoomCollections({
    int page = 1,
    int pageSize = 30,
  }) async {
    final List<ApiResponse> responses = await Future.wait<ApiResponse>(
      <Future<ApiResponse>>[
        _apiClient.post(
          _routes.favoriteRooms,
          body: <String, Object?>{
            'pageNum': page,
            'pageSize': pageSize,
          },
        ),
        _apiClient.get(_routes.ownedRooms),
      ],
    );
    return RoomCollectionSnapshot(
      favorites: _roomList(_pagedItems(responses[0].data), favorite: true),
      ownedRooms: _roomList(_asList(responses[1].data), favorite: false),
    );
  }

  @override
  Future<bool> setFavorite({
    required String roomId,
    required bool favorite,
  }) async {
    await _apiClient.patch(
      _routes.starRoom,
      query: <String, String>{
        'roomId': roomId,
        'roomIdStr': roomId,
        'starType': favorite ? '1' : '0',
      },
    );
    return favorite;
  }

  static List<DiscoveryRoom> _roomList(
    List<Object?> values, {
    required bool favorite,
  }) {
    return <DiscoveryRoom>[
      for (final Object? value in values)
        if (value is Map<String, Object?>)
          _roomFromMap(value, favorite: favorite),
    ];
  }

  static DiscoveryRoom _roomFromMap(
    Map<String, Object?> map, {
    required bool favorite,
  }) {
    final String id = _nonEmptyString(map['roomIdStr']) ??
        _nonEmptyString(map['roomId']) ??
        _nonEmptyString(map['id']) ??
        '';
    if (id.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间列表返回了缺少房间 ID 的数据',
      );
    }
    return DiscoveryRoom(
      id: id,
      code: _nonEmptyString(map['roomCode']) ??
          _nonEmptyString(map['code']) ??
          id,
      title: _nonEmptyString(map['roomName']) ??
          _nonEmptyString(map['name']) ??
          '语音房',
      topic: _nonEmptyString(map['description']) ??
          _nonEmptyString(map['labelName']) ??
          '正在发生的实时语音聊天',
      onlineCount: _asInt(map['liveCount']) ??
          _asInt(map['userTotal']) ??
          _asInt(map['onlineNum']) ??
          0,
      occupiedSeats: _boundedSeatCount(_asList(map['micUserHeadImgs']).length),
      isSpeaking: (_asInt(map['heatValue']) ?? 0) > 0,
      isFavorite: favorite || _asBool(map['collectionFlag']),
      ownerUserId: _asInt(map['userId']),
      ownerName: _nonEmptyString(map['nickName']),
      coverUrl: _nonEmptyString(map['coverImage']) ??
          _nonEmptyString(map['coverImgUrl']),
      relationReason: _nonEmptyString(map['labelName']),
      isLocked: _asInt(map['isLockRoom']) == 1 ||
          _asInt(map['isLock']) == 1,
    );
  }

  static int _boundedSeatCount(int value) {
    if (value < 0) {
      return 0;
    }
    return value > 8 ? 8 : value;
  }

  static DiscoveryUser _userFromMap(Map<String, Object?> map) {
    final int userId = _asInt(map['userId']) ?? _asInt(map['id']) ?? 0;
    if (userId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '用户搜索返回了缺少用户 ID 的数据',
      );
    }
    final String stayRoom = _nonEmptyString(map['isStayRoom']) ?? '';
    return DiscoveryUser(
      userId: userId,
      name: _nonEmptyString(map['nickName']) ?? '用户 $userId',
      loginName: _nonEmptyString(map['loginName']) ?? '$userId',
      avatarUrl: _nonEmptyString(map['headImageUrl']),
      bio: _nonEmptyString(map['userType']),
      currentRoomId: stayRoom.isEmpty || stayRoom == '0' ? null : stayRoom,
    );
  }

  static List<Object?> _pagedItems(Object? value) {
    final Map<String, Object?> map = _asMap(value);
    for (final String key in <String>['records', 'list', 'rows', 'items']) {
      final Object? candidate = map[key];
      if (candidate is List<Object?>) {
        return candidate;
      }
    }
    return _asList(value);
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};

  static List<Object?> _asList(Object? value) =>
      value is List<Object?> ? value : <Object?>[];

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    return _asInt(value) == 1;
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
