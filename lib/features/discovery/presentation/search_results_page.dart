import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/shared/widgets/scoped_placeholder_page.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text('“${widget.keyword}”的搜索结果'),
      ),
      body: Column(
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<SearchEntityType>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<SearchEntityType>>[
                ButtonSegment<SearchEntityType>(
                  value: SearchEntityType.all,
                  label: Text('全部'),
                ),
                ButtonSegment<SearchEntityType>(
                  value: SearchEntityType.rooms,
                  label: Text('房间'),
                ),
                ButtonSegment<SearchEntityType>(
                  value: SearchEntityType.users,
                  label: Text('用户'),
                ),
              ],
              selected: <SearchEntityType>{_type},
              onSelectionChanged: (Set<SearchEntityType> value) {
                setState(() => _type = value.first);
                _load();
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
      return _SearchState(
        icon: Icons.cloud_off_rounded,
        title: '搜索失败',
        description: _error!,
        actionLabel: '重新搜索',
        onAction: _load,
      );
    }
    final DiscoverySearchResult result = _result ??
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
        builder: (BuildContext context) => ScopedPlaceholderPage(
          pageId: 'US-003',
          title: user.name,
          description: user.bio ?? '查看该用户的公开资料、关系状态与可见动态。',
        ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.18),
          child: Icon(
            room.isSpeaking ? Icons.graphic_eq_rounded : Icons.headphones,
            color: AppColors.primary,
          ),
        ),
        title: Text(room.title),
        subtitle: Text(
          '${room.topic}\n${room.occupiedSeats}/8 麦 · ${room.onlineCount} 人在线',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (room.isLocked) const Icon(Icons.lock_outline_rounded, size: 18),
            const Icon(Icons.chevron_right_rounded),
          ],
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onOpenProfile,
        leading: CircleAvatar(child: Text(_initial(user.name))),
        title: Text(user.name),
        subtitle: Text(
          user.isInRoom
              ? '用户号 ${user.loginName} · 正在 ${user.currentRoomTitle ?? '语音房'}'
              : '用户号 ${user.loginName} · 当前未在房间',
        ),
        trailing: onEnterRoom == null
            ? const Icon(Icons.chevron_right_rounded)
            : FilledButton.tonal(
                onPressed: onEnterRoom,
                child: const Text('进房'),
              ),
      ),
    );
  }

  static String _initial(String value) =>
      value.isEmpty ? '?' : String.fromCharCode(value.runes.first);
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
