enum SocialRelationList { following, followers, friends }

enum FriendRequestStatus { pending, accepted, rejected, expired }

enum VisitorRecordType { viewedMe, viewedByMe }

enum ReportTargetType { user, room }

enum SupportTicketStatus { submitted, processing, resolved, rejected, unavailable }

class SocialUser {
  const SocialUser({
    required this.userId,
    required this.name,
    required this.signature,
    required this.avatarUrl,
    required this.isFollowing,
    required this.isFollower,
    required this.isFriend,
    required this.isBlocked,
    required this.isOnline,
    this.roomId,
    this.visitedAt,
    this.visitCount = 0,
  });

  final int userId;
  final String name;
  final String signature;
  final String avatarUrl;
  final bool isFollowing;
  final bool isFollower;
  final bool isFriend;
  final bool isBlocked;
  final bool isOnline;
  final String? roomId;
  final DateTime? visitedAt;
  final int visitCount;

  SocialUser copyWith({
    String? name,
    String? signature,
    String? avatarUrl,
    bool? isFollowing,
    bool? isFollower,
    bool? isFriend,
    bool? isBlocked,
    bool? isOnline,
    String? roomId,
    bool clearRoomId = false,
    DateTime? visitedAt,
    int? visitCount,
  }) {
    return SocialUser(
      userId: userId,
      name: name ?? this.name,
      signature: signature ?? this.signature,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isFollowing: isFollowing ?? this.isFollowing,
      isFollower: isFollower ?? this.isFollower,
      isFriend: isFriend ?? this.isFriend,
      isBlocked: isBlocked ?? this.isBlocked,
      isOnline: isOnline ?? this.isOnline,
      roomId: clearRoomId ? null : roomId ?? this.roomId,
      visitedAt: visitedAt ?? this.visitedAt,
      visitCount: visitCount ?? this.visitCount,
    );
  }
}

class SocialProfile {
  const SocialProfile({
    required this.user,
    required this.account,
    required this.sex,
    required this.birthday,
    required this.city,
    required this.coverUrl,
    required this.followingCount,
    required this.followerCount,
    required this.friendCount,
    required this.postCount,
    required this.level,
  });

  final SocialUser user;
  final String account;
  final int sex;
  final String birthday;
  final String city;
  final String coverUrl;
  final int followingCount;
  final int followerCount;
  final int friendCount;
  final int postCount;
  final int level;

  SocialProfile copyWith({
    SocialUser? user,
    int? sex,
    String? birthday,
    String? city,
    String? coverUrl,
    int? followingCount,
    int? followerCount,
    int? friendCount,
    int? postCount,
    int? level,
  }) {
    return SocialProfile(
      user: user ?? this.user,
      account: account,
      sex: sex ?? this.sex,
      birthday: birthday ?? this.birthday,
      city: city ?? this.city,
      coverUrl: coverUrl ?? this.coverUrl,
      followingCount: followingCount ?? this.followingCount,
      followerCount: followerCount ?? this.followerCount,
      friendCount: friendCount ?? this.friendCount,
      postCount: postCount ?? this.postCount,
      level: level ?? this.level,
    );
  }
}

class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.user,
    required this.message,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final SocialUser user;
  final String message;
  final DateTime createdAt;
  final FriendRequestStatus status;

  FriendRequest copyWith({FriendRequestStatus? status}) {
    return FriendRequest(
      id: id,
      user: user,
      message: message,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }
}

class PrivacySettings {
  const PrivacySettings({
    required this.onlyFollowedCanFollow,
    required this.serverValueKnown,
  });

  final bool onlyFollowedCanFollow;
  final bool serverValueKnown;

  PrivacySettings copyWith({
    bool? onlyFollowedCanFollow,
    bool? serverValueKnown,
  }) {
    return PrivacySettings(
      onlyFollowedCanFollow:
          onlyFollowedCanFollow ?? this.onlyFollowedCanFollow,
      serverValueKnown: serverValueKnown ?? this.serverValueKnown,
    );
  }
}

class SupportChannel {
  const SupportChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.liveConversationAvailable,
  });

  final String id;
  final String name;
  final String description;
  final bool liveConversationAvailable;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.content,
    required this.status,
    required this.statusText,
    required this.createdAt,
    required this.progressAvailable,
  });

  final String id;
  final String subject;
  final String content;
  final SupportTicketStatus status;
  final String statusText;
  final DateTime createdAt;
  final bool progressAvailable;
}

class SocialPage<T> {
  const SocialPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.hasMore,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;
}

abstract interface class SocialRepository {
  bool get supportsFriendRequestWorkflow;
  bool get supportsTicketProgress;

  Future<SocialProfile> fetchMyProfile();

  Future<SocialProfile> updateMyProfile({
    required String nickname,
    required String signature,
    required int sex,
    required String birthday,
    required String city,
  });

  Future<SocialProfile> fetchPublicProfile(int userId);

  Future<SocialPage<SocialUser>> fetchRelations({
    required SocialRelationList type,
    required int page,
    required int pageSize,
  });

  Future<void> setFollowing({
    required int userId,
    required bool following,
  });

  Future<List<FriendRequest>> fetchFriendRequests();

  Future<void> resolveFriendRequest({
    required String requestId,
    required bool accepted,
  });

  Future<SocialPage<SocialUser>> fetchVisitors({
    required VisitorRecordType type,
    required int page,
    required int pageSize,
  });

  Future<PrivacySettings> fetchPrivacySettings();

  Future<PrivacySettings> updatePrivacySettings({
    required bool onlyFollowedCanFollow,
  });

  Future<SocialPage<SocialUser>> fetchBlacklist({
    required int page,
    required int pageSize,
  });

  Future<void> setBlocked({
    required int userId,
    required bool blocked,
  });

  Future<String> submitReport({
    required ReportTargetType targetType,
    required String targetId,
    required int reasonCode,
    required String description,
    required bool alsoBlock,
  });

  Future<SupportChannel> fetchCustomerService();

  Future<SupportTicket> submitFeedback({
    required String subject,
    required String content,
  });

  Future<SupportTicket> fetchSupportTicket(String ticketId);
}
