import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';

class MockDiscoveryRepository implements DiscoveryRepository {
  MockDiscoveryRepository();

  final List<DiscoveryRoom> _rooms = <DiscoveryRoom>[
    const DiscoveryRoom(
      id: '880217',
      code: '880217',
      title: '深夜温柔陪伴',
      topic: '最近让你觉得被治愈的一件小事',
      onlineCount: 36,
      occupiedSeats: 3,
      isSpeaking: true,
      isFavorite: true,
      ownerUserId: 20001,
      ownerName: '鹿屿',
      relationReason: '你关注的晚星正在房间里',
    ),
    const DiscoveryRoom(
      id: '660318',
      code: '660318',
      title: '下班后的松弛时刻',
      topic: '聊聊今天最想放下的一件事',
      onlineCount: 24,
      occupiedSeats: 5,
      isSpeaking: true,
      isFavorite: false,
      ownerUserId: 20008,
      ownerName: '远山',
      relationReason: '与你常听的陪伴主题相似',
    ),
    const DiscoveryRoom(
      id: '520906',
      code: '520906',
      title: '安静音乐电台',
      topic: '轻音乐与自由聊天，让夜晚慢下来',
      onlineCount: 18,
      occupiedSeats: 2,
      isSpeaking: false,
      isFavorite: true,
      ownerUserId: 20012,
      ownerName: '南枝',
      relationReason: '2 位好友正在收听',
    ),
    const DiscoveryRoom(
      id: '952700',
      code: '952700',
      title: '周末松弛聊天局',
      topic: '不赶时间，慢慢认识新朋友',
      onlineCount: 12,
      occupiedSeats: 4,
      isSpeaking: true,
      isFavorite: false,
      ownerUserId: 10001,
      ownerName: '我',
      relationReason: '你创建的房间',
    ),
    const DiscoveryRoom(
      id: '310824',
      code: '310824',
      title: '新歌分享与闲聊',
      topic: '轻音乐分享与自由聊天，让夜晚慢下来',
      onlineCount: 9,
      occupiedSeats: 1,
      isSpeaking: false,
      isFavorite: false,
      ownerUserId: 20018,
      ownerName: '初晴',
      isLocked: true,
      relationReason: '普通音乐主题房',
    ),
  ];

  final List<DiscoveryUser> _users = <DiscoveryUser>[
    const DiscoveryUser(
      userId: 20001,
      name: '鹿屿',
      loginName: '20001',
      bio: '晚间陪伴房主，认真听每一次表达。',
      currentRoomId: '880217',
      currentRoomTitle: '深夜温柔陪伴',
    ),
    const DiscoveryUser(
      userId: 20002,
      name: '南风',
      loginName: '20002',
      bio: '喜欢城市散步和轻松聊天。',
      currentRoomId: '880217',
      currentRoomTitle: '深夜温柔陪伴',
    ),
    const DiscoveryUser(
      userId: 20003,
      name: '晚星',
      loginName: '20003',
      bio: '常驻陪伴主题房。',
      currentRoomId: '880217',
      currentRoomTitle: '深夜温柔陪伴',
    ),
    const DiscoveryUser(
      userId: 20008,
      name: '远山',
      loginName: '20008',
      bio: '下班后一起放松。',
      currentRoomId: '660318',
      currentRoomTitle: '下班后的松弛时刻',
    ),
    const DiscoveryUser(
      userId: 20012,
      name: '南枝',
      loginName: '20012',
      bio: '轻音乐与夜间电台。',
    ),
  ];

  @override
  Future<List<DiscoveryRoom>> fetchHomeRooms({
    int page = 1,
    int pageSize = 20,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return _slice(_rooms, page: page, pageSize: pageSize);
  }

  @override
  Future<DiscoverySearchResult> search({
    required String keyword,
    required SearchEntityType type,
    int page = 1,
    int pageSize = 20,
  }) async {
    final String normalized = keyword.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请输入房间、用户或房间号',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final List<DiscoveryRoom> matchingRooms = type == SearchEntityType.users
        ? <DiscoveryRoom>[]
        : _rooms
              .where(
                (DiscoveryRoom room) =>
                    room.title.toLowerCase().contains(normalized) ||
                    room.topic.toLowerCase().contains(normalized) ||
                    room.code.toLowerCase().contains(normalized),
              )
              .toList(growable: false);
    final List<DiscoveryUser> matchingUsers = type == SearchEntityType.rooms
        ? <DiscoveryUser>[]
        : _users
              .where(
                (DiscoveryUser user) =>
                    user.name.toLowerCase().contains(normalized) ||
                    user.loginName.toLowerCase().contains(normalized) ||
                    (user.bio ?? '').toLowerCase().contains(normalized),
              )
              .toList(growable: false);
    final List<DiscoveryRoom> rooms = _slice(
      matchingRooms,
      page: page,
      pageSize: pageSize,
    );
    final List<DiscoveryUser> users = _slice(
      matchingUsers,
      page: page,
      pageSize: pageSize,
    );
    final int total = matchingRooms.length + matchingUsers.length;
    return DiscoverySearchResult(
      rooms: rooms,
      users: users,
      page: page,
      pageSize: pageSize,
      hasMore: page * pageSize < total,
    );
  }

  @override
  Future<RoomCollectionSnapshot> fetchRoomCollections({
    int page = 1,
    int pageSize = 30,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final List<DiscoveryRoom> favorites = _rooms
        .where((DiscoveryRoom room) => room.isFavorite)
        .toList(growable: false);
    final List<DiscoveryRoom> ownedRooms = _rooms
        .where((DiscoveryRoom room) => room.ownerUserId == 10001)
        .toList(growable: false);
    return RoomCollectionSnapshot(
      favorites: _slice(favorites, page: page, pageSize: pageSize),
      ownedRooms: _slice(ownedRooms, page: page, pageSize: pageSize),
    );
  }

  @override
  Future<bool> setFavorite({
    required String roomId,
    required bool favorite,
  }) async {
    final int index = _rooms.indexWhere(
      (DiscoveryRoom room) => room.id == roomId,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '房间已失效或不存在',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _rooms[index] = _rooms[index].copyWith(isFavorite: favorite);
    return favorite;
  }

  static List<T> _slice<T>(
    List<T> source, {
    required int page,
    required int pageSize,
  }) {
    if (page <= 0 || pageSize <= 0) {
      return <T>[];
    }
    final int start = (page - 1) * pageSize;
    if (start >= source.length) {
      return <T>[];
    }
    final int end = start + pageSize > source.length
        ? source.length
        : start + pageSize;
    return source.sublist(start, end);
  }
}
