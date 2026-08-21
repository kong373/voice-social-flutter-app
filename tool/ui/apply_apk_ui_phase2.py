#!/usr/bin/env python3
"""Install the APK-inspired live shell without changing business contracts."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def write(relative: str, content: str) -> None:
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


write(
    "lib/features/shell/apk_live_pages.dart",
    r'''
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/apk_visuals.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';
import 'package:voice_social_app/features/shell/live_vendor_boundary_page.dart';

class ApkLiveHomePage extends StatefulWidget {
  const ApkLiveHomePage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<ApkLiveHomePage> createState() => _ApkLiveHomePageState();
}

class _ApkLiveHomePageState extends State<ApkLiveHomePage> {
  List<DiscoveryRoom> _rooms = const <DiscoveryRoom>[];
  bool _loading = true;
  String? _error;
  int _selectedCategory = 0;

  static const List<String> _categories = <String>[
    '推荐',
    '交友',
    '情感',
    '游戏',
    '电台',
    '音乐',
  ];

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
      final List<DiscoveryRoom> rooms =
          await widget.dependencies.discoveryRepository.fetchHomeRooms();
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

  void _openRoom(DiscoveryRoom room) {
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

  @override
  Widget build(BuildContext context) {
    return ApkPageBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: const Key('live-home-ready'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
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
                    tooltip: '搜索',
                    onPressed: _openSearch,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int index) {
                    return ChoiceChip(
                      label: Text(_categories[index]),
                      selected: index == _selectedCategory,
                      showCheckmark: false,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = index),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _LiveShortcut(
                      icon: Icons.favorite_rounded,
                      color: AppColors.secondary,
                      title: '收藏房间',
                      subtitle: '回到常听的声音',
                      onTap: _openSearch,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LiveShortcut(
                      icon: Icons.emoji_events_rounded,
                      color: AppColors.gold,
                      title: '热门榜单',
                      subtitle: '发现高人气房间',
                      onTap: _openSearch,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const ApkSectionHeader(
                title: '正在发生',
                subtitle: '听见此刻真实的声音',
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 72),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _LiveStateCard(
                  icon: Icons.cloud_off_outlined,
                  title: '房间列表加载失败',
                  description: _error!,
                  actionLabel: '重新加载',
                  onAction: _load,
                )
              else if (_rooms.isEmpty)
                _LiveStateCard(
                  icon: Icons.headphones_outlined,
                  title: '暂时没有开放的房间',
                  description: '稍后再来看看，或下拉刷新房间列表。',
                  actionLabel: '刷新',
                  onAction: _load,
                )
              else ...<Widget>[
                _LiveFeaturedRoom(
                  room: _rooms.first,
                  onTap: () => _openRoom(_rooms.first),
                ),
                const SizedBox(height: 18),
                for (int index = 0; index < _rooms.length; index += 1) ...<Widget>[
                  _LiveRoomCard(
                    room: _rooms[index],
                    index: index,
                    onTap: () => _openRoom(_rooms[index]),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ApkLiveDiscoverPage extends StatelessWidget {
  const ApkLiveDiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ApkPageBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('live-discover-page'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('发现', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  tooltip: '发布动态',
                  onPressed: null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Row(
              children: <Widget>[
                ApkStatusPill(label: '关注', color: AppColors.primary),
                SizedBox(width: 8),
                ApkStatusPill(label: '推荐', color: AppColors.secondary),
                SizedBox(width: 8),
                ApkStatusPill(label: '最新', color: AppColors.accent),
              ],
            ),
            const SizedBox(height: 22),
            ApkGlassCard(
              key: const Key('live-discovery-unavailable'),
              highlight: true,
              child: Column(
                children: <Widget>[
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.dynamic_feed_outlined,
                      size: 32,
                      color: AppColors.primaryBright,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '发现内容正在准备',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '动态服务接入后，会在这里展示关注内容、热门话题和实时房间动态。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 18),
                  const ApkStatusPill(
                    label: '首页房间与搜索仍可使用',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ApkLiveMessagesPage extends StatelessWidget {
  const ApkLiveMessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ApkPageBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('live-messages-page'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('消息', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  tooltip: '消息设置',
                  onPressed: null,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Row(
              children: <Widget>[
                Expanded(child: _MessageCategory(icon: Icons.person_add_alt_1_rounded, label: '好友请求')),
                SizedBox(width: 10),
                Expanded(child: _MessageCategory(icon: Icons.favorite_outline_rounded, label: '互动通知')),
                SizedBox(width: 10),
                Expanded(child: _MessageCategory(icon: Icons.campaign_outlined, label: '系统通知')),
              ],
            ),
            const SizedBox(height: 22),
            ApkGlassCard(
              key: const Key('im-vendor-blocked'),
              child: Column(
                children: <Widget>[
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.forum_outlined,
                      size: 32,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '消息服务正在准备',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当前不会伪造会话或消息。腾讯 IM 服务启用后，真实私聊、群聊与互动通知会显示在这里。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ApkLiveAccountPage extends StatefulWidget {
  const ApkLiveAccountPage({
    required this.dependencies,
    required this.onSignOut,
    super.key,
  });

  final AppDependencies dependencies;
  final Future<void> Function() onSignOut;

  @override
  State<ApkLiveAccountPage> createState() => _ApkLiveAccountPageState();
}

class _ApkLiveAccountPageState extends State<ApkLiveAccountPage> {
  LiveReadOnlyOverview? _overview;
  String? _error;
  bool _loading = true;
  bool _signingOut = false;

  bool get _showDeveloperReadiness =>
      kDebugMode &&
      widget.dependencies.environment.deploymentEnvironment
          .allowsDevelopmentTools;

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
      final LiveReadOnlyOverview overview =
          await widget.dependencies.liveReadOnlyRepository.fetchOverview();
      if (!mounted) {
        return;
      }
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '账号信息暂时无法加载';
      });
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }
    setState(() => _signingOut = true);
    try {
      await widget.onSignOut();
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  void _openDeveloperReadiness() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => Scaffold(
          appBar: AppBar(title: const Text('开发接入状态')),
          body: LiveVendorBoundaryPage(dependencies: widget.dependencies),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LiveReadOnlyOverview? overview = _overview;
    return ApkPageBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: const Key('live-account-page'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('我的', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  IconButton(
                    tooltip: '设置',
                    onPressed: null,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 72),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _LiveStateCard(
                  icon: Icons.cloud_off_outlined,
                  title: '账号信息加载失败',
                  description: _error!,
                  actionLabel: '重新加载',
                  onAction: _load,
                )
              else if (overview != null) ...<Widget>[
                _ProfileHero(user: overview.user),
                const SizedBox(height: 14),
                _WalletOverview(wallet: overview.wallet),
                const SizedBox(height: 18),
                const _AccountShortcuts(),
                const SizedBox(height: 22),
                ApkSectionHeader(
                  title: '最近订单',
                  action: TextButton(onPressed: null, child: const Text('全部')),
                ),
                const SizedBox(height: 10),
                if (overview.orders.isEmpty)
                  const ApkGlassCard(
                    child: _EmptyOrderState(),
                  )
                else
                  for (final LivePaymentOrder order in overview.orders) ...<Widget>[
                    _OrderCard(order: order),
                    const SizedBox(height: 10),
                  ],
                ApkGlassCard(
                  key: const Key('payment-initiation-blocked'),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.lock_outline_rounded,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '充值服务暂时不可用',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '当前可以查看余额与历史订单',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showDeveloperReadiness) ...<Widget>[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    key: const Key('developer-vendor-readiness'),
                    onPressed: _openDeveloperReadiness,
                    icon: const Icon(Icons.developer_mode_outlined),
                    label: const Text('开发接入状态'),
                  ),
                ],
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _signingOut ? null : _signOut,
                icon: _signingOut
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: const Text('退出登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveFeaturedRoom extends StatelessWidget {
  const _LiveFeaturedRoom({required this.room, required this.onTap});

  final DiscoveryRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ApkGlassCard(
      key: Key('live-room-${room.id}'),
      padding: EdgeInsets.zero,
      highlight: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 145,
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF5E45B6),
                  Color(0xFF2A2E66),
                  Color(0xFF14203F),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ApkStatusPill(
                      label: room.isSpeaking ? '正在热聊' : '正在收听',
                      icon: room.isSpeaking
                          ? Icons.graphic_eq_rounded
                          : Icons.headphones_rounded,
                      color: AppColors.success,
                    ),
                    const Spacer(),
                    Text('${room.onlineCount} 人在线'),
                  ],
                ),
                const Spacer(),
                Text(room.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  room.topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                _MiniSeatStack(count: room.occupiedSeats),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${room.occupiedSeats}/8 麦正在互动',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton(onPressed: onTap, child: const Text('进入')),
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
    final List<List<Color>> gradients = <List<Color>>[
      const <Color>[Color(0xFF4C3D91), Color(0xFF172044)],
      const <Color>[Color(0xFF22506A), Color(0xFF161B38)],
      const <Color>[Color(0xFF663A6A), Color(0xFF1D1738)],
    ];
    return ApkGlassCard(
      key: Key('live-room-${room.id}'),
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradients[index % gradients.length],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              room.isSpeaking
                  ? Icons.graphic_eq_rounded
                  : Icons.headphones_rounded,
              size: 29,
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
                      const Icon(Icons.lock_outline_rounded, size: 17),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  room.topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    _MiniSeatStack(count: room.occupiedSeats),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${room.onlineCount} 人在线',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
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

class _LiveShortcut extends StatelessWidget {
  const _LiveShortcut({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ApkGlassCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
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
      ),
    );
  }
}

class _MiniSeatStack extends StatelessWidget {
  const _MiniSeatStack({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final int safeCount = count.clamp(0, 4).toInt();
    return SizedBox(
      width: 18.0 + safeCount * 12,
      height: 24,
      child: Stack(
        children: <Widget>[
          for (int index = 0; index < safeCount; index += 1)
            Positioned(
              left: index * 12,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: index.isEven
                        ? const <Color>[AppColors.primary, AppColors.secondary]
                        : const <Color>[AppColors.accent, AppColors.primary],
                  ),
                  border: Border.all(color: AppColors.background, width: 2),
                ),
                child: const Icon(Icons.person_rounded, size: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageCategory extends StatelessWidget {
  const _MessageCategory({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ApkGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      radius: 18,
      child: Column(
        children: <Widget>[
          Icon(icon, color: AppColors.primaryBright),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.user});

  final LiveCurrentUser user;

  @override
  Widget build(BuildContext context) {
    return ApkGlassCard(
      key: const Key('current-user-contract-ready'),
      highlight: true,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 66,
                height: 66,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[AppColors.secondary, AppColors.primary],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: Text(
                  user.nickname.isEmpty
                      ? '?'
                      : String.fromCharCode(user.nickname.runes.first),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      user.nickname,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text('用户号 ${user.account}'),
                    if (user.mobile.isNotEmpty)
                      Text(
                        user.mobile,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          const SizedBox(height: 18),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _ProfileMetric(value: '—', label: '关注'),
              _ProfileMetric(value: '—', label: '粉丝'),
              _ProfileMetric(value: '—', label: '好友'),
              _ProfileMetric(value: '—', label: '访客'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _WalletOverview extends StatelessWidget {
  const _WalletOverview({required this.wallet});

  final LiveWalletSnapshot wallet;

  @override
  Widget build(BuildContext context) {
    return ApkGlassCard(
      key: const Key('wallet-contract-ready'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('钱包', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: <Widget>[
              Expanded(
                child: _WalletMetric(
                  label: '礼物币',
                  value: '${wallet.giftCoinBalance}',
                  color: AppColors.gold,
                ),
              ),
              Expanded(
                child: _WalletMetric(
                  label: '现金余额',
                  value: '¥${wallet.cashBalance.toStringAsFixed(2)}',
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: _WalletMetric(
                  label: '冻结金额',
                  value: '¥${wallet.frozenBalance.toStringAsFixed(2)}',
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletMetric extends StatelessWidget {
  const _WalletMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _AccountShortcuts extends StatelessWidget {
  const _AccountShortcuts();

  @override
  Widget build(BuildContext context) {
    return ApkGlassCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _AccountShortcut(icon: Icons.meeting_room_outlined, label: '我的房间'),
          _AccountShortcut(icon: Icons.verified_user_outlined, label: '守护中心'),
          _AccountShortcut(icon: Icons.groups_2_outlined, label: '公会中心'),
          _AccountShortcut(icon: Icons.backpack_outlined, label: '道具背包'),
        ],
      ),
    );
  }
}

class _AccountShortcut extends StatelessWidget {
  const _AccountShortcut({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 66,
      child: Column(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primaryBright, size: 21),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final LivePaymentOrder order;

  @override
  Widget build(BuildContext context) {
    return ApkGlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.toll_rounded, color: AppColors.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(order.orderNo, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '${order.channelName} · ${_statusLabel(order.status)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '¥${order.amount.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.gold,
                ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrderState extends StatelessWidget {
  const _EmptyOrderState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Icon(
          Icons.receipt_long_outlined,
          size: 36,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 10),
        Text('暂无订单', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('完成充值后，订单记录会显示在这里。',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _LiveStateCard extends StatelessWidget {
  const _LiveStateCard({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return ApkGlassCard(
      child: Column(
        children: <Widget>[
          Icon(icon, size: 44, color: AppColors.textSecondary),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
      'SUCCEEDED' => '支付成功',
      'CONFIRMING' => '确认中',
      'FAILED' => '支付失败',
      'CANCELLED' => '已取消',
      _ => '状态更新中',
    };
''',
)

write(
    "lib/features/shell/main_shell.dart",
    r'''
import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/shell/apk_live_pages.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    required this.dependencies,
    required this.onSignOut,
    super.key,
  });

  final AppDependencies dependencies;
  final Future<void> Function() onSignOut;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  List<Widget> get _pages {
    if (widget.dependencies.environment.isLive) {
      return <Widget>[
        ApkLiveHomePage(dependencies: widget.dependencies),
        const ApkLiveDiscoverPage(),
        const ApkLiveMessagesPage(),
        ApkLiveAccountPage(
          dependencies: widget.dependencies,
          onSignOut: widget.onSignOut,
        ),
      ];
    }
    return <Widget>[
      const HomePage(),
      const DiscoveryFeedPage(),
      const MessageCenterPage(),
      PersonalCenterPage(
        session: widget.dependencies.sessionManager.session,
        onSignOut: widget.onSignOut,
      ),
    ];
  }

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: '首页',
    ),
    NavigationDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore_rounded),
      label: '发现',
    ),
    NavigationDestination(
      icon: Icon(Icons.chat_bubble_outline_rounded),
      selectedIcon: Icon(Icons.chat_bubble_rounded),
      label: '消息',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xF20B1026),
          border: const Border(
            top: BorderSide(color: AppColors.glassStroke),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            setState(() => _selectedIndex = index);
          },
          destinations: _destinations,
        ),
      ),
    );
  }
}
''',
)

print('APK live shell migration applied')
