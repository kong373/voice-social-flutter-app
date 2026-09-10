import '../../../../core/media/media_models.dart';

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
    this.media = const <MediaReference>[],
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
  final List<MediaReference> media;
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
      media: media,
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
    this.status = 'PUBLISHED',
    this.canDelete = false,
    this.canReply = false,
    this.parentCommentStatus = 'NONE',
    this.parentCommentPlaceholder = '',
  });

  final String id;
  final String dynamicId;
  final DynamicAuthor author;
  final String content;
  final String createdAt;
  final int? replyToUserId;
  final String? replyToNickname;
  final String? replyToCommentId;
  final String status;
  final bool canDelete;
  final bool canReply;
  final String parentCommentStatus;
  final String parentCommentPlaceholder;
  bool get deleted => status == 'DELETED';
  bool get parentCommentUnavailable =>
      !const ['NONE', 'PUBLISHED'].contains(parentCommentStatus);
}

class CommentDeletion {
  const CommentDeletion(this.dynamicId, this.commentId, this.commentCount);
  final String dynamicId;
  final String commentId;
  final int commentCount;
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
    this.media = const <MediaReference>[],
  });

  final String content;
  final DynamicCategory category;
  final List<String> topics;
  final String location;
  final List<String> images;
  final List<MediaReference> media;
}

enum RankingBoard { charm, wealth, contribution, room }

// Retain the legacy enum only to reject old callers and decode historical data.
// It is not a current product tab or a fetchable ranking.
const productRankingBoards = <RankingBoard>[
  RankingBoard.charm,
  RankingBoard.wealth,
  RankingBoard.room,
];

extension RankingBoardLabel on RankingBoard {
  bool get isGiftValue => this != RankingBoard.contribution;
  String get metric =>
      this == RankingBoard.room ? 'ROOM_CONTRIBUTION' : name.toUpperCase();
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

  String get backendValue => name.toUpperCase();
}

class RankingEntry {
  const RankingEntry({
    required this.rank,
    required this.name,
    this.value,
    this.giftValueFen,
    this.firstReachedAt,
    this.firstReachedTransferId,
    this.isCurrentUser = false,
    this.userId,
    this.roomId,
    this.avatarUrl,
    this.subtitle = '',
  }) : assert((value == null) != (giftValueFen == null));

  final int rank;
  final int? userId;
  final String? roomId;
  final String name;
  final String? avatarUrl;

  /// Legacy contribution only. Gift rankings never pass through num/double.
  final num? value;
  final BigInt? giftValueFen;
  final DateTime? firstReachedAt;
  final String? firstReachedTransferId;
  final bool isCurrentUser;
  final String subtitle;

  String get displayValue {
    final fen = giftValueFen;
    if (fen == null) return value.toString();
    final hundred = BigInt.from(100);
    return '${fen ~/ hundred}.${(fen % hundred).toString().padLeft(2, '0')} 元';
  }
}

class RankingSnapshot {
  const RankingSnapshot({
    required this.board,
    required this.period,
    required this.entries,
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.pages = 0,
    this.startInclusive,
    this.endExclusive,
    this.serverNow,
    this.excludedUnvaluedTransfers = 0,
    this.serverAuthoritative = false,
    this.selfEntry,
  });

  final RankingBoard board;

  /// Contribution is cumulative and has no period.
  final RankingPeriod? period;
  final List<RankingEntry> entries;
  final int page;
  final int pageSize;
  final int total;
  final int pages;
  final DateTime? startInclusive;
  final DateTime? endExclusive;
  final DateTime? serverNow;
  final int excludedUnvaluedTransfers;
  final bool serverAuthoritative;
  bool get hasMore => page < pages;
  final RankingEntry? selfEntry;
}
