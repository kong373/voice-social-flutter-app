import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';
import 'package:voice_social_app/features/room/presentation/edit_room_page.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';

enum _SavedRoomSection { favorites, owned }

class SavedRoomsPage extends StatefulWidget {
  const SavedRoomsPage({super.key});

  @override
  State<SavedRoomsPage> createState() => _SavedRoomsPageState();
}

class _SavedRoomsPageState extends State<SavedRoomsPage> {
  DiscoveryRepository? _repositoryInstance;
  DiscoveryRepository get _repository => _repositoryInstance!;
  RoomCollectionSnapshot? _snapshot;
  _SavedRoomSection _section = _SavedRoomSection.favorites;
  bool _loading = true;
  String? _error;
  String? _busyRoomId;

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
      final RoomCollectionSnapshot snapshot = await _repository
          .fetchRoomCollections();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '房间收藏暂时无法加载，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(
        title: const Text('收藏与我的房间'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<_SavedRoomSection>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<_SavedRoomSection>>[
                ButtonSegment<_SavedRoomSection>(
                  value: _SavedRoomSection.favorites,
                  label: Text('收藏房间'),
                  icon: Icon(Icons.bookmark_outline_rounded),
                ),
                ButtonSegment<_SavedRoomSection>(
                  value: _SavedRoomSection.owned,
                  label: Text('我的房间'),
                  icon: Icon(Icons.meeting_room_outlined),
                ),
              ],
              selected: <_SavedRoomSection>{_section},
              onSelectionChanged: (Set<_SavedRoomSection> value) {
                setState(() => _section = value.first);
              },
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
      return _CollectionState(
        icon: Icons.cloud_off_rounded,
        title: '加载失败',
        description: _error!,
        actionLabel: '重新加载',
        onAction: _load,
      );
    }
    final RoomCollectionSnapshot snapshot =
        _snapshot ??
        const RoomCollectionSnapshot(
          favorites: <DiscoveryRoom>[],
          ownedRooms: <DiscoveryRoom>[],
        );
    final List<DiscoveryRoom> rooms = _section == _SavedRoomSection.favorites
        ? snapshot.favorites
        : snapshot.ownedRooms;
    if (rooms.isEmpty) {
      return _CollectionState(
        icon: _section == _SavedRoomSection.favorites
            ? Icons.bookmark_border_rounded
            : Icons.meeting_room_outlined,
        title: _section == _SavedRoomSection.favorites
            ? '还没有收藏房间'
            : '当前账号暂无可管理房间',
        description: _section == _SavedRoomSection.favorites
            ? '在房间详情中收藏后，会在这里集中显示。'
            : '创建或启用个人房后，可在这里编辑和进入。',
        actionLabel: '返回首页',
        onAction: () => Navigator.of(context).pop(),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) {
          final DiscoveryRoom room = rooms[index];
          return _SavedRoomCard(
            room: room,
            busy: _busyRoomId == room.id,
            onEnter: () => _enterRoom(room),
            onFavorite: _section == _SavedRoomSection.favorites
                ? () => _removeFavorite(room)
                : null,
            onManage: _section == _SavedRoomSection.owned
                ? () => _manageRoom(room)
                : null,
          );
        },
      ),
    );
  }

  Future<void> _removeFavorite(DiscoveryRoom room) async {
    if (_busyRoomId != null) {
      return;
    }
    setState(() => _busyRoomId = room.id);
    try {
      await _repository.setFavorite(roomId: room.id, favorite: false);
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is ApiException ? error.message : '取消收藏失败，请重试'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyRoomId = null);
      }
    }
  }

  void _enterRoom(DiscoveryRoom room) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RoomPage(roomId: room.id, title: room.title),
      ),
    );
  }

  Future<void> _manageRoom(DiscoveryRoom room) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => EditRoomPage(roomId: room.id),
      ),
    );
    if (changed == true) {
      await _load();
    }
  }
}

class _SavedRoomCard extends StatelessWidget {
  const _SavedRoomCard({
    required this.room,
    required this.busy,
    required this.onEnter,
    required this.onFavorite,
    required this.onManage,
  });

  final DiscoveryRoom room;
  final bool busy;
  final VoidCallback onEnter;
  final VoidCallback? onFavorite;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.lock_outline_rounded, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              room.topic,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              '房间号 ${room.code} · ${room.occupiedSeats}/8 麦 · ${room.onlineCount} 人在线',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                if (onFavorite != null)
                  TextButton.icon(
                    onPressed: busy ? null : onFavorite,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bookmark_remove_outlined),
                    label: const Text('取消收藏'),
                  ),
                if (onManage != null)
                  TextButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('管理'),
                  ),
                const Spacer(),
                FilledButton(onPressed: onEnter, child: const Text('进入房间')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionState extends StatelessWidget {
  const _CollectionState({
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
