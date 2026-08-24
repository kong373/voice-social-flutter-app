enum SearchEntityType {
  all(0),
  users(2),
  rooms(1);

  const SearchEntityType(this.backendCode);

  final int backendCode;
}

enum DiscoverySuggestionSource { roomHotTitle, roomHotTopic, curatedSeed }

class DiscoverySearchSuggestion {
  const DiscoverySearchSuggestion({
    required this.keyword,
    required this.source,
  });

  final String keyword;
  final DiscoverySuggestionSource source;
}

/// Formats a server-authoritative online count without treating unavailable
/// data as zero.
String discoveryOnlineCountLabel(int? onlineCount, {String suffix = '人在线'}) {
  if (onlineCount == null || onlineCount < 0) {
    return '在线人数未知';
  }
  return '$onlineCount $suffix';
}

class DiscoveryRoom {
  const DiscoveryRoom({
    required this.id,
    required this.code,
    required this.title,
    required this.topic,
    this.onlineCount,
    required this.occupiedSeats,
    required this.isSpeaking,
    required this.isFavorite,
    this.ownerUserId,
    this.ownerName,
    this.coverUrl,
    this.relationReason,
    this.isLocked = false,
  });

  final String id;
  final String code;
  final String title;
  final String topic;

  /// The last server-authoritative online count, when the snapshot includes
  /// one. A missing or malformed live field is intentionally represented as
  /// `null` instead of being mistaken for zero.
  final int? onlineCount;
  final int occupiedSeats;
  final bool isSpeaking;
  final bool isFavorite;
  final int? ownerUserId;
  final String? ownerName;
  final String? coverUrl;
  final String? relationReason;
  final bool isLocked;

  DiscoveryRoom copyWith({
    String? title,
    String? topic,
    int? onlineCount,
    int? occupiedSeats,
    bool? isSpeaking,
    bool? isFavorite,
    String? relationReason,
    bool? isLocked,
  }) {
    return DiscoveryRoom(
      id: id,
      code: code,
      title: title ?? this.title,
      topic: topic ?? this.topic,
      onlineCount: onlineCount ?? this.onlineCount,
      occupiedSeats: occupiedSeats ?? this.occupiedSeats,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isFavorite: isFavorite ?? this.isFavorite,
      ownerUserId: ownerUserId,
      ownerName: ownerName,
      coverUrl: coverUrl,
      relationReason: relationReason ?? this.relationReason,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

class DiscoveryUser {
  const DiscoveryUser({
    required this.userId,
    required this.name,
    required this.loginName,
    this.avatarUrl,
    this.bio,
    this.currentRoomId,
    this.currentRoomTitle,
  });

  final int userId;
  final String name;
  final String loginName;
  final String? avatarUrl;
  final String? bio;
  final String? currentRoomId;
  final String? currentRoomTitle;

  bool get isInRoom => currentRoomId != null && currentRoomId!.isNotEmpty;
}

class DiscoverySearchResult {
  const DiscoverySearchResult({
    required this.rooms,
    required this.users,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  final List<DiscoveryRoom> rooms;
  final List<DiscoveryUser> users;
  final int page;
  final int pageSize;
  final bool hasMore;
}

class RoomCollectionSnapshot {
  const RoomCollectionSnapshot({
    required this.favorites,
    required this.ownedRooms,
  });

  final List<DiscoveryRoom> favorites;
  final List<DiscoveryRoom> ownedRooms;
}
