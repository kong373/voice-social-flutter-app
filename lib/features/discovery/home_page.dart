import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
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
  DiscoveryRepository? _repositoryInstance;
  DiscoveryRepository get _repository => _repositoryInstance!;
  final List<DiscoveryRoom> _rooms = <DiscoveryRoom>[];
  int _rotation = 0;
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

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
    final int generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<DiscoveryRoom> rooms = await _repository.fetchHomeRooms();
      if (!mounted || generation != _loadGeneration) {
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
      if (!mounted || generation != _loadGeneration) {
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
    return SocialSkySurface(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                sliver: SliverToBoxAdapter(child: _buildHeader(context)),
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
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      '此刻适合你的房间',
                      style: Theme.of(context).textTheme.headlineSmall,
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
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 10),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: <Widget>[
                        Text(
                          '正在发生',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: rooms.length <= 1
                              ? null
                              : () => setState(
                                  () => _rotation =
                                      (_rotation + 1) % rooms.length,
                                ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('换一批'),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  sliver: SliverList.separated(
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (BuildContext context, int index) =>
                        _LiveRoomCard(
                          room: rooms[index],
                          onTap: () => _enterRoom(rooms[index]),
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _openSearch,
                child: const IgnorePointer(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索房间、用户或房间号',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: '创建房间',
              onPressed: _openCreateRoom,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            _HeaderShortcut(
              icon: Icons.bookmark_outline_rounded,
              label: '收藏与我的房间',
              onTap: _openSavedRooms,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '按实时活跃度与关系推荐',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
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

class _HeaderShortcut extends StatelessWidget {
  const _HeaderShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 19, color: AppColors.textSecondary),
            const SizedBox(width: 7),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
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
    final String? fontFamily = Theme.of(
      context,
    ).textTheme.bodyMedium?.fontFamily;
    return Theme(
      data: AppTheme.room(fontFamily: fontFamily),
      child: OriginalRoomArtwork(
        seed: room.id,
        height: 280,
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: RoomColors.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          room.isSpeaking
                              ? Icons.graphic_eq_rounded
                              : Icons.headphones_rounded,
                          size: 16,
                          color: RoomColors.success,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          room.isSpeaking ? '正在热聊' : '正在收听',
                          style: const TextStyle(color: RoomColors.success),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (room.isLocked) ...<Widget>[
                    const Icon(Icons.lock_outline_rounded, size: 17),
                    const SizedBox(width: 6),
                  ],
                  Text(discoveryOnlineCountLabel(room.onlineCount)),
                ],
              ),
              const Spacer(),
              Text(room.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 7),
              Text(
                room.topic,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: RoomColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              _SeatSummary(occupiedSeats: room.occupiedSeats),
              const SizedBox(height: 9),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.people_alt_rounded,
                    size: 18,
                    color: RoomColors.accent,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      room.relationReason ?? '根据当前活跃度推荐',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  FilledButton(onPressed: onEnter, child: const Text('进入房间')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveRoomCard extends StatelessWidget {
  const _LiveRoomCard({required this.room, required this.onTap});

  final DiscoveryRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: room.isSpeaking
                      ? AppColors.primary.withValues(alpha: 0.22)
                      : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  room.isSpeaking
                      ? Icons.graphic_eq_rounded
                      : Icons.headphones_rounded,
                  color: room.isSpeaking
                      ? AppColors.primary
                      : AppColors.textSecondary,
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
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (room.isLocked)
                          const Icon(Icons.lock_outline_rounded, size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      room.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${room.occupiedSeats}/8 麦 · ${discoveryOnlineCountLabel(room.onlineCount)} · ${room.relationReason ?? '实时推荐'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeatSummary extends StatelessWidget {
  const _SeatSummary({required this.occupiedSeats});

  final int occupiedSeats;

  @override
  Widget build(BuildContext context) {
    final int safeOccupied = occupiedSeats < 0
        ? 0
        : occupiedSeats > 8
        ? 8
        : occupiedSeats;
    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (int index = 0; index < 8; index += 1)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < safeOccupied
                        ? RoomColors.primary.withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.07),
                    border: Border.all(
                      color: index < safeOccupied
                          ? RoomColors.primary
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Icon(
                    index < safeOccupied
                        ? Icons.person_rounded
                        : Icons.add_rounded,
                    size: 12,
                    color: index < safeOccupied
                        ? RoomColors.textPrimary
                        : RoomColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
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
