import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';
import 'package:voice_social_app/features/discovery/presentation/saved_rooms_page.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/shell/live_read_only_pages.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

class VideoRuntimeHomePage extends StatefulWidget {
  const VideoRuntimeHomePage({
    required this.dependencies,
    required this.onOpenRoom,
    super.key,
  });

  final AppDependencies dependencies;
  final void Function(DiscoveryRoom room) onOpenRoom;

  @override
  State<VideoRuntimeHomePage> createState() => _VideoRuntimeHomePageState();
}

class _VideoRuntimeHomePageState extends State<VideoRuntimeHomePage> {
  static const List<String> _categories = <String>[
    '推荐',
    '轻聊',
    '情感',
    '交友',
    '电台',
  ];

  List<DiscoveryRoom> _rooms = const <DiscoveryRoom>[];
  bool _loading = true;
  String? _error;
  int _category = 0;
  int _roomOffset = 0;

  List<DiscoveryRoom> get _visibleRooms {
    final List<DiscoveryRoom> matching = _rooms
        .where(_matchesSelectedCategory)
        .toList(growable: false);
    final List<DiscoveryRoom> source = matching.isEmpty ? _rooms : matching;
    if (source.length < 2) {
      return source;
    }
    final int start = _roomOffset % source.length;
    return <DiscoveryRoom>[...source.skip(start), ...source.take(start)];
  }

  bool _matchesSelectedCategory(DiscoveryRoom room) {
    if (_category == 0) {
      return true;
    }
    final String searchable = '${room.title}${room.topic}';
    return switch (_category) {
      1 => <String>['轻聊', '聊天', '闲聊', '松弛'].any(searchable.contains),
      2 => <String>['情感', '温柔', '陪伴', '治愈', '心情'].any(searchable.contains),
      3 => <String>['交友', '朋友', '认识', '聊天局'].any(searchable.contains),
      4 => <String>['电台', '音乐', '新歌'].any(searchable.contains),
      _ => true,
    };
  }

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final List<DiscoveryRoom> rooms = await widget
          .dependencies
          .discoveryRepository
          .fetchHomeRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _roomOffset = 0;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '房间推荐暂时无法加载';
      });
    }
  }

  void _openSearch() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => const GlobalSearchPage(),
    ),
  );

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _selectCategory(int index) {
    setState(() {
      _category = index;
      _roomOffset = 0;
    });
  }

  void _rotateRooms() {
    if (_visibleRooms.length < 2) {
      _load();
      return;
    }
    setState(() => _roomOffset += 1);
  }

  void _openRanking() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => const RankingPage(),
    ),
  );

  Future<void> _showTopicPicker() async {
    final List<DiscoveryRoom> rooms = _visibleRooms
        .take(3)
        .toList(growable: false);
    if (rooms.isEmpty) {
      _toast('当前还没有可进入的话题房');
      return;
    }
    final DiscoveryRoom? selected = await showModalBottomSheet<DiscoveryRoom>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('选一个话题加入', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final DiscoveryRoom room in rooms)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: RuntimeAvatar(seed: room.id, size: 40),
                title: Text(room.topic),
                subtitle: Text('${room.title} · ${room.onlineCount} 人在线'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(sheetContext).pop(room),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      widget.onOpenRoom(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DiscoveryRoom> visibleRooms = _visibleRooms;
    return SocialSkySurface(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            key: const Key('video-runtime-home'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                sliver: SliverToBoxAdapter(child: _header()),
              ),
              SliverToBoxAdapter(child: _tabs()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                sliver: SliverToBoxAdapter(child: _hero()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
                sliver: SliverToBoxAdapter(child: _activity()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
                sliver: SliverToBoxAdapter(child: _finder()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 7),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: <Widget>[
                      Text(
                        '正在发生',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(width: 7),
                      const RuntimeWaveform(width: 30),
                      const Spacer(),
                      TextButton(
                        key: const Key('home-rotate-rooms'),
                        onPressed: _rotateRooms,
                        child: const Text('换一批'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 210,
                    child: _LightState(
                      icon: Icons.cloud_off_rounded,
                      title: '加载失败',
                      description: _error!,
                      actionLabel: '重试',
                      onAction: _load,
                    ),
                  ),
                )
              else if (_rooms.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 210,
                    child: _LightState(
                      icon: Icons.headphones_rounded,
                      title: '暂时没有开放中的房间',
                      description: '下拉刷新，稍后再来听听。',
                      actionLabel: '刷新',
                      onAction: _load,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 34),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 9,
                          mainAxisSpacing: 9,
                          childAspectRatio: 0.78,
                        ),
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final DiscoveryRoom room = visibleRooms[index];
                      return _RoomPoster(
                        room: room,
                        onTap: () => widget.onOpenRoom(room),
                      );
                    }, childCount: visibleRooms.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: <Widget>[
      Text(
        '发现',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontSize: 26, letterSpacing: -0.5),
      ),
      const Spacer(),
      _RoundHeaderButton(
        icon: Icons.emoji_events_outlined,
        tooltip: '榜单',
        onTap: _openRanking,
      ),
      const SizedBox(width: 7),
      _RoundHeaderButton(
        icon: Icons.search_rounded,
        tooltip: '搜索',
        onTap: _openSearch,
      ),
    ],
  );

  Widget _tabs() => SizedBox(
    height: 50,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      itemCount: _categories.length,
      separatorBuilder: (_, __) => const SizedBox(width: 22),
      itemBuilder: (BuildContext context, int index) {
        final bool active = _category == index;
        return InkWell(
          onTap: () => _selectCategory(index),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _categories[index],
                style: TextStyle(
                  color: active
                      ? SocialColors.textPrimary
                      : SocialColors.textSecondary,
                  fontSize: active ? 15 : 14,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
              if (active)
                Container(
                  width: 17,
                  height: 3,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    gradient: SocialColors.brandGradient,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _hero() {
    final DiscoveryRoom? room = _visibleRooms.firstOrNull;
    return SizedBox(
      height: 104,
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 6,
            child: OriginalRoomArtwork(
              seed: 'hero-main',
              height: 104,
              borderRadius: BorderRadius.circular(19),
              child: InkWell(
                onTap: room == null ? null : () => widget.onOpenRoom(room),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 11, 11, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Row(
                        children: <Widget>[
                          Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                          ),
                          Spacer(),
                          Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFFF9AC7),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        room?.title ?? '深夜轻聊',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          shadows: <Shadow>[
                            Shadow(color: Colors.black45, blurRadius: 7),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _HeroMiniCard(
                    seed: 'hero-date',
                    label: '约个轻聊',
                    icon: Icons.forum_rounded,
                    onTap: _openSearch,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _HeroMiniCard(
                    seed: 'hero-friends',
                    label: '交友房',
                    icon: Icons.favorite_border_rounded,
                    onTap: () => _selectCategory(3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activity() {
    final DiscoveryRoom? room = _rooms
        .where((DiscoveryRoom item) => item.isFavorite)
        .firstOrNull;
    return SocialCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      radius: 15,
      color: const Color(0xEAF5E8FF),
      onTap: room == null ? null : () => widget.onOpenRoom(room),
      child: const Row(
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Stack(
              children: <Widget>[
                RuntimeAvatar(seed: 'activity-1', size: 28),
                Positioned(
                  left: 20,
                  child: RuntimeAvatar(seed: 'activity-2', size: 28),
                ),
              ],
            ),
          ),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              '云朵和晚星正在「周末轻聊」 · 3 人在听',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: SocialColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: SocialColors.textTertiary),
        ],
      ),
    );
  }

  Widget _finder() => SizedBox(
    height: 96,
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 98,
          child: SocialCard(
            padding: const EdgeInsets.all(10),
            radius: 18,
            color: const Color(0xEBDCD9FF),
            onTap: _openSearch,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    RuntimeAvatar(seed: 'finder', size: 28),
                    Spacer(),
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ],
                ),
                Spacer(),
                Text(
                  '找个聊得来的人',
                  maxLines: 2,
                  style: TextStyle(
                    color: SocialColors.primaryDark,
                    fontSize: 12,
                    height: 1.16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SocialCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            radius: 18,
            color: const Color(0xE9D8E6FF),
            onTap: _showTopicPicker,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _TopicPreview(seed: 'topic-1', text: '今天有什么让你开心的事？'),
                _TopicPreview(seed: 'topic-2', text: '分享一首最近循环的歌'),
                _TopicPreview(seed: 'topic-3', text: '来一局轻松的房间小游戏'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _RoundHeaderButton extends StatelessWidget {
  const _RoundHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white.withValues(alpha: 0.58),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 36,
          child: Icon(icon, size: 21, color: SocialColors.textPrimary),
        ),
      ),
    ),
  );
}

class _HeroMiniCard extends StatelessWidget {
  const _HeroMiniCard({
    required this.seed,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String seed;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OriginalRoomArtwork(
    seed: seed,
    height: 104,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Column(
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 23),
            const Spacer(),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.14,
                fontWeight: FontWeight.w800,
                shadows: <Shadow>[Shadow(color: Colors.black38, blurRadius: 6)],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TopicPreview extends StatelessWidget {
  const _TopicPreview({required this.seed, required this.text});

  final String seed;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      RuntimeAvatar(seed: seed, size: 20),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: SocialColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _RoomPoster extends StatelessWidget {
  const _RoomPoster({required this.room, required this.onTap});

  final DiscoveryRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SocialCard(
    key: Key('live-room-${room.id}'),
    padding: EdgeInsets.zero,
    radius: 17,
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: OriginalRoomArtwork(
            seed: room.id,
            height: double.infinity,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xC56E53F6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '• 热聊',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.signal_cellular_alt_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                      Text(
                        '${room.onlineCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    room.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black54, blurRadius: 9),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                room.topic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SocialColors.textSecondary,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: <Widget>[
                  RuntimeAvatar(seed: '${room.id}-1', size: 21),
                  Transform.translate(
                    offset: const Offset(-5, 0),
                    child: RuntimeAvatar(seed: '${room.id}-2', size: 21),
                  ),
                  const Spacer(),
                  Text(
                    '${room.occupiedSeats}/8 麦',
                    style: const TextStyle(
                      color: SocialColors.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class VideoRuntimeDiscoveryPage extends StatefulWidget {
  const VideoRuntimeDiscoveryPage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<VideoRuntimeDiscoveryPage> createState() =>
      _VideoRuntimeDiscoveryPageState();
}

class _VideoRuntimeDiscoveryPageState extends State<VideoRuntimeDiscoveryPage> {
  int _tab = 0;
  final Set<String> _liked = <String>{'post-moon'};
  final Set<String> _followed = <String>{'post-moon', 'post-island'};
  final List<_MockPost> _publishedPosts = <_MockPost>[];

  List<_MockPost> get _visiblePosts {
    final List<_MockPost> posts = <_MockPost>[
      ..._publishedPosts,
      ..._mockPosts,
    ];
    if (_tab == 0) {
      return posts;
    }
    return posts
        .where((_MockPost post) => _followed.contains(post.seed))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<_MockPost> visiblePosts = _visiblePosts;
    return SocialSkySurface(
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const Key('video-runtime-discovery'),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(15, 9, 10, 8),
              sliver: SliverToBoxAdapter(child: _header()),
            ),
            if (widget.dependencies.environment.isLive)
              const SliverFillRemaining(child: DiscoveryFeedPage())
            else ...<Widget>[
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 2, 12, 10),
                sliver: SliverToBoxAdapter(child: _MomentBanner()),
              ),
              if (visiblePosts.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LightState(
                    icon: Icons.person_search_rounded,
                    title: '还没有关注动态',
                    description: '去发现页关注喜欢的人，他们的新动态会出现在这里。',
                  ),
                )
              else
                SliverList.separated(
                  itemCount: visiblePosts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final _MockPost post = visiblePosts[index];
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        0,
                        12,
                        index == visiblePosts.length - 1 ? 34 : 0,
                      ),
                      child: _FeedCard(
                        post: post,
                        liked: _liked.contains(post.seed),
                        followed: _followed.contains(post.seed),
                        onLike: () => setState(() {
                          _liked.contains(post.seed)
                              ? _liked.remove(post.seed)
                              : _liked.add(post.seed);
                        }),
                        onFollow: () => setState(() {
                          _followed.contains(post.seed)
                              ? _followed.remove(post.seed)
                              : _followed.add(post.seed);
                        }),
                        onComment: () => _showCommentSheet(post.name),
                        onShare: () => _showShareSheet(post),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: <Widget>[
      for (int index = 0; index < 2; index += 1)
        Padding(
          padding: const EdgeInsets.only(right: 22),
          child: InkWell(
            onTap: () => setState(() => _tab = index),
            child: Column(
              children: <Widget>[
                Text(
                  index == 0 ? '发现' : '关注',
                  style: TextStyle(
                    color: _tab == index
                        ? SocialColors.textPrimary
                        : SocialColors.textSecondary,
                    fontSize: _tab == index ? 23 : 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_tab == index)
                  Container(
                    width: 18,
                    height: 3,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                      gradient: SocialColors.brandGradient,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
          ),
        ),
      const Spacer(),
      _RoundHeaderButton(
        icon: Icons.add_rounded,
        tooltip: '发布动态',
        onTap: _openPublisher,
      ),
    ],
  );

  Future<void> _openPublisher() async {
    final DynamicPost? post = await Navigator.of(context).push<DynamicPost>(
      MaterialPageRoute<DynamicPost>(
        builder: (BuildContext context) => const PublishDynamicPage(),
      ),
    );
    if (post == null || !mounted) {
      return;
    }
    setState(() {
      _tab = 0;
      _publishedPosts.insert(
        0,
        _MockPost(
          name: post.author.nickname,
          time: '刚刚',
          text: post.content,
          location: post.location,
          seed: 'published-${post.id}',
          likes: post.likeCount,
          showArtwork: post.images.isNotEmpty,
        ),
      );
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('动态已发布')));
  }

  Future<void> _showShareSheet(_MockPost post) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('分享动态', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制动态文字'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: post.text));
                if (!mounted || !sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('动态文字已复制')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('发给好友'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const MessageCenterPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCommentSheet(String name) async {
    final TextEditingController controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          14 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(hintText: '回复 $name…'),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('评论已发布')));
              },
              child: const Text('发送'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}

class _MomentBanner extends StatelessWidget {
  const _MomentBanner();

  @override
  Widget build(BuildContext context) => OriginalRoomArtwork(
    seed: 'moment-banner',
    height: 92,
    borderRadius: BorderRadius.circular(20),
    child: const Padding(
      padding: EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '今天也有人认真生活',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  '分享真实片刻，遇见同频的人',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(Icons.camera_alt_rounded, color: Colors.white, size: 30),
        ],
      ),
    ),
  );
}

class _MockPost {
  const _MockPost({
    required this.name,
    required this.time,
    required this.text,
    required this.location,
    required this.seed,
    required this.likes,
    this.showArtwork = true,
  });

  final String name;
  final String time;
  final String text;
  final String location;
  final String seed;
  final int likes;
  final bool showArtwork;
}

const List<_MockPost> _mockPosts = <_MockPost>[
  _MockPost(
    name: '晚星',
    time: '12 分钟前',
    text: '云很低，风很轻。今天适合和喜欢的人慢慢聊天。',
    location: '杭州 · 湖畔',
    seed: 'post-moon',
    likes: 128,
  ),
  _MockPost(
    name: '橘子汽水',
    time: '36 分钟前',
    text: '周末的快乐很简单：一张唱片、一杯冰饮，还有房间里熟悉的声音。',
    location: '广州 · 旧街',
    seed: 'post-festival',
    likes: 86,
  ),
  _MockPost(
    name: '岛屿来信',
    time: '1 小时前',
    text: '记录一次不赶时间的日落。愿每个人都能遇见可以安静倾听的伙伴。',
    location: '厦门 · 海边',
    seed: 'post-island',
    likes: 214,
  ),
];

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.post,
    required this.liked,
    required this.followed,
    required this.onLike,
    required this.onFollow,
    required this.onComment,
    required this.onShare,
  });

  final _MockPost post;
  final bool liked;
  final bool followed;
  final VoidCallback onLike;
  final VoidCallback onFollow;
  final VoidCallback onComment;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) => SocialCard(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
    radius: 20,
    color: Colors.white.withValues(alpha: 0.9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            RuntimeAvatar(seed: post.name, size: 42),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    post.name,
                    style: const TextStyle(
                      color: SocialColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    post.location.isEmpty
                        ? post.time
                        : '${post.time} · ${post.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SocialColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            SocialPill(
              label: followed ? '已关注' : '关注',
              active: followed,
              onTap: onFollow,
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          post.text,
          style: const TextStyle(
            color: SocialColors.textPrimary,
            fontSize: 13,
            height: 1.44,
          ),
        ),
        if (post.showArtwork) ...<Widget>[
          const SizedBox(height: 9),
          OriginalRoomArtwork(
            seed: post.seed,
            height: 168,
            borderRadius: BorderRadius.circular(16),
          ),
        ],
        const SizedBox(height: 5),
        Row(
          children: <Widget>[
            _FeedAction(
              icon: liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: '${post.likes + (liked ? 1 : 0)}',
              color: liked ? SocialColors.secondary : null,
              onTap: onLike,
            ),
            _FeedAction(
              icon: Icons.chat_bubble_outline_rounded,
              label: '18',
              onTap: onComment,
            ),
            _FeedAction(
              icon: Icons.ios_share_rounded,
              label: '分享',
              onTap: onShare,
            ),
          ],
        ),
      ],
    ),
  );
}

class _FeedAction extends StatelessWidget {
  const _FeedAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 17, color: color ?? SocialColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color ?? SocialColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class VideoRuntimeMessagesPage extends StatefulWidget {
  const VideoRuntimeMessagesPage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<VideoRuntimeMessagesPage> createState() =>
      _VideoRuntimeMessagesPageState();
}

class _VideoRuntimeMessagesPageState extends State<VideoRuntimeMessagesPage> {
  int _tab = 0;
  List<ConversationSummary>? _conversations;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadConversations);
  }

  Future<void> _loadConversations() async {
    if (!widget.dependencies.messageRepository.supportsConversationList) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<ConversationSummary> value = await widget
          .dependencies
          .messageRepository
          .fetchConversations();
      if (!mounted) return;
      setState(() {
        _conversations = value;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '消息列表暂时无法加载';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dependencies.environment.isLive &&
        !widget.dependencies.messageRepository.supportsConversationList) {
      return const _LiveMessageSurface();
    }
    final List<ConversationSummary> conversations =
        (_conversations ?? const <ConversationSummary>[])
            .where((ConversationSummary item) => _tab == 0 || item.available)
            .toList(growable: false);
    return SocialSkySurface(
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('video-runtime-messages'),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
          children: <Widget>[
            _header(),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: _MessageShortcut(
                    icon: Icons.notifications_none_rounded,
                    title: '系统消息',
                    accent: Color(0xFF6D9BFF),
                    onTap: () =>
                        _openNotifications(NotificationCategory.system),
                  ),
                ),
                Expanded(
                  child: _MessageShortcut(
                    icon: Icons.favorite_border_rounded,
                    title: '互动通知',
                    accent: SocialColors.secondary,
                    onTap: () =>
                        _openNotifications(NotificationCategory.interaction),
                  ),
                ),
                Expanded(
                  child: _MessageShortcut(
                    icon: Icons.person_add_alt_1_rounded,
                    title: '好友请求',
                    accent: Color(0xFF63CDB6),
                    onTap: () => _openPage(const RelationsPage()),
                  ),
                ),
                Expanded(
                  child: _MessageShortcut(
                    icon: Icons.support_agent_rounded,
                    title: '帮助助手',
                    accent: Color(0xFFFFB466),
                    onTap: () => _openPage(const HelpCenterPage()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              _tab == 0 ? '最近消息' : '我的联系人',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (_loading)
              const SizedBox(
                height: 170,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SizedBox(
                height: 190,
                child: _LightState(
                  icon: Icons.cloud_off_rounded,
                  title: '消息加载失败',
                  description: _error!,
                  actionLabel: '重试',
                  onAction: _loadConversations,
                ),
              )
            else if (conversations.isEmpty)
              _LightState(
                icon: Icons.forum_outlined,
                title: _tab == 0 ? '还没有消息' : '还没有可联系的好友',
                description: _tab == 0 ? '进入感兴趣的房间，认识同频的人。' : '建立好友关系后，会显示在这里。',
              )
            else
              SocialCard(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                radius: 20,
                child: Column(
                  children: <Widget>[
                    for (
                      int index = 0;
                      index < conversations.length;
                      index += 1
                    ) ...<Widget>[
                      _ConversationRow(
                        conversation: conversations[index],
                        contactOnly: _tab == 1,
                        onTap: () => _openConversation(conversations[index]),
                      ),
                      if (index < conversations.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      for (int index = 0; index < 2; index += 1)
        Padding(
          padding: const EdgeInsets.only(right: 22),
          child: InkWell(
            onTap: () => setState(() => _tab = index),
            child: Text(
              index == 0 ? '消息' : '联系人',
              style: TextStyle(
                color: _tab == index
                    ? SocialColors.textPrimary
                    : SocialColors.textSecondary,
                fontSize: _tab == index ? 25 : 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      const Spacer(),
      _RoundHeaderButton(
        icon: Icons.search_rounded,
        tooltip: '搜索消息',
        onTap: _openMessageCenter,
      ),
    ],
  );

  void _openMessageCenter() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => const MessageCenterPage(),
    ),
  );

  void _openNotifications(NotificationCategory category) =>
      _openPage(NotificationCenterPage(initialCategory: category));

  void _openConversation(ConversationSummary conversation) =>
      Navigator.of(context)
          .push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  PrivateChatPage(conversation: conversation),
            ),
          )
          .then((_) => _loadConversations());

  void _openPage(Widget page) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (BuildContext context) => page),
  );
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversation,
    required this.contactOnly,
    required this.onTap,
  });

  final ConversationSummary conversation;
  final bool contactOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: <Widget>[
            Stack(
              children: <Widget>[
                RuntimeAvatar(seed: conversation.id, size: 48),
                if (conversation.available)
                  Positioned(
                    right: 1,
                    bottom: 2,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFF59D8A4),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    conversation.title,
                    style: const TextStyle(
                      color: SocialColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contactOnly
                        ? '在线 · 可以开始聊天'
                        : conversation.available
                        ? conversation.lastMessage
                        : conversation.unavailableReason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SocialColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (!contactOnly)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    _conversationTime(conversation.updatedAt),
                    style: const TextStyle(
                      color: SocialColors.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (conversation.unreadCount > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 17),
                      height: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: SocialColors.secondary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${conversation.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static String _conversationTime(DateTime value) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime messageDay = DateTime(value.year, value.month, value.day);
    if (messageDay == today) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    if (today.difference(messageDay).inDays == 1) {
      return '昨天';
    }
    return '${value.month}/${value.day}';
  }
}

class _LiveMessageSurface extends StatelessWidget {
  const _LiveMessageSurface();

  @override
  Widget build(BuildContext context) => SocialSkySurface(
    child: SafeArea(
      bottom: false,
      child: ListView(
        key: const Key('video-runtime-messages'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: <Widget>[
          Text('消息', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: _MessageShortcut(
                  icon: Icons.notifications_none_rounded,
                  title: '系统消息',
                  accent: Color(0xFF6D9BFF),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          const NotificationCenterPage(),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _MessageShortcut(
                  icon: Icons.favorite_border_rounded,
                  title: '互动通知',
                  accent: SocialColors.secondary,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          const NotificationCenterPage(
                            initialCategory: NotificationCategory.interaction,
                          ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _MessageShortcut(
                  icon: Icons.person_add_alt_1_rounded,
                  title: '好友请求',
                  accent: Color(0xFF63CDB6),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => const RelationsPage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _LightState(
            key: Key('im-vendor-blocked'),
            icon: Icons.forum_outlined,
            title: '消息服务正在准备',
            description: '不会伪造私聊和互动消息。服务接通后会展示真实会话。',
          ),
        ],
      ),
    ),
  );
}

class _MessageShortcut extends StatelessWidget {
  const _MessageShortcut({
    required this.icon,
    required this.title,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: <Widget>[
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[accent.withValues(alpha: 0.55), accent],
              ),
              borderRadius: BorderRadius.circular(17),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SocialColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class VideoRuntimeAccountPage extends StatelessWidget {
  const VideoRuntimeAccountPage({
    required this.dependencies,
    required this.onOpenRoom,
    required this.onSignOut,
    super.key,
  });

  final AppDependencies dependencies;
  final void Function(DiscoveryRoom room) onOpenRoom;
  final Future<void> Function() onSignOut;

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (BuildContext context) => page),
      );

  @override
  Widget build(BuildContext context) {
    final String account = dependencies.sessionManager.session?.mobile ?? '';
    final Widget accountPage = dependencies.environment.isLive
        ? LiveReadOnlyAccountPage(
            dependencies: dependencies,
            onSignOut: onSignOut,
          )
        : PersonalCenterPage(
            session: dependencies.sessionManager.session,
            onSignOut: onSignOut,
          );
    return SocialSkySurface(
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const Key('video-runtime-account'),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 4),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: <Widget>[
                    Text(
                      '我的',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    _RoundHeaderButton(
                      icon: Icons.settings_outlined,
                      tooltip: '设置',
                      onTap: () => _open(context, accountPage),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              sliver: SliverToBoxAdapter(
                child: _ProfileHeader(onTap: () => _open(context, accountPage)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              sliver: SliverToBoxAdapter(
                child: _DecorationBanner(
                  onTap: () => _open(context, const DecorationPage()),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _AccountFeatureCard(
                        icon: Icons.account_balance_wallet_outlined,
                        title: '钱包',
                        subtitle: '礼物币与流水',
                        color: const Color(0xFFFFE4B8),
                        onTap: () =>
                            _open(context, CommerceHubPage(account: account)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AccountFeatureCard(
                        icon: Icons.photo_library_outlined,
                        title: '收藏房间',
                        subtitle: '最近听过的',
                        color: const Color(0xFFDCEAFF),
                        onTap: () => _open(context, const SavedRoomsPage()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AccountFeatureCard(
                        icon: Icons.storefront_outlined,
                        title: '装扮',
                        subtitle: '头像框与进场',
                        color: const Color(0xFFFFDDED),
                        onTap: () => _open(context, const DecorationPage()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 9),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '最近常听',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: _RecentRoomsStrip(onOpenRoom: onOpenRoom),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 9),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '我的服务',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 34),
              sliver: SliverToBoxAdapter(
                child: SocialCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                  radius: 20,
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.94,
                    children: <Widget>[
                      _AccountTool(
                        icon: Icons.people_outline_rounded,
                        label: '关注与粉丝',
                        onTap: () => _open(context, const RelationsPage()),
                      ),
                      _AccountTool(
                        icon: Icons.event_available_outlined,
                        label: '活动中心',
                        onTap: () => _open(context, const ActivityCenterPage()),
                      ),
                      _AccountTool(
                        icon: Icons.visibility_outlined,
                        label: '访客记录',
                        onTap: () => _open(context, const VisitorRecordsPage()),
                      ),
                      _AccountTool(
                        icon: Icons.manage_accounts_outlined,
                        label: '资料与设置',
                        onTap: () => _open(context, accountPage),
                      ),
                      _AccountTool(
                        icon: Icons.notifications_none_rounded,
                        label: '通知中心',
                        onTap: () =>
                            _open(context, const NotificationCenterPage()),
                      ),
                      _AccountTool(
                        icon: Icons.help_outline_rounded,
                        label: '帮助与反馈',
                        onTap: () => _open(context, const HelpCenterPage()),
                      ),
                      _AccountTool(
                        icon: Icons.verified_user_outlined,
                        label: '隐私与安全',
                        onTap: () => _open(context, accountPage),
                      ),
                      _AccountTool(
                        icon: Icons.more_horiz_rounded,
                        label: '更多',
                        onTap: () => _open(context, accountPage),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: <Widget>[
          const Row(
            children: <Widget>[
              RuntimeAvatar(seed: 'current-user', size: 74),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            '星河漫游者',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: SocialColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(
                          Icons.verified_rounded,
                          color: SocialColors.primary,
                          size: 18,
                        ),
                      ],
                    ),
                    SizedBox(height: 5),
                    Text(
                      'ID 880217 · 今天也在认真生活',
                      style: TextStyle(
                        color: SocialColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: SocialColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Row(
            children: <Widget>[
              _ProfileStat(value: '128', label: '关注'),
              _ProfileStat(value: '2.6k', label: '粉丝'),
              _ProfileStat(value: '18.9k', label: '获赞'),
              _ProfileStat(value: '32', label: '访客'),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            color: SocialColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: SocialColors.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _DecorationBanner extends StatelessWidget {
  const _DecorationBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF302659), Color(0xFF7455BB)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x337154C0),
              blurRadius: 18,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD681)),
            SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '个性装扮',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '管理头像框、进场与声波样式',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
            Text(
              '去装扮',
              style: TextStyle(
                color: Color(0xFFFFE7A8),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Color(0xFFFFE7A8)),
          ],
        ),
      ),
    ),
  );
}

class _AccountFeatureCard extends StatelessWidget {
  const _AccountFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: <Widget>[
            Icon(icon, color: SocialColors.textPrimary, size: 23),
            const SizedBox(height: 7),
            Text(
              title,
              style: const TextStyle(
                color: SocialColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SocialColors.textSecondary,
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecentRoomsStrip extends StatelessWidget {
  const _RecentRoomsStrip({required this.onOpenRoom});

  final void Function(DiscoveryRoom room) onOpenRoom;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: Row(
      children: <Widget>[
        for (final DiscoveryRoom room in _recentRooms) ...<Widget>[
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: Key('recent-room-${room.id}'),
                onTap: () => onOpenRoom(room),
                borderRadius: BorderRadius.circular(16),
                child: OriginalRoomArtwork(
                  seed: room.id,
                  height: 88,
                  borderRadius: BorderRadius.circular(16),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Text(
                        room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          shadows: <Shadow>[
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (room.id != _recentRooms.last.id) const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

const List<DiscoveryRoom> _recentRooms = <DiscoveryRoom>[
  DiscoveryRoom(
    id: '880217',
    code: '880217',
    title: '深夜轻聊',
    topic: '最近让你觉得被治愈的一件小事',
    onlineCount: 36,
    occupiedSeats: 3,
    isSpeaking: true,
    isFavorite: true,
  ),
  DiscoveryRoom(
    id: '520906',
    code: '520906',
    title: '周末电台',
    topic: '轻音乐与自由聊天，让夜晚慢下来',
    onlineCount: 18,
    occupiedSeats: 2,
    isSpeaking: false,
    isFavorite: true,
  ),
  DiscoveryRoom(
    id: '952700',
    code: '952700',
    title: '岛屿来信',
    topic: '不赶时间，慢慢认识新朋友',
    onlineCount: 12,
    occupiedSeats: 4,
    isSpeaking: true,
    isFavorite: false,
  ),
];

class _AccountTool extends StatelessWidget {
  const _AccountTool({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF0EDFF),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: SocialColors.primary, size: 21),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: SocialColors.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _LightState extends StatelessWidget {
  const _LightState({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: SocialCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: SocialColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(19),
              ),
              child: Icon(icon, color: SocialColors.primary, size: 27),
            ),
            const SizedBox(height: 13),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 13),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
