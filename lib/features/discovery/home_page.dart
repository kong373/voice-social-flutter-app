import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/replica_components.dart';
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
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          key: const Key('apk-replica-home'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              sliver: SliverToBoxAdapter(child: _buildHeader(context)),
            ),
            SliverToBoxAdapter(child: _buildCategories()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              sliver: SliverToBoxAdapter(child: _buildShortcuts()),
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
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: ReplicaSectionTitle(
                    title: '此刻适合你的房间',
                    subtitle: '根据实时活跃度与关系推荐',
                    trailing: ReplicaPill(
                      label: '换一批',
                      icon: Icons.refresh_rounded,
                      compact: true,
                      onTap: rooms.length <= 1
                          ? null
                          : () => setState(
                                () => _rotation =
                                    (_rotation + 1) % rooms.length,
                              ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: _HeroRoomCard(
                    room: rooms.first,
                    onEnter: () => _enterRoom(rooms.first),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 26, 18, 12),
                sliver: const SliverToBoxAdapter(
                  child: ReplicaSectionTitle(
                    title: '正在发生',
                    subtitle: '点击卡片可直接进入语音房',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                sliver: SliverList.separated(
                  itemCount: rooms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) =>
                      _LiveRoomCard(
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(13),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
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
        ReplicaPanel(
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
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) => ReplicaPill(
          label: _categories[index],
          active: index == _categoryIndex,
          compact: true,
          onTap: () => setState(() => _categoryIndex = index),
        ),
      ),
    );
  }

  Widget _buildShortcuts() {
    return ReplicaPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ReplicaIconTile(
              icon: Icons.bookmark_added_outlined,
              label: '收藏与房间',
              accent: AppColors.secondary,
              onTap: _openSavedRooms,
            ),
          ),
          Expanded(
            child: ReplicaIconTile(
              icon: Icons.add_home_work_outlined,
              label: '创建房间',
              accent: AppColors.primaryBright,
              onTap: _openCreateRoom,
            ),
          ),
          Expanded(
            child: ReplicaIconTile(
              icon: Icons.search_rounded,
              label: '全局搜索',
              accent: AppColors.accent,
              onTap: _openSearch,
            ),
          ),
        ],
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const GlobalSearchPage(),
      ),
    );
  }

  void _openCreateRoom() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const CreateRoomPage(),
      ),
    );
  }

  void _openSavedRooms() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SavedRoomsPage(),
      ),
    );
  }

  void _enterRoom(DiscoveryRoom room) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomPage(
          roomId: room.id,
          title: room.title,
          entrySource: RoomEntrySource.home,
        ),
      ),
    );
  }
}

class _HeroRoomCard extends StatelessWidget {
  const _HeroRoomCard({required this.room, required this.onEnter});

  final DiscoveryRoom room;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    return ReplicaPanel(
      padding: EdgeInsets.zero,
      borderColor: AppColors.primary.withValues(alpha: 0.25),
      onTap: onEnter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ReplicaRoomArtwork(
            seed: room.id,
            height: 170,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      ReplicaPill(
                        label: room.isSpeaking ? '正在热聊' : '正在收听',
                        icon: room.isSpeaking
                            ? Icons.graphic_eq_rounded
                            : Icons.headphones_rounded,
                        active: true,
                        compact: true,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (room.isLocked) ...<Widget>[
                              const Icon(Icons.lock_rounded, size: 14),
                              const SizedBox(width: 5),
                            ],
                            const Icon(Icons.people_alt_rounded, size: 15),
                            const SizedBox(width: 5),
                            Text('${room.onlineCount}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 10),
                          ],
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    room.topic,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 8),
                          ],
                        ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
            child: Column(
              children: <Widget>[
                Row(
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
                    FilledButton(
                      onPressed: onEnter,
                      child: const Text('进入'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SeatProgress(occupiedSeats: room.occupiedSeats),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveRoomCard extends StatelessWidget {
  const _LiveRoomCard({
    required this.room,
    required this.index,
    required this.onTap,
  });

  final DiscoveryRoom room;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ReplicaPanel(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 92,
            child: ReplicaRoomArtwork(
              seed: '${room.id}-$index',
              height: 92,
              borderRadius: BorderRadius.circular(17),
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: room.isSpeaking
                      ? const ReplicaWaveform(width: 36, height: 15)
                      : const Icon(Icons.headphones_rounded, size: 18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (room.isLocked)
                      const Icon(Icons.lock_outline_rounded, size: 16),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  room.topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    _AvatarStack(seed: room.id, count: room.occupiedSeats, small: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${room.occupiedSeats}/8 麦 · ${room.onlineCount} 人在线',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
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
    final double size = small ? 23 : 29;
    return SizedBox(
      width: size + (shown - 1) * size * 0.62,
      height: size,
      child: Stack(
        children: <Widget>[
          for (int index = 0; index < shown; index += 1)
            Positioned(
              left: index * size * 0.62,
              child: ReplicaAvatar(
                seed: '$seed-$index',
                size: size,
                ringColor: AppColors.surface,
              ),
            ),
        ],
      ),
    );
  }
}

class _SeatProgress extends StatelessWidget {
  const _SeatProgress({required this.occupiedSeats});

  final int occupiedSeats;

  @override
  Widget build(BuildContext context) {
    final int safeOccupied = occupiedSeats.clamp(0, 8);
    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (int index = 0; index < 8; index += 1)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: index < safeOccupied
                        ? const LinearGradient(
                            colors: <Color>[
                              AppColors.primary,
                              AppColors.secondary,
                            ],
                          )
                        : null,
                    color: index < safeOccupied
                        ? null
                        : Colors.white.withValues(alpha: 0.055),
                    border: Border.all(
                      color: index < safeOccupied
                          ? Colors.white.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                  child: Icon(
                    index < safeOccupied
                        ? Icons.person_rounded
                        : Icons.add_rounded,
                    size: 13,
                    color: index < safeOccupied
                        ? Colors.white
                        : AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text('$safeOccupied/8 麦'),
      ],
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
        child: ReplicaPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
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
      ),
    );
  }
}
