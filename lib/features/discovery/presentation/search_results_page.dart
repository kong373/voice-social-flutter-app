import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

class SearchResultsPage extends StatefulWidget {
  const SearchResultsPage({
    required this.keyword,
    this.initialType = SearchEntityType.all,
    super.key,
  });

  final String keyword;
  final SearchEntityType initialType;

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  DiscoveryRepository? _repositoryInstance;
  DiscoveryRepository get _repository => _repositoryInstance!;
  late SearchEntityType _type;
  DiscoverySearchResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance = AppDependencyScope.of(context).discoveryRepository;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final DiscoverySearchResult result = await _repository.search(
        keyword: widget.keyword,
        type: _type,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: Text('“${widget.keyword}”的搜索结果')),
      body: Column(
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: <Widget>[
                for (final SearchEntityType type
                    in SearchEntityType.values) ...<Widget>[
                  SocialPill(
                    label: switch (type) {
                      SearchEntityType.all => '全部',
                      SearchEntityType.rooms => '房间',
                      SearchEntityType.users => '用户',
                    },
                    active: _type == type,
                    onTap: () {
                      if (_type == type) return;
                      setState(() => _type = type);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _SearchState(
        icon: Icons.cloud_off_rounded,
        title: '搜索失败',
        description: _error!,
        actionLabel: '重新搜索',
        onAction: _load,
      );
    }
    final DiscoverySearchResult result =
        _result ??
        const DiscoverySearchResult(
          rooms: <DiscoveryRoom>[],
          users: <DiscoveryUser>[],
          page: 1,
          pageSize: 20,
          hasMore: false,
        );
    if (result.rooms.isEmpty && result.users.isEmpty) {
      return _SearchState(
        icon: Icons.search_off_rounded,
        title: '没有找到匹配内容',
        description: '可以尝试完整房间号、用户昵称，或减少关键词。',
        actionLabel: '返回修改关键词',
        onAction: () => Navigator.of(context).pop(),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: <Widget>[
          if (result.rooms.isNotEmpty) ...<Widget>[
            _SectionHeader(title: '房间', count: result.rooms.length),
            for (final DiscoveryRoom room in result.rooms)
              _RoomResultTile(room: room, onTap: () => _openRoom(room)),
          ],
          if (result.users.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            _SectionHeader(title: '用户', count: result.users.length),
            for (final DiscoveryUser user in result.users)
              _UserResultTile(
                user: user,
                onOpenProfile: () => _openProfile(user),
                onEnterRoom: user.isInRoom ? () => _openUserRoom(user) : null,
              ),
          ],
        ],
      ),
    );
  }

  void _openRoom(DiscoveryRoom room) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomPage(
          roomId: room.id,
          title: room.title,
          entrySource: RoomEntrySource.search,
        ),
      ),
    );
  }

  void _openUserRoom(DiscoveryUser user) {
    final String? roomId = user.currentRoomId;
    if (roomId == null) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomPage(
          roomId: roomId,
          title: user.currentRoomTitle ?? '语音房',
          entrySource: RoomEntrySource.search,
        ),
      ),
    );
  }

  void _openProfile(DiscoveryUser user) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            PublicProfilePage(userId: user.userId),
      ),
    );
  }

  static String _messageFor(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return '搜索服务暂时不可用，请稍后重试';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Row(
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('$count', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RoomResultTile extends StatelessWidget {
  const _RoomResultTile({required this.room, required this.onTap});

  final DiscoveryRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: OriginalRoomArtwork(
          seed: room.id,
          height: 116,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            room.isSpeaking
                                ? Icons.graphic_eq_rounded
                                : Icons.headphones_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${room.onlineCount} 人在线',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (room.isLocked)
                      const Icon(
                        Icons.lock_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        room.topic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xDDFFFFFF),
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${room.occupiedSeats}/8 麦',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserResultTile extends StatelessWidget {
  const _UserResultTile({
    required this.user,
    required this.onOpenProfile,
    required this.onEnterRoom,
  });

  final DiscoveryUser user;
  final VoidCallback onOpenProfile;
  final VoidCallback? onEnterRoom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SocialCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 18,
        onTap: onOpenProfile,
        child: Row(
          children: <Widget>[
            RuntimeAvatar(seed: '${user.userId}', size: 44),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    user.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.isInRoom
                        ? '正在 ${user.currentRoomTitle ?? '语音房'}'
                        : '用户号 ${user.loginName} · 当前离线',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onEnterRoom != null)
              SocialPill(
                label: '进房',
                active: true,
                icon: Icons.graphic_eq_rounded,
                onTap: onEnterRoom,
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: SocialColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchState extends StatelessWidget {
  const _SearchState({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
