import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_request_id.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_repository.dart';

class BackendDynamicRepository implements DynamicRepository {
  static const int _maxPageSize = 50;

  BackendDynamicRepository({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
    required int Function() currentUserIdProvider,
  }) : _apiClient = apiClient,
       _routes = routes,
       _currentUserIdProvider = currentUserIdProvider;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final int Function() _currentUserIdProvider;
  final Map<String, DynamicPost> _postCache = <String, DynamicPost>{};
  final Map<String, Future<void>> _pendingDeleteSubmissions =
      <String, Future<void>>{};
  final Map<String, String> _retainedDeleteRequestIds = <String, String>{};

  @override
  bool get supportsImagePublishing => false;

  @override
  Future<PagedResult<DynamicPost>> fetchFeed({
    DynamicCategory category = DynamicCategory.all,
    int page = 1,
    int pageSize = 20,
  }) async {
    _validatePageRequest(page: page, pageSize: pageSize);
    final String? backendCategory = _backendFeedCategory(category);
    final ApiResponse response = await _apiClient.get(
      _routes.dynamicList,
      query: <String, String>{
        'pageNum': '$page',
        'pageSize': '$pageSize',
        if (backendCategory != null) 'category': backendCategory,
      },
    );
    final Map<String, Object?> pageData = _pageData(response.data);
    final List<Map<String, Object?>> rawItems = _items(pageData);
    final bool hasMore = _hasMore(
      pageData,
      page: page,
      pageSize: pageSize,
      count: rawItems.length,
    );
    final List<DynamicPost> items = rawItems
        .map(_postFromMap)
        .toList(growable: false);
    for (final DynamicPost post in items) {
      _postCache[post.id] = post;
    }
    return PagedResult<DynamicPost>(items: items, page: page, hasMore: hasMore);
  }

  @override
  Future<DynamicPost> fetchPost(String dynamicId) async {
    final String normalizedId = dynamicId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '动态 ID 不能为空',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.dynamicDetail,
      query: <String, String>{'dynamicId': normalizedId},
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端未返回动态详情',
      );
    }
    final DynamicPost post = _postFromMap(data);
    if (post.id != normalizedId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态详情 ID 与请求不一致',
      );
    }
    _postCache[post.id] = post;
    return post;
  }

  @override
  Future<PagedResult<DynamicComment>> fetchComments({
    required String dynamicId,
    int page = 1,
    int pageSize = 30,
  }) async {
    _validatePageRequest(page: page, pageSize: pageSize);
    final String normalizedId = dynamicId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '动态 ID 不能为空',
      );
    }
    final ApiResponse response = await _apiClient.get(
      _routes.dynamicComments,
      query: <String, String>{
        'dynamicId': normalizedId,
        'pageNum': '$page',
        'pageSize': '$pageSize',
      },
    );
    final Map<String, Object?> pageData = _pageData(response.data);
    final List<Map<String, Object?>> rawItems = _items(pageData);
    final bool hasMore = _hasMore(
      pageData,
      page: page,
      pageSize: pageSize,
      count: rawItems.length,
    );
    final List<DynamicComment> items = rawItems
        .map((Map<String, Object?> item) => _commentFromMap(normalizedId, item))
        .toList(growable: false);
    return PagedResult<DynamicComment>(
      items: items,
      page: page,
      hasMore: hasMore,
    );
  }

  @override
  Future<DynamicPost> toggleLike(
    String dynamicId, {
    required bool liked,
    String? requestId,
  }) async {
    final String normalizedId = dynamicId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '动态 ID 不能为空',
      );
    }
    final ApiResponse response = await _apiClient.post(
      _routes.dynamicLike,
      headers: _requestHeaders(requestId),
      body: <String, Object?>{
        'dynamicId': normalizedId,
        'liked': liked,
        'type': liked ? 1 : 0,
      },
    );
    final Map<String, Object?> mutation = _asMap(response.data);
    if (mutation.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端未返回点赞结果',
      );
    }
    // Re-read the post after the mutation. The server owns both the like
    // state and the counter; never derive either value from a stale cache.
    return fetchPost(normalizedId);
  }

  @override
  Future<DynamicComment> addComment({
    required String dynamicId,
    required String content,
    int? replyToUserId,
    String? replyToCommentId,
    String? requestId,
  }) async {
    final String normalizedId = dynamicId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '动态 ID 不能为空',
      );
    }
    if (_currentUserIdProvider() <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: '登录会话已失效',
      );
    }
    final String value = content.trim();
    if (value.isEmpty || value.length > 200) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '评论内容需为 1～200 个字',
      );
    }
    final ApiResponse response = await _apiClient.post(
      _routes.dynamicComment,
      headers: _requestHeaders(requestId),
      body: <String, Object?>{
        'dynamicId': _numericId(normalizedId),
        'content': value,
        if (replyToUserId != null) 'replyToUserId': replyToUserId,
        if (replyToCommentId != null) 'parentCommentId': replyToCommentId,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端未返回评论详情',
      );
    }
    // A comment changes the authoritative server-side count. Invalidate the
    // local entry instead of manufacturing a local comment/count.
    _postCache.remove(normalizedId);
    return _commentFromMap(normalizedId, data);
  }

  @override
  Future<DynamicPost> publish(
    PublishDynamicRequest request, {
    String? requestId,
  }) async {
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
    final String backendCategory = _backendPublishCategory(request.category);
    final ApiResponse response = await _apiClient.post(
      _routes.dynamicPublish,
      headers: _requestHeaders(requestId),
      body: <String, Object?>{
        'content': content,
        'category': backendCategory,
        'topic': request.topics.join(','),
        'location': request.location.trim(),
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
    _postCache[post.id] = post;
    return post;
  }

  @override
  Future<void> deletePost(String dynamicId) async {
    final String normalizedId = dynamicId.trim();
    if (normalizedId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '动态 ID 不能为空',
      );
    }
    final Future<void>? pending = _pendingDeleteSubmissions[normalizedId];
    if (pending != null) {
      return pending;
    }
    final String requestId = _retainedDeleteRequestIds[normalizedId] ??=
        newDynamicRequestId('dynamic-delete');
    final Future<void> request =
        _deletePostOnce(normalizedId, requestId: requestId).then<void>(
          (_) {
            _pendingDeleteSubmissions.remove(normalizedId);
            _retainedDeleteRequestIds.remove(normalizedId);
            _postCache.remove(normalizedId);
          },
          onError: (Object error, StackTrace stackTrace) {
            _pendingDeleteSubmissions.remove(normalizedId);
            if (!shouldRetainDynamicWriteRequest(error)) {
              _retainedDeleteRequestIds.remove(normalizedId);
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    _pendingDeleteSubmissions[normalizedId] = request;
    return request;
  }

  Future<void> _deletePostOnce(
    String normalizedId, {
    required String requestId,
  }) async {
    final ApiResponse response = await _apiClient.delete(
      '${_routes.dynamicDelete}/${Uri.encodeComponent(normalizedId)}',
      headers: _requestHeaders(requestId),
    );
    final Map<String, Object?> data = _requireMap(response.data, '动态删除');
    if (_requiredServerId(data['dynamicId'], field: '动态删除编号') != normalizedId ||
        data['deleted'] is! bool ||
        data['deleted'] != true ||
        _requiredString(data['status'], field: '动态删除状态') != 'DELETED') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态删除响应与请求不一致',
      );
    }
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
      final Map<String, Object?> data = _rankingPage(
        response.data,
        expectedMetric: 'ROOM_CONTRIBUTION',
      );
      final List<Map<String, Object?>> raw = _rankingItems(data);
      final List<RankingEntry> entries = <RankingEntry>[];
      for (final Map<String, Object?> item in raw) {
        final int rank = _requiredPositiveInt(item['rank'], '房间榜 rank');
        final String roomId = _requiredString(
          item['roomId'],
          field: '房间榜 roomId',
        );
        final String name = _requiredString(
          item['roomName'],
          field: '房间榜 roomName',
        );
        entries.add(
          RankingEntry(
            rank: rank,
            roomId: roomId,
            name: name,
            avatarUrl: _optionalString(item['roomHeadImgUrl']),
            value: _requiredNonNegativeNum(item['score'], '房间榜 score'),
            subtitle: _optionalString(item['metric']) ?? '',
          ),
        );
      }
      return RankingSnapshot(
        board: board,
        period: period,
        entries: entries,
        countdownSeconds: _optionalNonNegativeInt(data['countdown']) ?? 0,
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
    final Map<String, Object?> data = _rankingPage(
      response.data,
      expectedMetric: board.name.toUpperCase(),
    );
    final List<Map<String, Object?>> raw = _rankingItems(data);
    final List<RankingEntry> entries = <RankingEntry>[];
    for (final Map<String, Object?> item in raw) {
      entries.add(_userRank(item));
    }
    final Map<String, Object?> self = data.containsKey('selfRank')
        ? _requireMap(data['selfRank'], '排行榜 selfRank', allowEmpty: true)
        : const <String, Object?>{};
    return RankingSnapshot(
      board: board,
      period: period,
      entries: entries,
      countdownSeconds: _optionalNonNegativeInt(data['countdown']) ?? 0,
      selfEntry: self.isEmpty ? null : _userRank(self),
    );
  }

  static RankingEntry _userRank(Map<String, Object?> item) {
    return RankingEntry(
      rank: _requiredPositiveInt(item['rank'], '用户榜 rank'),
      userId: _requiredPositiveInt(item['userId'], '用户榜 userId'),
      name: _requiredString(item['nickName'], field: '用户榜 nickName'),
      avatarUrl: _optionalString(item['userHeadImg'] ?? item['headImgUrl']),
      value: _requiredNonNegativeNum(item['score'], '用户榜 score'),
      subtitle: _optionalString(item['metric']) ?? '',
    );
  }

  static DynamicPost _postFromMap(Map<String, Object?> item) {
    final String id = _requiredServerId(
      item['dynamicId'] ?? item['id'],
      field: '动态编号',
    );
    if (item.containsKey('id') &&
        item['id'] != null &&
        _requiredServerId(item['id'], field: '动态 id') != id) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态 id 与 dynamicId 不一致',
      );
    }
    final int userId = _requiredPositiveInt(item['userId'], '动态 userId');
    final String nickname = _requiredString(
      item['nickName'] ?? item['nickname'],
      field: '动态 nickName',
    );
    if (item.containsKey('nickname') &&
        item['nickname'] != null &&
        _requiredString(item['nickname'], field: '动态 nickname') != nickname) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态 nickName 与 nickname 不一致',
      );
    }
    final String content = _requiredString(
      item['content'],
      field: '动态 content',
    );
    final int likeCount = _requiredNonNegativeInt(
      item['likeCount'],
      '动态 likeCount',
    );
    final int commentCount = _requiredNonNegativeInt(
      item['commentCount'],
      '动态 commentCount',
    );
    final bool liked = _requiredBool(
      item['liked'] ?? (item.containsKey('isLiked') ? item['isLiked'] : null),
      '动态 liked',
    );
    final String category = _supportedBackendPostCategory(item['category']);
    if (item.containsKey('isLike')) {
      final int flag = _requiredBinaryInt(item['isLike'], '动态 isLike');
      if (liked != (flag == 1)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '动态 liked 与 isLike 不一致',
        );
      }
    }
    return DynamicPost(
      id: id,
      author: DynamicAuthor(
        userId: userId,
        nickname: nickname,
        avatarUrl: _optionalString(item['avatarUrl'] ?? item['headImgUrl']),
        gender: _asInt(item['gender'] ?? item['sex']) ?? 0,
      ),
      content: content,
      images: _strictStringList(item['images'], '动态 images'),
      location: _string(item['location']),
      tags: <String>[category],
      topics: _split(item['topic']),
      likeCount: likeCount,
      commentCount: commentCount,
      isLiked: liked,
      isCollected: item.containsKey('isCollected')
          ? _requiredBool(item['isCollected'], '动态 isCollected')
          : false,
      unlockChat: item.containsKey('unlockChat')
          ? _requiredBool(item['unlockChat'], '动态 unlockChat')
          : false,
      createdAt: _requiredServiceTime(item, field: '动态创建时间'),
    );
  }

  static DynamicComment _commentFromMap(
    String dynamicId,
    Map<String, Object?> item,
  ) {
    final String id = _requiredServerId(
      item['id'] ?? item['commentId'],
      field: '评论编号',
    );
    final int userId = _requiredPositiveInt(item['userId'], '评论 userId');
    final String nickname = _requiredString(
      item['nickName'] ?? item['nickname'],
      field: '评论 nickName',
    );
    if (item.containsKey('nickname') &&
        item['nickname'] != null &&
        _requiredString(item['nickname'], field: '评论 nickname') != nickname) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '评论 nickName 与 nickname 不一致',
      );
    }
    return DynamicComment(
      id: id,
      dynamicId: dynamicId,
      author: DynamicAuthor(
        userId: userId,
        nickname: nickname,
        avatarUrl: _optionalString(item['avatarUrl'] ?? item['headImgUrl']),
      ),
      content: _requiredString(item['content'], field: '评论 content'),
      createdAt: _requiredServiceTime(item, field: '评论创建时间'),
      replyToUserId: _asInt(item['replyToUserId']),
      replyToNickname: _optionalString(item['replyToNickname']),
      replyToCommentId: _optionalString(
        item['parentCommentId'] ?? item['replyToCommentId'],
      ),
    );
  }

  static Map<String, Object?> _rankingPage(
    Object? value, {
    required String expectedMetric,
  }) {
    final Map<String, Object?> data = _requireMap(value, '排行榜响应');
    if (data['serverAuthoritative'] != true) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '排行榜响应不是服务端权威数据',
      );
    }
    final String metric = _requiredString(data['metric'], field: '排行榜 metric');
    if (metric != expectedMetric) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '排行榜 metric 与请求榜单不一致',
      );
    }
    final int current = _requiredPositiveInt(data['current'], '排行榜 current');
    final int pageSize = _requiredPositiveInt(data['pageSize'], '排行榜 pageSize');
    final int total = _requiredNonNegativeInt(data['total'], '排行榜 total');
    final int pages = _requiredNonNegativeInt(data['pages'], '排行榜 pages');
    const int requestedPage = 1;
    const int requestedPageSize = 20;
    final int expectedPages = total == 0
        ? 0
        : (total / requestedPageSize).ceil();
    if (current != requestedPage ||
        pageSize != requestedPageSize ||
        pages != expectedPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '排行榜分页元数据与请求或 total 不一致',
      );
    }
    return data;
  }

  static List<Map<String, Object?>> _rankingItems(Map<String, Object?> data) {
    final List<Map<String, Object?>> records = _asMapList(
      data['records'],
      field: '排行榜 records',
      required: true,
    );
    final List<Map<String, Object?>> list = _asMapList(
      data['list'],
      field: '排行榜 list',
      required: true,
    );
    if (!_deepEqual(records, list)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '排行榜 records 与 list 不一致',
      );
    }
    final int total = _requiredNonNegativeInt(data['total'], '排行榜 total');
    final int expectedCount = total == 0 ? 0 : total.clamp(0, 20).toInt();
    if (records.length != expectedCount) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '排行榜当前页条目数与 total 不一致',
      );
    }
    return records;
  }

  static Map<String, Object?> _pageData(Object? data) {
    final Map<String, Object?> map = _requireMap(data, '动态分页');
    _items(map);
    return map;
  }

  static List<Map<String, Object?>> _items(Map<String, Object?> data) {
    if (!data.containsKey('records') || !data.containsKey('list')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态分页缺少 records 或 list',
      );
    }
    final List<Map<String, Object?>> records = _asMapList(
      data['records'],
      field: 'records',
      required: true,
    );
    final List<Map<String, Object?>> list = _asMapList(
      data['list'],
      field: 'list',
      required: true,
    );
    if (!_deepEqual(records, list)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态分页 records 与 list 不一致',
      );
    }
    return records;
  }

  static bool _hasMore(
    Map<String, Object?> data, {
    required int page,
    required int pageSize,
    required int count,
  }) {
    final int? current = _asInt(data['current']);
    if (current == null || current != page) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态分页 current 与请求页不一致',
      );
    }
    final int? responsePageSize = _asInt(data['pageSize']);
    if (responsePageSize == null || responsePageSize != pageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态分页 pageSize 与请求不一致',
      );
    }
    final int? responseSize = _asInt(data['size']);
    if (data.containsKey('size') && responseSize != pageSize) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态分页额外 size 字段与 pageSize 不一致',
      );
    }
    final int? total = _asInt(data['total']);
    if (total == null || total < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态分页 total 不是有效服务端数字',
      );
    }
    final int? totalPages = _asInt(data['pages']);
    if (totalPages == null || totalPages < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态分页 pages 不是有效服务端数字',
      );
    }
    final int expectedPages = total == 0 ? 0 : (total / pageSize).ceil();
    if (totalPages != expectedPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态分页 pages 与 total 不一致',
      );
    }
    final int expectedCount = total == 0
        ? 0
        : (total - ((page - 1) * pageSize)).clamp(0, pageSize).toInt();
    if (count != expectedCount) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: count == 0 && page < totalPages
            ? '动态分页空页仍有更多数据'
            : '动态分页 records 数量与 total 不一致',
      );
    }
    return page < totalPages;
  }

  static void _validatePageRequest({required int page, required int pageSize}) {
    if (page < 1 || pageSize < 1 || pageSize > _maxPageSize) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '动态分页请求参数无效，pageSize 不能超过 50',
      );
    }
  }

  static String _requiredServerId(Object? value, {required String field}) {
    final String id = _string(value);
    if (id.isEmpty) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$field缺失');
    }
    return id;
  }

  static String _requiredString(Object? value, {required String field}) {
    if (value is! String || value.trim().isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 缺失或无效',
      );
    }
    return value.trim();
  }

  static int _requiredPositiveInt(Object? value, String field) {
    if (value is! int || value <= 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 缺失或无效',
      );
    }
    return value;
  }

  static int _requiredNonNegativeInt(Object? value, String field) {
    if (value is! int || value < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 缺失或无效',
      );
    }
    return value;
  }

  static int? _optionalNonNegativeInt(Object? value) {
    if (value == null) {
      return null;
    }
    return _requiredNonNegativeInt(value, '排行榜 countdown');
  }

  static num _requiredNonNegativeNum(Object? value, String field) {
    if (value is! num || value < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 缺失或无效',
      );
    }
    return value;
  }

  static bool _requiredBool(Object? value, String field) {
    if (value is! bool) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 缺失或无效',
      );
    }
    return value;
  }

  static int _requiredBinaryInt(Object? value, String field) {
    if (value is! int || (value != 0 && value != 1)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 缺失或无效',
      );
    }
    return value;
  }

  static String _requiredServiceTime(
    Map<String, Object?> item, {
    required String field,
  }) {
    final String value = _string(item['createdAt'] ?? item['createTime']);
    if (value.isEmpty || DateTime.tryParse(value) == null) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$field缺失或无效');
    }
    return value;
  }

  static Object _numericId(String value) => int.tryParse(value) ?? value;

  static Map<String, String>? _requestHeaders(String? requestId) {
    final String? raw = requestId?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return <String, String>{'X-Request-Id': normalizeDynamicRequestId(raw)};
  }

  static String? _backendFeedCategory(DynamicCategory category) =>
      switch (category) {
        DynamicCategory.all => null,
        DynamicCategory.companionship => 'LIFE',
        DynamicCategory.music => throw const ApiException(
          kind: ApiFailureKind.configuration,
          message: '第一方后端尚不支持音乐动态分类',
        ),
        DynamicCategory.chat => 'CHAT',
      };

  static String _backendPublishCategory(DynamicCategory category) =>
      switch (category) {
        DynamicCategory.companionship => 'LIFE',
        DynamicCategory.chat => 'CHAT',
        DynamicCategory.music => throw const ApiException(
          kind: ApiFailureKind.configuration,
          message: '第一方后端尚不支持音乐动态分类，无法发布',
        ),
        DynamicCategory.all => throw const ApiException(
          kind: ApiFailureKind.configuration,
          message: '发布动态必须选择第一方后端支持的明确分类',
        ),
      };

  static String _supportedBackendPostCategory(Object? value) {
    if (value is String && (value == 'LIFE' || value == 'CHAT')) {
      return value;
    }
    throw const ApiException(
      kind: ApiFailureKind.protocol,
      message: '服务端返回了客户端不支持的动态分类',
    );
  }

  static Map<String, Object?> _requireMap(
    Object? value,
    String field, {
    bool allowEmpty = false,
  }) {
    if (value is! Map) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$field 不是对象');
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field 包含非字符串字段名',
        );
      }
      result[entry.key as String] = entry.value;
    }
    if (!allowEmpty && result.isEmpty) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$field 为空');
    }
    return result;
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static List<Map<String, Object?>> _asMapList(
    Object? value, {
    String field = '列表',
    bool required = false,
  }) {
    if (value == null && !required) {
      return const <Map<String, Object?>>[];
    }
    if (value is! List) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '动态$field不是数组',
      );
    }
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Object? item in value) {
      if (item is! Map) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '动态$field包含非对象元素',
        );
      }
      result.add(_requireMap(item, field, allowEmpty: false));
    }
    return List<Map<String, Object?>>.unmodifiable(result);
  }

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

  static List<String> _strictStringList(Object? value, String field) {
    if (value is! List) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field 缺失或无效',
      );
    }
    final List<String> result = <String>[];
    for (final Object? item in value) {
      if (item is! String) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field 包含无效元素',
        );
      }
      result.add(item);
    }
    return List<String>.unmodifiable(result);
  }

  static bool _deepEqual(Object? left, Object? right) {
    if (left is List && right is List) {
      return left.length == right.length &&
          Iterable<int>.generate(
            left.length,
          ).every((int index) => _deepEqual(left[index], right[index]));
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final Object? key in left.keys) {
        if (!right.containsKey(key) || !_deepEqual(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }
}
