import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/video_ui_components.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';
import 'package:voice_social_app/features/discovery/presentation/saved_rooms_page.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/create_room_page.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const List<String> _categories = <String>[
    '推荐',
    '陪伴',
    '轻聊',
    '情感',
    '电台',
    '交友',
  ];

  DiscoveryRepository? _repositoryInstance;
  DiscoveryRepository get _repository => _repositoryInstance!;
  final List<DiscoveryRoom> _rooms = <DiscoveryRoom>[];
  int _rotation = 0;
  int _categoryIndex = 0;
  bool _loading = true;
  String? _error;

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
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final List<DiscoveryRoom> rooms = await _repository.fetchHomeRooms();
      if (!mounted) {
        return;
      }
      setState(() {
        _rooms
          ..clear()
          ..addAll(rooms);
        _rotation = 0;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '房间推荐暂时无法加载，请稍后重试';
      });
    }
  }

  List<DiscoveryRoom> get _rotatedRooms {
    if (_rooms.isEmpty) {
      return <DiscoveryRoom>[];
    }
    return <DiscoveryRoom>[
      for (int index = 0; index < _rooms.length; index += 1)
        _rooms[(index + _rotation) % _rooms.length],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final List<DiscoveryRoom> rooms = _rotatedRooms;
    return LobbyTheme(
      child: LobbyBackdrop(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              key: const Key('video-runtime-home'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  sliver: SliverToBoxAdapter(child: _buildHeader()),
                ),
                SliverToBoxAdapter(child: _buildCategories()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  sliver: SliverToBoxAdapter(child: _buildFeatureMosaic()),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _HomeState(
                      icon: Icons.cloud_off_rounded,
                      title: '房间推荐加载失败',
                      description: _error!,
                      actionLabel: '重新加载',
                      onAction: _load,
                    ),
                  )
                else if (rooms.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _HomeState(
                      icon: Icons.meeting_room_outlined,
                      title: '暂时没有可推荐房间',
                      description: '可以创建自己的房间，或稍后下拉刷新。',
                      actionLabel: '创建房间',
                      onAction: _openCreateRoom,
                    ),
                  )
                else ...<Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '此刻适合你的房间',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '实时活跃、关系和话题共同推荐',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          LobbyPill(
                            label: '换一批',
                            icon: Icons.refresh_rounded,
                            onTap: rooms.length <= 1
                                ? null
                                : () => setState(
                                      () => _rotation =
                                          (_rotation + 1) % rooms.length,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverToBoxAdapter(
                      child: _FeaturedRoomCard(
                        room: rooms.first,
                        onTap: () => _enterRoom(rooms.first),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 25, 18, 12),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: <Widget>[
                          Text(
                            '正在发生',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          Text(
                            '点击直接进房',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                    sliver: SliverGrid.builder(
                      itemCount: rooms.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.82,
                          ),
                      itemBuilder: (BuildContext context, int index) =>
                          _RoomPosterCard(
                        room: rooms[index],
                        index: index,
                        onTap: () => _enterRoom(rooms[index]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('正在发生', style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    '听见有趣的人，也让别人听见你',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '创建房间',
              onPressed: _openCreateRoom,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 15),
        LobbyCard(
          padding: EdgeInsets.zero,
          radius: 18,
          onTap: _openSearch,
          child: const IgnorePointer(
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索房间、用户或房间号',
                prefixIcon: Icon(Icons.search_rounded),
                suffixIcon: Icon(Icons.tune_rounded),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategories() {
    return SizedBox(
      height: 55,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) => LobbyPill(
          label: _categories[index],
          active: _categoryIndex == index,
          onTap: () => setState(() => _categoryIndex = index),
        ),
      ),
    );
  }

  Widget _buildFeatureMosaic() {
    return SizedBox(
      height: 166,
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 7,
            child: LobbyCard(
              padding: EdgeInsets.zero,
              onTap: _openSavedRooms,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF8FA8FF), Color(0xFFB39BFF)],
              ),
              child: Stack(
                children: <Widget>[
                  const Positioned(
                    right: -12,
                    bottom: -12,
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 108,
                      color: Color(0x33FFFFFF),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.bookmark_added_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '收藏与我的房间',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '快速回到熟悉的人群',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: LobbyCard(
                    padding: const EdgeInsets.all(13),
                    onTap: _openCreateRoom,
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFFFFB8D5), Color(0xFFF2C5FF)],
                    ),
                    child: _MosaicAction(
                      icon: Icons.add_home_work_rounded,
                      title: '创建房间',
                      subtitle: '发起此刻的话题',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: LobbyCard(
                    padding: const EdgeInsets.all(13),
                    onTap: _openSearch,
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFFA9E9FF), Color(0xFFBFD1FF)],
                    ),
                    child: _MosaicAction(
                      icon: Icons.person_search_rounded,
                      title: '找人找房',
                      subtitle: '昵称、ID、房间号',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const GlobalSearchPage()),
    );
  }

  void _openCreateRoom() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CreateRoomPage()),
    );
  }

  void _openSavedRooms() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SavedRoomsPage()),
    );
  }

  void _enterRoom(DiscoveryRoom room) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RoomPage(
          roomId: room.id,
          title: room.title,
          entrySource: RoomEntrySource.home,
        ),
      ),
    );
  }
}

class _MosaicAction extends StatelessWidget {
  const _MosaicAction({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.64),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeaturedRoomCard extends StatelessWidget {
  const _FeaturedRoomCard({required this.room, required this.onTap});

  final DiscoveryRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LobbyCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RoomArtwork(
            seed: room.id,
            height: 175,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.26),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            VoiceWave(active: room.isSpeaking, width: 30),
                            const SizedBox(width: 7),
                            Text(
                              room.isSpeaking ? '正在热聊' : '正在收听',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _OnlineBadge(room: room),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black38, blurRadius: 8),
                          ],
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    room.topic,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 14, 15),
            child: Row(
              children: <Widget>[
                _AvatarStack(seed: room.id, count: room.occupiedSeats),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    room.relationReason ?? '根据当前活跃度推荐',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: onTap, child: const Text('进入')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomPosterCard extends StatelessWidget {
  const _RoomPosterCard({
    required this.room,
    required this.index,
    required this.onTap,
  });

  final DiscoveryRoom room;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LobbyCard(
      padding: EdgeInsets.zero,
      radius: 20,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: RoomArtwork(
              seed: '${room.id}-$index',
              height: double.infinity,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(19),
              ),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Align(
                  alignment: Alignment.topRight,
                  child: _OnlineBadge(room: room),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  room.topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 7),
                Row(
                  children: <Widget>[
                    _AvatarStack(
                      seed: room.id,
                      count: room.occupiedSeats,
                      small: true,
                    ),
                    const Spacer(),
                    VoiceWave(active: room.isSpeaking, width: 30),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge({required this.room});

  final DiscoveryRoom room;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (room.isLocked) ...<Widget>[
            const Icon(Icons.lock_rounded, size: 13, color: Colors.white),
            const SizedBox(width: 4),
          ],
          const Icon(Icons.people_alt_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '${room.onlineCount}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({
    required this.seed,
    required this.count,
    this.small = false,
  });

  final String seed;
  final int count;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final int shown = count.clamp(1, 4);
    final double size = small ? 22 : 29;
    return SizedBox(
      width: size + (shown - 1) * size * 0.58,
      height: size,
      child: Stack(
        children: <Widget>[
          for (int index = 0; index < shown; index += 1)
            Positioned(
              left: index * size * 0.58,
              child: ColorAvatar(seed: '$seed-$index', size: size),
            ),
        ],
      ),
    );
  }
}

class _HomeState extends StatelessWidget {
  const _HomeState({
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
        child: LobbyCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 46, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
