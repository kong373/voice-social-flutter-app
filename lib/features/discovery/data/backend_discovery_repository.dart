import 'dart:convert';

import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_request_id.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';

class BackendDiscoveryRepository implements DiscoveryRepository {
  BackendDiscoveryRepository({
    required ApiClient apiClient,
    required String clientType,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  }) : _apiClient = apiClient,
       _routes = routes,
       _platformCode = clientType.toLowerCase().contains('ios') ? 2 : 1;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final int _platformCode;
  final Map<String, Future<bool>> _pendingFavoriteWrites =
      <String, Future<bool>>{};
  final Map<String, String> _favoriteRequestIds = <String, String>{};
  final Map<String, Future<void>> _favoriteMutationTails =
      <String, Future<void>>{};

  @override
  Future<List<DiscoveryRoom>> fetchHomeRooms({
    int page = 1,
    int pageSize = 20,
  }) async {
    _validatePageRequest(page: page, pageSize: pageSize);
    final ApiResponse response = await _apiClient.post(
      _routes.homeRecommendedRooms,
      body: <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        'platform': _platformCode,
        'rtcSolutionType': 0,
      },
    );
    final Map<String, Object?> data = _requiredMap(
      response.data,
      context: '首页房间分页响应',
    );
    final List<Object?> records = _requiredList(
      data,
      'records',
      context: '首页房间分页响应',
    );
    _validateReadPageEnvelope(
      data,
      requestedPage: page,
      requestedPageSize: pageSize,
      itemCount: records.length,
      context: '首页房间分页',
      pageField: 'current',
    );
    return _roomList(records, favorite: false);
  }

  @override
  Future<DiscoverySearchResult> search({
    required String keyword,
    required SearchEntityType type,
    int page = 1,
    int pageSize = 20,
  }) async {
    _validatePageRequest(page: page, pageSize: pageSize);
    final String normalized = keyword.trim();
    if (normalized.isEmpty || normalized.length > 64) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请输入 1 至 64 个字符的房间、用户或房间号',
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
    final Map<String, Object?> data = _requiredMap(
      response.data,
      context: '搜索响应',
    );
    final List<DiscoveryRoom> rooms = _roomList(
      _requiredList(data, 'roomsList', context: '搜索响应'),
      favorite: false,
    );
    final List<DiscoveryUser> users = _userList(
      _requiredList(data, 'usersList', context: '搜索响应'),
    );
    final int responsePage = _requiredPageInt(
      data,
      field: 'pageNo',
      allowZero: false,
    );
    final int responsePageSize = _requiredPageInt(
      data,
      field: 'pageSize',
      allowZero: false,
    );
    final int total = _requiredPageInt(data, field: 'total', allowZero: true);
    if (responsePage != page || responsePageSize != pageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '搜索分页 pageNo 或 pageSize 与请求不一致',
      );
    }
    return DiscoverySearchResult(
      rooms: rooms,
      users: users,
      page: responsePage,
      pageSize: responsePageSize,
      hasMore: responsePage * responsePageSize < total,
    );
  }

  @override
  Future<RoomCollectionSnapshot> fetchRoomCollections({
    int page = 1,
    int pageSize = 30,
  }) async {
    _validatePageRequest(page: page, pageSize: pageSize);
    final List<List<DiscoveryRoom>> collections =
        await Future.wait<List<DiscoveryRoom>>(<Future<List<DiscoveryRoom>>>[
          _fetchRoomCollectionPages(
            page: page,
            pageSize: pageSize,
            favorite: true,
          ),
          _fetchRoomCollectionPages(
            page: page,
            pageSize: pageSize,
            favorite: false,
          ),
        ]);
    return RoomCollectionSnapshot(
      favorites: collections[0],
      ownedRooms: collections[1],
    );
  }

  Future<List<DiscoveryRoom>> _fetchRoomCollectionPages({
    required int page,
    required int pageSize,
    required bool favorite,
  }) async {
    const int maxPages = 100;
    final List<DiscoveryRoom> rooms = <DiscoveryRoom>[];
    final Set<String> seenRoomIds = <String>{};
    int requestedPage = page;
    int? stableTotal;
    int? stablePages;
    while (true) {
      final ApiResponse response = favorite
          ? await _apiClient.post(
              _routes.favoriteRooms,
              body: <String, Object?>{
                'pageNum': requestedPage,
                'pageSize': pageSize,
              },
            )
          : await _apiClient.get(
              _routes.ownedRooms,
              query: <String, String>{
                'pageNum': '$requestedPage',
                'pageSize': '$pageSize',
              },
            );
      final String context = favorite ? '收藏房间分页' : '我的房间分页';
      final _CollectionPage parsed = _parseCollectionPage(
        response.data,
        requestedPage: requestedPage,
        requestedPageSize: pageSize,
        context: context,
      );
      stableTotal ??= parsed.total;
      stablePages ??= parsed.pages;
      if (stableTotal != parsed.total || stablePages != parsed.pages) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$context遍历期间 total 或 pages 发生漂移',
        );
      }
      final List<DiscoveryRoom> currentRooms = _roomList(
        parsed.items,
        favorite: favorite,
      );
      for (final DiscoveryRoom room in currentRooms) {
        if (!seenRoomIds.add(room.id)) {
          throw ApiException(
            kind: ApiFailureKind.protocol,
            message: '$context包含重复房间 ID',
          );
        }
        rooms.add(room);
      }
      if (requestedPage >= parsed.pages || parsed.pages == 0) {
        return rooms;
      }
      if (requestedPage - page + 1 >= maxPages) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$context超过安全分页上限',
        );
      }
      requestedPage++;
    }
  }

  @override
  Future<bool> setFavorite({
    required String roomId,
    required bool favorite,
  }) async {
    final String normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '收藏房间 ID 不能为空',
      );
    }
    final String intent = '$normalizedRoomId:$favorite';
    final Future<bool>? pending = _pendingFavoriteWrites[intent];
    if (pending != null) {
      return pending;
    }
    final Future<bool> request =
        _serializeFavoriteMutation(normalizedRoomId, () async {
          final String requestId = _favoriteRequestIds[intent] ??=
              newDiscoveryRequestId('discovery-favorite');
          try {
            final bool result = await _setFavoriteOnce(
              roomId: normalizedRoomId,
              favorite: favorite,
              requestId: requestId,
            );
            _favoriteRequestIds.remove(intent);
            return result;
          } catch (error) {
            if (!shouldRetainDiscoveryWriteRequest(error)) {
              _favoriteRequestIds.remove(intent);
            }
            rethrow;
          }
        }).whenComplete(() {
          _pendingFavoriteWrites.remove(intent);
        });
    _pendingFavoriteWrites[intent] = request;
    return request;
  }

  Future<bool> _setFavoriteOnce({
    required String roomId,
    required bool favorite,
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.starRoom,
      headers: <String, String>{
        'X-Request-Id': normalizeDiscoveryRequestId(requestId),
      },
      body: <String, Object?>{
        'roomId': roomId,
        'favorite': favorite,
        'type': favorite ? 1 : 0,
      },
    );
    final Map<String, Object?> data = _requiredMap(
      response.data,
      context: '收藏写入响应',
    );
    final String responseRoomId = _nonEmptyString(data['roomId']) ?? '';
    final Object? rawFavorite = data['favorite'];
    final int? collectionFlag = _asInt(data['collectionFlag']);
    if (responseRoomId != roomId ||
        rawFavorite is! bool ||
        (collectionFlag != 0 && collectionFlag != 1) ||
        rawFavorite != (collectionFlag == 1) ||
        rawFavorite != favorite) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '收藏写入响应的房间或状态与请求不一致',
      );
    }
    return rawFavorite;
  }

  Future<T> _serializeFavoriteMutation<T>(
    String roomId,
    Future<T> Function() operation,
  ) {
    final Future<void> previous =
        _favoriteMutationTails[roomId] ?? Future<void>.value();
    final Future<void> ready = previous.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    final Future<T> result = ready.then<T>((_) => operation());
    late final Future<void> tail;
    tail = result
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
          if (identical(_favoriteMutationTails[roomId], tail)) {
            _favoriteMutationTails.remove(roomId);
          }
        });
    _favoriteMutationTails[roomId] = tail;
    return result;
  }

  static List<DiscoveryRoom> _roomList(
    List<Object?> values, {
    required bool favorite,
  }) {
    final List<DiscoveryRoom> rooms = <DiscoveryRoom>[];
    for (final Object? value in values) {
      if (value is! Map<String, Object?>) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '房间列表包含非对象数据',
        );
      }
      rooms.add(_roomFromMap(value, favorite: favorite));
    }
    return rooms;
  }

  static DiscoveryRoom _roomFromMap(
    Map<String, Object?> map, {
    required bool favorite,
  }) {
    final String id = _consistentStringIdentity(map, const <String>[
      'roomIdStr',
      'roomId',
      'id',
    ], context: '房间列表');
    return DiscoveryRoom(
      id: id,
      code:
          _nonEmptyString(map['roomCode']) ??
          _nonEmptyString(map['code']) ??
          id,
      title:
          _nonEmptyString(map['roomName']) ??
          _nonEmptyString(map['name']) ??
          '语音房',
      topic:
          _nonEmptyString(map['topic']) ??
          _nonEmptyString(map['description']) ??
          _nonEmptyString(map['labelName']) ??
          '正在发生的实时语音聊天',
      onlineCount: _authoritativeOnlineCount(map),
      occupiedSeats: _boundedSeatCount(_asList(map['micUserHeadImgs']).length),
      isSpeaking: (_asInt(map['heatValue']) ?? 0) > 0,
      isFavorite:
          favorite ||
          _asBool(map['favorite']) ||
          _asBool(map['collectionFlag']),
      ownerUserId: _asInt(map['userId']),
      ownerName: _nonEmptyString(map['nickName']),
      coverUrl:
          _nonEmptyString(map['coverImage']) ??
          _nonEmptyString(map['coverImgUrl']),
      relationReason: _nonEmptyString(map['labelName']),
      isLocked: _asInt(map['isLockRoom']) == 1 || _asInt(map['isLock']) == 1,
    );
  }

  static int _boundedSeatCount(int value) {
    if (value < 0) {
      return 0;
    }
    return value > 8 ? 8 : value;
  }

  static int? _authoritativeOnlineCount(Map<String, Object?> map) {
    for (final String key in <String>[
      'onlineCount',
      'liveCount',
      'userTotal',
      'onlineNum',
    ]) {
      if (!map.containsKey(key)) {
        continue;
      }
      final int? value = _asInt(map[key]);
      // Once a server field is present, do not silently substitute a stale
      // alias when that authoritative field is malformed or contradictory.
      return value == null || value < 0 ? null : value;
    }
    return null;
  }

  static DiscoveryUser _userFromMap(Map<String, Object?> map) {
    final int userId = _consistentPositiveIntIdentity(map, const <String>[
      'userId',
      'id',
    ], context: '用户搜索');
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

  static List<DiscoveryUser> _userList(List<Object?> values) {
    final List<DiscoveryUser> users = <DiscoveryUser>[];
    for (final Object? value in values) {
      if (value is! Map<String, Object?>) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '用户列表包含非对象数据',
        );
      }
      users.add(_userFromMap(value));
    }
    return users;
  }

  static String _consistentStringIdentity(
    Map<String, Object?> map,
    List<String> fields, {
    required String context,
  }) {
    final Set<String> values = <String>{};
    for (final String field in fields) {
      final String? value = _nonEmptyString(map[field]);
      if (value != null) {
        values.add(value);
      }
    }
    if (values.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context返回了缺少 ID 的数据',
      );
    }
    if (values.length != 1) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context返回了互相冲突的 ID 字段',
      );
    }
    return values.single;
  }

  static int _consistentPositiveIntIdentity(
    Map<String, Object?> map,
    List<String> fields, {
    required String context,
  }) {
    final Set<int> values = <int>{};
    for (final String field in fields) {
      final int? value = _asInt(map[field]);
      if (value != null && value > 0) {
        values.add(value);
      }
    }
    if (values.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context返回了缺少 ID 的数据',
      );
    }
    if (values.length != 1) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context返回了互相冲突的 ID 字段',
      );
    }
    return values.single;
  }

  static _CollectionPage _parseCollectionPage(
    Object? value, {
    required int requestedPage,
    required int requestedPageSize,
    required String context,
  }) {
    final Map<String, Object?> data = _requiredMap(value, context: context);
    final List<Object?> records = _requiredList(
      data,
      'records',
      context: context,
    );
    final List<Object?> list = _requiredList(data, 'list', context: context);
    if (jsonEncode(records) != jsonEncode(list)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context records 与 list 不一致',
      );
    }
    final int current = _requiredPageInt(
      data,
      field: 'current',
      allowZero: false,
    );
    final int size = _requiredPageInt(data, field: 'size', allowZero: false);
    final int responsePageSize = _requiredPageInt(
      data,
      field: 'pageSize',
      allowZero: false,
    );
    final int total = _requiredPageInt(data, field: 'total', allowZero: true);
    final int pages = _requiredPageInt(data, field: 'pages', allowZero: true);
    final int expectedPages = total == 0
        ? 0
        : (total + requestedPageSize - 1) ~/ requestedPageSize;
    if (current != requestedPage ||
        size != requestedPageSize ||
        responsePageSize != requestedPageSize ||
        pages != expectedPages) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context分页元数据与请求或 total 不一致',
      );
    }
    final int expectedItems = requestedPage > pages
        ? 0
        : (total - ((requestedPage - 1) * requestedPageSize))
              .clamp(0, requestedPageSize)
              .toInt();
    if (records.length != expectedItems) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context当前页条目数与 total/pages 不一致',
      );
    }
    return _CollectionPage(items: records, total: total, pages: pages);
  }

  static Map<String, Object?> _requiredMap(
    Object? value, {
    required String context,
  }) {
    if (value is Map<String, Object?>) {
      return value;
    }
    throw ApiException(kind: ApiFailureKind.protocol, message: '$context不是对象');
  }

  static List<Object?> _requiredList(
    Map<String, Object?> data,
    String field, {
    required String context,
  }) {
    if (!data.containsKey(field)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context缺少 $field',
      );
    }
    final Object? value = data[field];
    if (value is List<Object?>) {
      return value;
    }
    throw ApiException(
      kind: ApiFailureKind.protocol,
      message: '$context $field 不是列表',
    );
  }

  static void _validatePageRequest({required int page, required int pageSize}) {
    if (page < 1 || pageSize < 1 || pageSize > 50) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '分页 page 必须为正数，pageSize 必须为 1 至 50',
      );
    }
  }

  static void _validateReadPageEnvelope(
    Map<String, Object?> data, {
    required int requestedPage,
    required int requestedPageSize,
    required int itemCount,
    required String context,
    required String pageField,
  }) {
    final int current = _requiredPageInt(
      data,
      field: pageField,
      allowZero: false,
    );
    final int pageSize = _requiredPageInt(
      data,
      field: 'pageSize',
      allowZero: false,
    );
    final int total = _requiredPageInt(data, field: 'total', allowZero: true);
    if (current != requestedPage || pageSize != requestedPageSize) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context页码或 pageSize 与请求不一致',
      );
    }
    final int remaining = total - ((current - 1) * pageSize);
    final int expectedCount = remaining.clamp(0, pageSize).toInt();
    if (itemCount != expectedCount) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$context记录数与 total/pageSize 不一致',
      );
    }
  }

  static int _requiredPageInt(
    Map<String, Object?> data, {
    required String field,
    required bool allowZero,
  }) {
    final int? value = _asInt(data[field]);
    if (value == null || value < (allowZero ? 0 : 1)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '搜索响应缺少有效的 $field 分页数字',
      );
    }
    return value;
  }

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

class _CollectionPage {
  const _CollectionPage({
    required this.items,
    required this.total,
    required this.pages,
  });

  final List<Object?> items;
  final int total;
  final int pages;
}
