import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

class MockSocialRepository implements SocialRepository {
  MockSocialRepository()
      : _users = <int, SocialUser>{
          10001: const SocialUser(
            userId: 10001,
            name: '晚星',
            signature: '愿每一次相遇都轻松一点。',
            avatarUrl: '',
            isFollowing: false,
            isFollower: false,
            isFriend: false,
            isBlocked: false,
            isOnline: true,
          ),
          20001: const SocialUser(
            userId: 20001,
            name: '鹿屿',
            signature: '深夜陪伴房主，慢慢聊。',
            avatarUrl: '',
            isFollowing: true,
            isFollower: true,
            isFriend: true,
            isBlocked: false,
            isOnline: true,
            roomId: '880217',
          ),
          20002: const SocialUser(
            userId: 20002,
            name: '南风',
            signature: '下班后只聊轻松的事。',
            avatarUrl: '',
            isFollowing: true,
            isFollower: false,
            isFriend: false,
            isBlocked: false,
            isOnline: false,
          ),
          20003: const SocialUser(
            userId: 20003,
            name: '阿岚',
            signature: '最近在学习更认真地倾听。',
            avatarUrl: '',
            isFollowing: false,
            isFollower: true,
            isFriend: false,
            isBlocked: false,
            isOnline: true,
            roomId: '660318',
          ),
          20004: const SocialUser(
            userId: 20004,
            name: '松子',
            signature: '音乐、电台和日常碎片。',
            avatarUrl: '',
            isFollowing: false,
            isFollower: false,
            isFriend: false,
            isBlocked: false,
            isOnline: true,
          ),
          20005: const SocialUser(
            userId: 20005,
            name: '已屏蔽用户',
            signature: '',
            avatarUrl: '',
            isFollowing: false,
            isFollower: false,
            isFriend: false,
            isBlocked: true,
            isOnline: false,
          ),
        };

  final Map<int, SocialUser> _users;
  final List<FriendRequest> _requests = <FriendRequest>[];
  final Map<String, SupportTicket> _tickets = <String, SupportTicket>{};
  PrivacySettings _privacy = const PrivacySettings(
    onlyFollowedCanFollow: false,
    serverValueKnown: true,
  );
  int _ticketSequence = 1;

  @override
  bool get supportsFriendRequestWorkflow => true;

  @override
  bool get supportsTicketProgress => true;

  void _ensureSeededRequests() {
    if (_requests.isNotEmpty) {
      return;
    }
    _requests.add(
      FriendRequest(
        id: 'request-1',
        user: _users[20004]!,
        message: '在同一个陪伴房聊过，想和你成为好友。',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        status: FriendRequestStatus.pending,
      ),
    );
  }

  @override
  Future<SocialProfile> fetchMyProfile() async {
    final SocialUser user = _users[10001]!;
    return SocialProfile(
      user: user,
      account: '10001',
      sex: 2,
      birthday: '2000-06-18',
      city: '武汉',
      coverUrl: '',
      followingCount: _users.values.where((SocialUser item) => item.isFollowing).length,
      followerCount: _users.values.where((SocialUser item) => item.isFollower).length,
      friendCount: _users.values.where((SocialUser item) => item.isFriend).length,
      postCount: 12,
      level: 8,
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
    if (sex != 1 && sex != 2) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择有效性别',
      );
    }
    _users[10001] = _users[10001]!.copyWith(
      name: normalizedName,
      signature: normalizedSignature,
    );
    final SocialProfile profile = await fetchMyProfile();
    return profile.copyWith(sex: sex, birthday: birthday, city: city);
  }

  @override
  Future<SocialProfile> fetchPublicProfile(int userId) async {
    final SocialUser? user = _users[userId];
    if (user == null) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '用户不存在或资料已不可用',
      );
    }
    return SocialProfile(
      user: user,
      account: '$userId',
      sex: userId.isEven ? 2 : 1,
      birthday: '2001-03-12',
      city: '武汉',
      coverUrl: '',
      followingCount: 36,
      followerCount: 128,
      friendCount: user.isFriend ? 48 : 0,
      postCount: 18,
      level: 12,
    );
  }

  @override
  Future<SocialPage<SocialUser>> fetchRelations({
    required SocialRelationList type,
    required int page,
    required int pageSize,
  }) async {
    final List<SocialUser> all = _users.values.where((SocialUser user) {
      if (user.userId == 10001 || user.isBlocked) {
        return false;
      }
      return switch (type) {
        SocialRelationList.following => user.isFollowing,
        SocialRelationList.followers => user.isFollower,
        SocialRelationList.friends => user.isFriend,
      };
    }).toList(growable: false);
    return _page(all, page: page, pageSize: pageSize);
  }

  @override
  Future<void> setFollowing({
    required int userId,
    required bool following,
  }) async {
    final SocialUser user = _requireUser(userId);
    if (user.isBlocked) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '请先从黑名单中移除该用户',
      );
    }
    _users[userId] = user.copyWith(
      isFollowing: following,
      isFriend: following && user.isFollower,
    );
  }

  @override
  Future<List<FriendRequest>> fetchFriendRequests() async {
    _ensureSeededRequests();
    return List<FriendRequest>.unmodifiable(_requests);
  }

  @override
  Future<void> resolveFriendRequest({
    required String requestId,
    required bool accepted,
  }) async {
    _ensureSeededRequests();
    final int index = _requests.indexWhere(
      (FriendRequest request) => request.id == requestId,
    );
    if (index < 0 || _requests[index].status != FriendRequestStatus.pending) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '好友请求状态已变化，请刷新后重试',
      );
    }
    final FriendRequest request = _requests[index];
    _requests[index] = request.copyWith(
      status: accepted
          ? FriendRequestStatus.accepted
          : FriendRequestStatus.rejected,
    );
    if (accepted) {
      final SocialUser user = _requireUser(request.user.userId);
      _users[user.userId] = user.copyWith(
        isFollowing: true,
        isFollower: true,
        isFriend: true,
      );
    }
  }

  @override
  Future<SocialPage<SocialUser>> fetchVisitors({
    required VisitorRecordType type,
    required int page,
    required int pageSize,
  }) async {
    final DateTime now = DateTime.now();
    final List<SocialUser> visitors = <SocialUser>[
      _users[20003]!.copyWith(
        visitedAt: now.subtract(const Duration(minutes: 28)),
        visitCount: 3,
      ),
      _users[20001]!.copyWith(
        visitedAt: now.subtract(const Duration(days: 1)),
        visitCount: 1,
      ),
      if (type == VisitorRecordType.viewedByMe)
        _users[20002]!.copyWith(
          visitedAt: now.subtract(const Duration(days: 2)),
          visitCount: 2,
        ),
    ];
    return _page(visitors, page: page, pageSize: pageSize);
  }

  @override
  Future<PrivacySettings> fetchPrivacySettings() async => _privacy;

  @override
  Future<PrivacySettings> updatePrivacySettings({
    required bool onlyFollowedCanFollow,
  }) async {
    _privacy = _privacy.copyWith(
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
    final List<SocialUser> blocked = _users.values
        .where((SocialUser user) => user.isBlocked)
        .toList(growable: false);
    return _page(blocked, page: page, pageSize: pageSize);
  }

  @override
  Future<void> setBlocked({
    required int userId,
    required bool blocked,
  }) async {
    final SocialUser user = _requireUser(userId);
    if (userId == 10001) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '不能拉黑自己',
      );
    }
    _users[userId] = user.copyWith(
      isBlocked: blocked,
      isFollowing: blocked ? false : user.isFollowing,
      isFriend: blocked ? false : user.isFriend,
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
    if (reasonCode < 1 || reasonCode > 5 || description.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择举报原因并填写必要说明',
      );
    }
    if (alsoBlock && targetType == ReportTargetType.user) {
      final int? userId = int.tryParse(targetId);
      if (userId != null) {
        await setBlocked(userId: userId, blocked: true);
      }
    }
    return 'report-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<SupportChannel> fetchCustomerService() async => const SupportChannel(
        id: 'customer-service',
        name: '平台客服',
        description: '当前可提交意见反馈；即时客服会话将在腾讯 IM 接入后开放。',
        liveConversationAvailable: false,
      );

  @override
  Future<SupportTicket> submitFeedback({
    required String subject,
    required String content,
  }) async {
    if (content.trim().isEmpty || content.trim().length > 200) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '反馈内容应为 1 至 200 个字符',
      );
    }
    final String id = 'ticket-${_ticketSequence++}';
    final SupportTicket ticket = SupportTicket(
      id: id,
      subject: subject.trim().isEmpty ? '意见反馈' : subject.trim(),
      content: content.trim(),
      status: SupportTicketStatus.submitted,
      statusText: '已提交，等待客服处理',
      createdAt: DateTime.now(),
      progressAvailable: true,
    );
    _tickets[id] = ticket;
    return ticket;
  }

  @override
  Future<SupportTicket> fetchSupportTicket(String ticketId) async {
    final SupportTicket? ticket = _tickets[ticketId];
    if (ticket == null) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '工单不存在或已不可查询',
      );
    }
    return ticket;
  }

  SocialUser _requireUser(int userId) {
    final SocialUser? user = _users[userId];
    if (user == null) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '用户不存在',
      );
    }
    return user;
  }

  static SocialPage<SocialUser> _page(
    List<SocialUser> items, {
    required int page,
    required int pageSize,
  }) {
    final int safePage = page < 1 ? 1 : page;
    final int safePageSize = pageSize < 1 ? 20 : pageSize;
    final int start = (safePage - 1) * safePageSize;
    final int end = (start + safePageSize).clamp(0, items.length).toInt();
    final List<SocialUser> slice = start >= items.length
        ? const <SocialUser>[]
        : items.sublist(start, end);
    return SocialPage<SocialUser>(
      items: slice,
      page: safePage,
      pageSize: safePageSize,
      total: items.length,
      hasMore: end < items.length,
    );
  }
}
