import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

class BackendSocialRepository implements SocialRepository {
  BackendSocialRepository({
    required ApiClient apiClient,
    required int Function() currentUserIdProvider,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  })  : _apiClient = apiClient,
        _currentUserIdProvider = currentUserIdProvider,
        _routes = routes;

  final ApiClient _apiClient;
  final int Function() _currentUserIdProvider;
  final BackendRouteCatalog _routes;
  PrivacySettings _privacy = const PrivacySettings(
    onlyFollowedCanFollow: false,
    serverValueKnown: false,
  );
  final Map<String, SupportTicket> _submittedTickets =
      <String, SupportTicket>{};

  @override
  bool get supportsFriendRequestWorkflow => false;

  @override
  bool get supportsTicketProgress => false;

  @override
  Future<SocialProfile> fetchMyProfile() async {
    final ApiResponse personalResponse = await _apiClient.get(
      _routes.personalData,
    );
    final Map<String, Object?> personal = _asMap(personalResponse.data);
    Map<String, Object?> homepage = const <String, Object?>{};
    try {
      final ApiResponse homepageResponse = await _apiClient.get(
        _routes.personalHomepage,
      );
      homepage = _asMap(homepageResponse.data);
    } on ApiException {
      // The personal-data contract is sufficient for the profile root.
    }
    final int userId = _asInt(personal['id']) ?? _currentUserIdProvider();
    return _profileFromMaps(
      userId: userId,
      personal: personal,
      homepage: homepage,
      isSelf: true,
    );
  }

  @override
  Future<SocialProfile> updateMyProfile({
    required String nickname,
    required String signature,
    required int sex,
    required String birthday,
    required String city,
  }) async {
    final String normalizedName = nickname.trim();
    final String normalizedSignature = signature.trim();
    if (normalizedName.isEmpty || normalizedName.length > 64) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '昵称长度应为 1 至 64 个字符',
      );
    }
    if (normalizedSignature.length > 150) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '个性签名不能超过 150 个字符',
      );
    }
    await _apiClient.patch(
      _routes.updateUserProfile,
      body: <String, Object?>{
        'nickName': normalizedName,
        'signature': normalizedSignature,
        'sex': sex,
        'birthday': birthday,
        'address': city,
      },
    );
    return fetchMyProfile();
  }

  @override
  Future<SocialProfile> fetchPublicProfile(int userId) async {
    final ApiResponse response = await _apiClient.get(
      _routes.personalHomepage,
      query: <String, String>{'userId': '$userId'},
    );
    final Map<String, Object?> homepage = _asMap(response.data);
    if (homepage.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '用户主页响应为空',
      );
    }
    return _profileFromMaps(
      userId: userId,
      personal: const <String, Object?>{},
      homepage: homepage,
      isSelf: false,
    );
  }

  @override
  Future<SocialPage<SocialUser>> fetchRelations({
    required SocialRelationList type,
    required int page,
    required int pageSize,
  }) async {
    final String route = switch (type) {
      SocialRelationList.following => _routes.followingList,
      SocialRelationList.followers => _routes.followersList,
      SocialRelationList.friends => _routes.friendsList,
    };
    final ApiResponse response = await _apiClient.post(
      route,
      body: <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        'isSearchCount': true,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<SocialUser> items = <SocialUser>[
      for (final Object? raw in _asList(data['list']))
        if (raw is Map<String, Object?>) _relationUser(raw, type),
    ];
    return _socialPage(data, items, page: page, pageSize: pageSize);
  }

  @override
  Future<void> setFollowing({
    required int userId,
    required bool following,
  }) async {
    await _apiClient.get(
      _routes.setFollowing,
      query: <String, String>{
        'userId': '$userId',
        'type': following ? '1' : '0',
      },
    );
  }

  @override
  Future<List<FriendRequest>> fetchFriendRequests() async =>
      const <FriendRequest>[];

  @override
  Future<void> resolveFriendRequest({
    required String requestId,
    required bool accepted,
  }) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '当前后端只有关注与互相关注关系，没有确认的好友请求接受/拒绝协议',
    );
  }

  @override
  Future<SocialPage<SocialUser>> fetchVisitors({
    required VisitorRecordType type,
    required int page,
    required int pageSize,
  }) async {
    final ApiResponse response = await _apiClient.get(
      _routes.visitorRecords,
      query: <String, String>{
        'type': type == VisitorRecordType.viewedMe ? '1' : '2',
        'pageNum': '$page',
        'pageSize': '$pageSize',
        'isSearchCount': 'true',
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<SocialUser> items = <SocialUser>[
      for (final Object? raw in _asList(data['list']))
        if (raw is Map<String, Object?>)
          SocialUser(
            userId: _asInt(raw['userId']) ?? 0,
            name: _string(raw['nickname'], fallback: '访客'),
            signature: '',
            avatarUrl: _string(raw['headImgUrl']),
            isFollowing: false,
            isFollower: false,
            isFriend: false,
            isBlocked: false,
            isOnline: false,
            visitedAt: _asDateTime(raw['visitedDate']),
            visitCount: _asInt(raw['visitUserNum']) ?? 1,
          ),
    ];
    return _socialPage(data, items, page: page, pageSize: pageSize);
  }

  @override
  Future<PrivacySettings> fetchPrivacySettings() async => _privacy;

  @override
  Future<PrivacySettings> updatePrivacySettings({
    required bool onlyFollowedCanFollow,
  }) async {
    await _apiClient.get(
      _routes.onlyFollowedCanFollow,
      query: <String, String>{
        'type': onlyFollowedCanFollow ? '1' : '0',
      },
    );
    _privacy = PrivacySettings(
      onlyFollowedCanFollow: onlyFollowedCanFollow,
      serverValueKnown: true,
    );
    return _privacy;
  }

  @override
  Future<SocialPage<SocialUser>> fetchBlacklist({
    required int page,
    required int pageSize,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _routes.blacklist,
      body: <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        'isSearchCount': true,
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    final List<SocialUser> items = <SocialUser>[
      for (final Object? raw in _asList(data['list']))
        if (raw is Map<String, Object?>)
          SocialUser(
            userId: _asInt(raw['userId']) ?? 0,
            name: _string(raw['nickName'], fallback: '已屏蔽用户'),
            signature: '',
            avatarUrl: _string(raw['headImgUrl']),
            isFollowing: false,
            isFollower: false,
            isFriend: false,
            isBlocked: true,
            isOnline: false,
          ),
    ];
    return _socialPage(data, items, page: page, pageSize: pageSize);
  }

  @override
  Future<void> setBlocked({
    required int userId,
    required bool blocked,
  }) async {
    await _apiClient.get(
      _routes.setBlocked,
      query: <String, String>{
        'userId': '$userId',
        'type': blocked ? '1' : '0',
      },
    );
  }

  @override
  Future<String> submitReport({
    required ReportTargetType targetType,
    required String targetId,
    required int reasonCode,
    required String description,
    required bool alsoBlock,
  }) async {
    final int currentUserId = _currentUserIdProvider();
    if (currentUserId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: '登录会话已失效',
      );
    }
    await _apiClient.post(
      _routes.reportUserOrRoom,
      body: <String, Object?>{
        'userId': currentUserId,
        'beTipUserId': targetType == ReportTargetType.user
            ? int.tryParse(targetId)
            : null,
        'beTipRoomId': targetType == ReportTargetType.room
            ? int.tryParse(targetId)
            : null,
        'tipType': reasonCode,
        'tipDescrib': description.trim(),
        'tipOffImages': const <String>[],
        'type': alsoBlock ? 1 : 2,
      },
    );
    return 'server-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<SupportChannel> fetchCustomerService() async {
    final ApiResponse response = await _apiClient.get(
      _routes.customerService,
    );
    final Map<String, Object?> data = _asMap(response.data);
    return SupportChannel(
      id: _string(data['accid'], fallback: 'customer-service'),
      name: '平台客服',
      description: '即时客服会话需要腾讯 IM；当前可以提交意见反馈。',
      liveConversationAvailable: false,
    );
  }

  @override
  Future<SupportTicket> submitFeedback({
    required String subject,
    required String content,
  }) async {
    final String normalized = content.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '反馈内容应为 1 至 200 个字符',
      );
    }
    await _apiClient.post(
      _routes.submitFeedback,
      query: <String, String>{'content': normalized},
    );
    final String id = 'feedback-${DateTime.now().millisecondsSinceEpoch}';
    final SupportTicket ticket = SupportTicket(
      id: id,
      subject: subject.trim().isEmpty ? '意见反馈' : subject.trim(),
      content: normalized,
      status: SupportTicketStatus.submitted,
      statusText: '服务端已接收反馈，但当前接口不提供处理进度查询',
      createdAt: DateTime.now(),
      progressAvailable: false,
    );
    _submittedTickets[id] = ticket;
    return ticket;
  }

  @override
  Future<SupportTicket> fetchSupportTicket(String ticketId) async {
    final SupportTicket? ticket = _submittedTickets[ticketId];
    if (ticket == null) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '当前后端意见反馈接口不提供工单进度查询',
      );
    }
    return ticket;
  }

  static SocialProfile _profileFromMaps({
    required int userId,
    required Map<String, Object?> personal,
    required Map<String, Object?> homepage,
    required bool isSelf,
  }) {
    final int relationCode = _asInt(homepage['isAttention']) ?? 0;
    final bool isFriend = relationCode == 1;
    final bool isFollowing = relationCode == 1 || relationCode == 2;
    final String roomId = _string(homepage['roomId']);
    final SocialUser user = SocialUser(
      userId: _asInt(homepage['id']) ?? _asInt(personal['id']) ?? userId,
      name: _string(
        homepage['nickName'] ?? personal['nickName'],
        fallback: isSelf ? '当前用户' : '用户 $userId',
      ),
      signature: _string(homepage['signature']),
      avatarUrl: _string(
        homepage['headImgUrl'] ?? personal['headImgUrl'],
      ),
      isFollowing: isSelf ? false : isFollowing,
      isFollower: isSelf ? false : isFriend,
      isFriend: isSelf ? false : isFriend,
      isBlocked: _asBool(homepage['isBlacklist']),
      isOnline: _asInt(homepage['isOnline']) == 1,
      roomId: roomId.isEmpty ? null : roomId,
    );
    return SocialProfile(
      user: user,
      account: _string(
        homepage['loginName'] ?? personal['loginName'],
        fallback: '$userId',
      ),
      sex: _asInt(homepage['sex']) ?? 0,
      birthday: _string(homepage['birthday']),
      city: _string(homepage['piAddress'] ?? homepage['address']),
      coverUrl: _string(homepage['coverImgUrl']),
      followingCount: _asInt(
            homepage['attentionNum'] ?? personal['attentionNum'],
          ) ??
          0,
      followerCount: _asInt(homepage['fansNum'] ?? personal['fansNum']) ?? 0,
      friendCount: _asInt(homepage['playmateNum']) ?? 0,
      postCount: _asInt(homepage['dynamicNum'] ?? personal['dynamicNum']) ?? 0,
      level: _asInt(homepage['level'] ?? personal['level']) ?? 0,
    );
  }

  static SocialUser _relationUser(
    Map<String, Object?> raw,
    SocialRelationList type,
  ) {
    final bool isFriend = type == SocialRelationList.friends ||
        _asInt(raw['mark']) == 0;
    return SocialUser(
      userId: _asInt(raw['userId']) ?? 0,
      name: _string(raw['nickName'], fallback: '用户'),
      signature: _string(raw['signature']),
      avatarUrl: _string(raw['headImgUrl']),
      isFollowing: type != SocialRelationList.followers || isFriend,
      isFollower: type != SocialRelationList.following || isFriend,
      isFriend: isFriend,
      isBlocked: false,
      isOnline: _asInt(raw['isOnline']) == 1,
      roomId: _asInt(raw['isInRoom']) == 1 && _string(raw['roomId']).isNotEmpty
          ? _string(raw['roomId'])
          : null,
    );
  }

  static SocialPage<SocialUser> _socialPage(
    Map<String, Object?> data,
    List<SocialUser> items, {
    required int page,
    required int pageSize,
  }) {
    final int current = _asInt(data['current']) ?? page;
    final int size = _asInt(data['size']) ?? pageSize;
    final int total = _asInt(data['total']) ?? items.length;
    final int pages = _asInt(data['pages']) ??
        (size <= 0 ? 1 : (total / size).ceil());
    return SocialPage<SocialUser>(
      items: items,
      page: current,
      pageSize: size,
      total: total,
      hasMore: current < pages,
    );
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};

  static List<Object?> _asList(Object? value) =>
      value is List<Object?> ? value : const <Object?>[];

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    return _asInt(value) == 1;
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  static DateTime? _asDateTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');
}
