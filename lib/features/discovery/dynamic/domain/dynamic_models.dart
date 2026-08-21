enum DynamicCategory { all, companionship, music, chat }

extension DynamicCategoryLabel on DynamicCategory {
  String get label => switch (this) {
    DynamicCategory.all => '全部',
    DynamicCategory.companionship => '陪伴',
    DynamicCategory.music => '音乐',
    DynamicCategory.chat => '聊天',
  };

  String? get backendTag => switch (this) {
    DynamicCategory.all => null,
    DynamicCategory.companionship => '陪伴',
    DynamicCategory.music => '音乐',
    DynamicCategory.chat => '聊天',
  };
}

class DynamicAuthor {
  const DynamicAuthor({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.gender = 0,
  });

  final int userId;
  final String nickname;
  final String? avatarUrl;
  final int gender;
}

class DynamicPost {
  const DynamicPost({
    required this.id,
    required this.author,
    required this.content,
    required this.createdAt,
    this.images = const <String>[],
    this.location = '',
    this.tags = const <String>[],
    this.topics = const <String>[],
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
    this.isCollected = false,
    this.unlockChat = false,
  });

  final String id;
  final DynamicAuthor author;
  final String content;
  final List<String> images;
  final String location;
  final List<String> tags;
  final List<String> topics;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final bool isCollected;
  final bool unlockChat;
  final String createdAt;

  DynamicPost copyWith({
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    bool? isCollected,
  }) {
    return DynamicPost(
      id: id,
      author: author,
      content: content,
      images: images,
      location: location,
      tags: tags,
      topics: topics,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      isCollected: isCollected ?? this.isCollected,
      unlockChat: unlockChat,
      createdAt: createdAt,
    );
  }
}

class DynamicComment {
  const DynamicComment({
    required this.id,
    required this.dynamicId,
    required this.author,
    required this.content,
    required this.createdAt,
    this.replyToUserId,
    this.replyToNickname,
    this.replyToCommentId,
  });

  final String id;
  final String dynamicId;
  final DynamicAuthor author;
  final String content;
  final String createdAt;
  final int? replyToUserId;
  final String? replyToNickname;
  final String? replyToCommentId;
}

class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<T> items;
  final int page;
  final bool hasMore;
}

class PublishDynamicRequest {
  const PublishDynamicRequest({
    required this.content,
    required this.category,
    this.topics = const <String>[],
    this.location = '',
    this.images = const <String>[],
  });

  final String content;
  final DynamicCategory category;
  final List<String> topics;
  final String location;
  final List<String> images;
}

enum RankingBoard { charm, wealth, contribution, room }

extension RankingBoardLabel on RankingBoard {
  String get label => switch (this) {
    RankingBoard.charm => '魅力榜',
    RankingBoard.wealth => '财富榜',
    RankingBoard.contribution => '贡献榜',
    RankingBoard.room => '房间榜',
  };
}

enum RankingPeriod { day, week, month }

extension RankingPeriodValue on RankingPeriod {
  String get label => switch (this) {
    RankingPeriod.day => '日榜',
    RankingPeriod.week => '周榜',
    RankingPeriod.month => '月榜',
  };

  int get userBackendValue => switch (this) {
    RankingPeriod.day => 1,
    RankingPeriod.week => 2,
    RankingPeriod.month => 3,
  };

  int get roomBackendValue => switch (this) {
    RankingPeriod.day => 1,
    RankingPeriod.week => 2,
    RankingPeriod.month => 3,
  };
}

class RankingEntry {
  const RankingEntry({
    required this.rank,
    required this.name,
    required this.value,
    this.userId,
    this.roomId,
    this.avatarUrl,
    this.subtitle = '',
  });

  final int rank;
  final int? userId;
  final String? roomId;
  final String name;
  final String? avatarUrl;
  final num value;
  final String subtitle;
}

class RankingSnapshot {
  const RankingSnapshot({
    required this.board,
    required this.period,
    required this.entries,
    this.countdownSeconds = 0,
    this.selfEntry,
  });

  final RankingBoard board;
  final RankingPeriod period;
  final List<RankingEntry> entries;
  final int countdownSeconds;
  final RankingEntry? selfEntry;
}
