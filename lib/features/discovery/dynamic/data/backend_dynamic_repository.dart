import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_repository.dart';

class BackendDynamicRepository implements DynamicRepository {
  BackendDynamicRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
    required int Function() currentUserIdProvider,
  })  : _apiClient = apiClient,
        _routes = routes,
        _currentUserIdProvider = currentUserIdProvider;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final int Function() _currentUserIdProvider;
  final Map<String, DynamicPost> _postCache = <String, DynamicPost>{};

  @override
  bool get supportsImagePublishing => false;

  @override
  Future<PagedResult<DynamicPost>> fetchFeed({
    DynamicCategory category = DynamicCategory.all,
    int page = 1,
    int pageSize = 20,
  }) async {
    final ApiResponse response = await _apiClient.get(
      _routes.dynamicList,
      query: <String, String>{
        'pageNum': '$page',
        'pageSize': '$pageSize',
        if (category.backendTag != null) 'tags': category.backendTag!,
      },
    );
    final Map<String, Object?> pageData = _pageData(response.data);
    final List<DynamicPost> items = _items(pageData)
        .map(_postFromMap)
        .where((DynamicPost post) => post.id.isNotEmpty)
        .toList(growable: false);
    for (final DynamicPost post in items) {
      _postCache[post.id] = post;
    }
    return PagedResult<DynamicPost>(
      items: items,
      page: page,
      hasMore: _hasMore(pageData, page: page, pageSize: pageSize, count: items.length),
    );
  }

  @override
  Future<DynamicPost> fetchPost(String dynamicId) async {
    final DynamicPost? cached = _postCache[dynamicId];
    if (cached != null) {
      return cached;
    }
    for (int page = 1; page <= 3; page += 1) {
      final PagedResult<DynamicPost> result = await fetchFeed(page: page, pageSize: 30);
      for (final DynamicPost post in result.items) {
        if (post.id == dynamicId) {
          return post;
        }
      }
      if (!result.hasMore) {
        break;
      }
    }
    throw const ApiException(
      kind: ApiFailureKind.validation,
      message: '动态已删除或不可用',
    );
  }

  @override
  Future<PagedResult<DynamicComment>> fetchComments({
    required String dynamicId,
    int page = 1,
    int pageSize = 30,
  }) async {
    final ApiResponse response = await _apiClient.get(
      _routes.dynamicComments,
      query: <String, String>{
        'dynamicId': dynamicId,
        'pageNum': '$page',
        'pageSize': '$pageSize',
      },
    );
    final Map<String, Object?> pageData = _pageData(response.data);
    final List<DynamicComment> items = _items(pageData)
        .map((Map<String, Object?> item) => _commentFromMap(dynamicId, item))
        .where((DynamicComment item) => item.id.isNotEmpty)
        .toList(growable: false);
    return PagedResult<DynamicComment>(
      items: items,
      page: page,
      hasMore: _hasMore(pageData, page: page, pageSize: pageSize, count: items.length),
    );
  }

  @override
  Future<DynamicPost> toggleLike(String dynamicId) async {
    await _apiClient.post(
      _routes.dynamicLike,
      query: <String, String>{'dynamicId': dynamicId},
    );
    final DynamicPost current = await fetchPost(dynamicId);
    final bool liked = !current.isLiked;
    final DynamicPost optimistic = current.copyWith(
      isLiked: liked,
      likeCount: (current.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 31).toInt(),
    );
    _postCache[dynamicId] = optimistic;
    return optimistic;
  }

  @override
  Future<DynamicComment> addComment({
    required String dynamicId,
    required String content,
    int? replyToUserId,
    String? replyToCommentId,
  }) async {
    final String value = content.trim();
    if (value.isEmpty || value.length > 200) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '评论内容需为 1～200 个字',
      );
    }
    final ApiResponse response = await _apiClient.post(
      _routes.dynamicComment,
      body: <String, Object?>{
        'dynamicId': _numericId(dynamicId),
        'content': value,
        if (replyToUserId != null) 'replyToUserId': replyToUserId,
        if (replyToCommentId != null) 'replyToCommentId': _numericId(replyToCommentId),
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final DynamicComment comment = data.isEmpty
        ? DynamicComment(
            id: 'server-${DateTime.now().microsecondsSinceEpoch}',
            dynamicId: dynamicId,
            author: DynamicAuthor(
              userId: _currentUserIdProvider(),
              nickname: '我',
            ),
            content: value,
            createdAt: '刚刚',
            replyToUserId: replyToUserId,
            replyToCommentId: replyToCommentId,
          )
        : _commentFromMap(dynamicId, data);
    final DynamicPost? current = _postCache[dynamicId];
    if (current != null) {
      _postCache[dynamicId] = current.copyWith(
        commentCount: current.commentCount + 1,
      );
    }
    return comment;
  }

  @override
  Future<DynamicPost> publish(PublishDynamicRequest request) async {
    final String content = request.content.trim();
    if (content.isEmpty || content.length > 1000) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '动态内容需为 1～1000 个字',
      );
    }
    if (request.images.isNotEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '图片上传服务尚未接入',
      );
    }
    final ApiResponse response = await _apiClient.post(
      _routes.dynamicPublish,
      body: <String, Object?>{
        'content': content,
        'images': '',
        'tags': request.category == DynamicCategory.all
            ? '聊天'
            : request.category.label,
        'location': request.location.trim(),
        'topics': request.topics.join(','),
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态已提交，但服务端未返回动态详情',
      );
    }
    final DynamicPost post = _postFromMap(data);
    if (post.id.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端未返回有效动态编号',
      );
    }
    _postCache[post.id] = post;
    return post;
  }

  @override
  Future<void> deletePost(String dynamicId) async {
    await _apiClient.delete('${_routes.dynamicDelete}/$dynamicId');
    _postCache.remove(dynamicId);
  }

  @override
  Future<RankingSnapshot> fetchRanking({
    required RankingBoard board,
    required RankingPeriod period,
  }) async {
    if (board == RankingBoard.room) {
      final ApiResponse response = await _apiClient.post(
        _routes.roomRanking,
        body: <String, Object?>{'rankType': period.roomBackendValue},
      );
      final Map<String, Object?> data = _asMap(response.data);
      final List<RankingEntry> entries = <RankingEntry>[];
      final List<Map<String, Object?>> raw = _asMapList(data['itemVos'] ?? data['list']);
      for (int index = 0; index < raw.length; index += 1) {
        final Map<String, Object?> item = raw[index];
        entries.add(RankingEntry(
          rank: _asInt(item['rankNo']) ?? index + 1,
          roomId: _string(item['roomId']),
          name: _string(item['roomName'], fallback: '语音房'),
          avatarUrl: _optionalString(item['roomHeadImgUrl']),
          value: _asNum(item['theVal'] ?? item['value']) ?? 0,
          subtitle: _string(item['text']),
        ));
      }
      return RankingSnapshot(
        board: board,
        period: period,
        entries: entries,
        countdownSeconds: _asInt(data['cd'] ?? data['countdown']) ?? 0,
      );
    }

    final String route = switch (board) {
      RankingBoard.charm => _routes.charmRanking,
      RankingBoard.wealth => _routes.wealthRanking,
      RankingBoard.contribution => _routes.contributionRanking,
      RankingBoard.room => throw StateError('handled above'),
    };
    final ApiResponse response = await _apiClient.post(
      route,
      body: <String, Object?>{'theType': period.userBackendValue},
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<RankingEntry> entries = <RankingEntry>[];
    final List<Map<String, Object?>> raw = _asMapList(data['ranks'] ?? data['list']);
    for (int index = 0; index < raw.length; index += 1) {
      entries.add(_userRank(raw[index], fallbackRank: index + 1));
    }
    final Map<String, Object?> self = _asMap(data['selfRank']);
    return RankingSnapshot(
      board: board,
      period: period,
      entries: entries,
      countdownSeconds: _asInt(data['countdown']) ?? 0,
      selfEntry: self.isEmpty ? null : _userRank(self),
    );
  }

  static RankingEntry _userRank(
    Map<String, Object?> item, {
    int fallbackRank = 0,
  }) {
    return RankingEntry(
      rank: _asInt(item['rankNo']) ?? fallbackRank,
      userId: _asInt(item['userId'] ?? item['attachUserId']),
      name: _string(
        item['userNickname'] ?? item['nickName'],
        fallback: '用户',
      ),
      avatarUrl: _optionalString(item['userHeadImg'] ?? item['headImgUrl']),
      value: _asNum(item['theVal'] ?? item['value']) ?? 0,
      subtitle: _string(item['text']),
    );
  }

  static DynamicPost _postFromMap(Map<String, Object?> item) {
    final int userId = _asInt(item['userId']) ?? 0;
    return DynamicPost(
      id: _string(item['id'] ?? item['dynamicId']),
      author: DynamicAuthor(
        userId: userId,
        nickname: _string(item['nickname'] ?? item['nickName'], fallback: '用户$userId'),
        avatarUrl: _optionalString(item['avatarUrl'] ?? item['headImgUrl']),
        gender: _asInt(item['gender'] ?? item['sex']) ?? 0,
      ),
      content: _string(item['content']),
      images: _split(item['images']),
      location: _string(item['location']),
      tags: _split(item['tags']),
      topics: _split(item['topics']),
      likeCount: _asInt(item['likeCount']) ?? 0,
      commentCount: _asInt(item['commentCount']) ?? 0,
      isLiked: _asBool(item['isLiked']),
      isCollected: _asBool(item['isCollected']),
      unlockChat: _asBool(item['unlockChat']),
      createdAt: _string(
        item['createTimeText'] ?? item['createdAt'] ?? item['createTime'],
        fallback: '刚刚',
      ),
    );
  }

  static DynamicComment _commentFromMap(
    String dynamicId,
    Map<String, Object?> item,
  ) {
    final int userId = _asInt(item['userId']) ?? 0;
    return DynamicComment(
      id: _string(item['id'] ?? item['commentId']),
      dynamicId: dynamicId,
      author: DynamicAuthor(
        userId: userId,
        nickname: _string(item['nickname'] ?? item['nickName'], fallback: '用户$userId'),
        avatarUrl: _optionalString(item['avatarUrl'] ?? item['headImgUrl']),
      ),
      content: _string(item['content']),
      createdAt: _string(
        item['createTimeText'] ?? item['createdAt'] ?? item['createTime'],
        fallback: '刚刚',
      ),
      replyToUserId: _asInt(item['replyToUserId']),
      replyToNickname: _optionalString(item['replyToNickname']),
      replyToCommentId: _optionalString(item['replyToCommentId']),
    );
  }

  static Map<String, Object?> _pageData(Object? data) {
    final Map<String, Object?> map = _asMap(data);
    final Map<String, Object?> nested = _asMap(map['page'] ?? map['result']);
    return nested.isEmpty ? map : nested;
  }

  static List<Map<String, Object?>> _items(Map<String, Object?> data) =>
      _asMapList(data['records'] ?? data['list'] ?? data['rows'] ?? data['items']);

  static bool _hasMore(
    Map<String, Object?> data, {
    required int page,
    required int pageSize,
    required int count,
  }) {
    final int? totalPages = _asInt(data['pages'] ?? data['totalPages']);
    if (totalPages != null) {
      return page < totalPages;
    }
    final int? total = _asInt(data['total']);
    if (total != null) {
      return page * pageSize < total;
    }
    return count >= pageSize;
  }

  static Object _numericId(String value) => int.tryParse(value) ?? value;
  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};
  static List<Map<String, Object?>> _asMapList(Object? value) => value is List
      ? value.whereType<Map<String, Object?>>().toList(growable: false)
      : const <Map<String, Object?>>[];
  static String _string(Object? value, {String fallback = ''}) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }
  static String? _optionalString(Object? value) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? null : result;
  }
  static int? _asInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
  static num? _asNum(Object? value) =>
      value is num ? value : num.tryParse(value?.toString() ?? '');
  static bool _asBool(Object? value) =>
      value == true || value == 1 || value?.toString() == '1';
  static List<String> _split(Object? value) {
    if (value is List) {
      return value
          .map((Object? item) => item?.toString().trim() ?? '')
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return (value?.toString() ?? '')
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
