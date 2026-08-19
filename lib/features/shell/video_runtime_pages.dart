import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
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
    '陪伴',
    '轻聊',
    '情感',
    '电台',
  ];

  List<DiscoveryRoom> _rooms = const <DiscoveryRoom>[];
  bool _loading = true;
  String? _error;
  int _categoryIndex = 0;

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
      if (!mounted) {
        return;
      }
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '房间推荐暂时无法加载';
      });
    }
  }

  void _openSearch() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const GlobalSearchPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                sliver: SliverToBoxAdapter(child: _header()),
              ),
              SliverToBoxAdapter(child: _categoryBar()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                sliver: SliverToBoxAdapter(child: _heroMosaic()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                sliver: SliverToBoxAdapter(child: _activityStrip()),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 24, 18, 12),
                sliver: SliverToBoxAdapter(
                  child: SocialSectionTitle(
                    title: '正在发生',
                    subtitle: '点击封面直接进入语音房',
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LightState(
                    icon: Icons.cloud_off_rounded,
                    title: '房间推荐加载失败',
                    description: _error!,
                    actionLabel: '重新加载',
                    onAction: _load,
                  ),
                )
              else if (_rooms.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LightState(
                    icon: Icons.headphones_rounded,
                    title: '暂时没有开放中的房间',
                    description: '下拉刷新，稍后再来听听。',
                    actionLabel: '刷新',
                    onAction: _load,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 34),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final DiscoveryRoom room = _rooms[index];
                      return _RoomPoster(
                        room: room,
                        onTap: () => widget.onOpenRoom(room),
                      );
                    }, childCount: _rooms.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('遇见正在说话的人', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                '此刻有人在线，轻轻点进房间听一会儿',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: '搜索',
          onPressed: _openSearch,
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    );
  }

  Widget _categoryBar() {
    return SizedBox(
      height: 55,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) => SocialPill(
          label: _categories[index],
          active: _categoryIndex == index,
          onTap: () => setState(() => _categoryIndex = index),
        ),
      ),
    );
  }

  Widget _heroMosaic() {
    final DiscoveryRoom? room = _rooms.isEmpty ? null : _rooms.first;
    return SizedBox(
      height: 202,
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 6,
            child: SocialCard(
              padding: EdgeInsets.zero,
              radius: 24,
              onTap: room == null ? null : () => widget.onOpenRoom(room),
              child: OriginalRoomArtwork(
                seed: room?.id ?? 'hero-room',
                height: 202,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SocialPill(
                        label: '今晚推荐',
                        icon: Icons.auto_awesome_rounded,
                        active: true,
                      ),
                      const Spacer(),
                      Text(
                        room?.title ?? '深夜陪伴电台',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.18,
                          shadows: <Shadow>[
                            Shadow(color: Colors.black38, blurRadius: 10),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Row(
                        children: <Widget>[
                          RuntimeWaveform(width: 34),
                          SizedBox(width: 8),
                          Text(
                            '正在热聊',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: SocialCard(
                    padding: const EdgeInsets.all(13),
                    radius: 22,
                    color: const Color(0xFFF0EAFF),
                    onTap: _openSearch,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.person_search_rounded,
                          color: SocialColors.primary,
                        ),
                        Spacer(),
                        Text(
                          '找人找房',
                          style: TextStyle(
                            color: SocialColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '昵称、ID、房间号',
                          style: TextStyle(
                            color: SocialColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Expanded(
                  child: SocialCard(
                    padding: EdgeInsets.all(13),
                    radius: 22,
                    color: Color(0xFFE5F8FF),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.favorite_rounded,
                          color: SocialColors.secondary,
                        ),
                        Spacer(),
                        Text(
                          '关系动态',
                          style: TextStyle(
                            color: SocialColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '关注的人正在房间',
                          style: TextStyle(
                            color: SocialColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
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

  Widget _activityStrip() {
    return const SocialCard(
      padding: EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      radius: 18,
      child: Row(
        children: <Widget>[
          RuntimeAvatar(seed: 'live-activity', size: 34),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '晚星刚刚加入「深夜陪伴」 · 3 位朋友正在收听',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: SocialColors.textSecondary, fontSize: 12),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: SocialColors.textTertiary),
        ],
      ),
    );
  }
}

class _RoomPoster extends StatelessWidget {
  const _RoomPoster({required this.room, required this.onTap});

  final DiscoveryRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SocialCard(
      key: Key('live-room-${room.id}'),
      padding: EdgeInsets.zero,
      radius: 23,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) =>
                    OriginalRoomArtwork(
                      seed: room.id,
                      height: constraints.maxHeight,
                      borderRadius: BorderRadius.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      if (room.isSpeaking)
                                        const RuntimeWaveform(width: 24)
                                      else
                                        const Icon(
                                          Icons.headphones_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      const SizedBox(width: 5),
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                height: 1.18,
                                shadows: <Shadow>[
                                  Shadow(color: Colors.black45, blurRadius: 8),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  room.topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 7),
                Row(
                  children: <Widget>[
                    RuntimeAvatar(seed: '${room.id}-1', size: 23),
                    Transform.translate(
                      offset: const Offset(-6, 0),
                      child: RuntimeAvatar(seed: '${room.id}-2', size: 23),
                    ),
                    const Spacer(),
                    Text(
                      '${room.occupiedSeats}/8 麦',
                      style: Theme.of(context).textTheme.bodySmall,
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
}

class VideoRuntimeDiscoveryPage extends StatelessWidget {
  const VideoRuntimeDiscoveryPage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('video-runtime-discovery'),
      color: SocialColors.page,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Row(
                children: <Widget>[
                  Text('发现', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: '发布动态',
                    onPressed:
                        dependencies.dynamicRepository.supportsImagePublishing
                        ? () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('发布入口将在素材服务接入后开放')),
                          )
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SocialCard(
                padding: EdgeInsets.zero,
                radius: 24,
                child: OriginalRoomArtwork(
                  seed: 'discovery-banner',
                  height: 108,
                  borderRadius: BorderRadius.circular(24),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '今天也有人认真生活',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Spacer(),
                        Text(
                          '分享真实片刻，遇见同频的人',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Expanded(child: DiscoveryFeedPage()),
          ],
        ),
      ),
    );
  }
}

class VideoRuntimeMessagesPage extends StatelessWidget {
  const VideoRuntimeMessagesPage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    if (dependencies.environment.isLive &&
        !dependencies.messageRepository.supportsConversationList) {
      return const _LiveMessageSurface();
    }
    return ColoredBox(
      key: const Key('video-runtime-messages'),
      color: SocialColors.page,
      child: const SafeArea(bottom: false, child: MessageCenterPage()),
    );
  }
}

class _LiveMessageSurface extends StatelessWidget {
  const _LiveMessageSurface();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('video-runtime-messages'),
      color: SocialColors.page,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: <Widget>[
            Text('消息', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            const Row(
              children: <Widget>[
                Expanded(
                  child: _MessageShortcut(
                    icon: Icons.notifications_none_rounded,
                    title: '系统消息',
                    accent: Color(0xFF6D9BFF),
                  ),
                ),
                Expanded(
                  child: _MessageShortcut(
                    icon: Icons.favorite_border_rounded,
                    title: '互动通知',
                    accent: SocialColors.secondary,
                  ),
                ),
                Expanded(
                  child: _MessageShortcut(
                    icon: Icons.person_add_alt_1_rounded,
                    title: '好友请求',
                    accent: Color(0xFF63CDB6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const SocialSectionTitle(title: '最近会话'),
            const SizedBox(height: 12),
            const _LightState(
              key: Key('im-vendor-blocked'),
              icon: Icons.forum_outlined,
              title: '消息服务正在准备',
              description: '不会伪造私聊和互动消息。服务接通后，会在这里展示真实会话。',
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageShortcut extends StatelessWidget {
  const _MessageShortcut({
    required this.icon,
    required this.title,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(19),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class VideoRuntimeAccountPage extends StatelessWidget {
  const VideoRuntimeAccountPage({
    required this.dependencies,
    required this.onSignOut,
    super.key,
  });

  final AppDependencies dependencies;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
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
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Row(
                children: <Widget>[
                  Text('我的', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  IconButton(
                    tooltip: '设置',
                    onPressed: () {},
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: _ProfilePreview(),
            ),
            Expanded(child: accountPage),
          ],
        ),
      ),
    );
  }
}

class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview();

  @override
  Widget build(BuildContext context) {
    return SocialCard(
      key: const Key('video-runtime-account'),
      color: Colors.white.withValues(alpha: 0.82),
      child: const Row(
        children: <Widget>[
          RuntimeAvatar(seed: 'current-user', size: 60),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '当前用户',
                  style: TextStyle(
                    color: SocialColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '在线 · 完善资料后更容易遇见同频的人',
                  style: TextStyle(
                    color: SocialColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: SocialColors.textTertiary),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SocialCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: SocialColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: SocialColors.primary, size: 29),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 7),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 16),
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
}
