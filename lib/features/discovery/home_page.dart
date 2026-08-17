import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/home_room.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/shared/widgets/scoped_placeholder_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _rotation = 0;

  static const List<HomeRoom> _rooms = <HomeRoom>[
    HomeRoom(
      id: '880217',
      title: '深夜温柔陪伴',
      topic: '最近让你觉得被治愈的一件小事',
      listeners: 36,
      occupiedSeats: 3,
      friendReason: '你关注的晚星正在房间里',
      isSpeaking: true,
    ),
    HomeRoom(
      id: '660318',
      title: '下班后的松弛时刻',
      topic: '聊聊今天最想放下的一件事',
      listeners: 24,
      occupiedSeats: 5,
      friendReason: '与你常听的陪伴主题相似',
      isSpeaking: true,
    ),
    HomeRoom(
      id: '520906',
      title: '安静音乐电台',
      topic: '轻音乐与自由聊天，让夜晚慢下来',
      listeners: 18,
      occupiedSeats: 2,
      friendReason: '2 位好友正在收听',
      isSpeaking: false,
    ),
  ];

  List<HomeRoom> get _rotatedRooms => <HomeRoom>[
        for (int index = 0; index < _rooms.length; index += 1)
          _rooms[(index + _rotation) % _rooms.length],
      ];

  @override
  Widget build(BuildContext context) {
    final List<HomeRoom> rooms = _rotatedRooms;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF15112E),
            AppColors.background,
            AppColors.background,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              sliver: SliverToBoxAdapter(child: _buildHeader(context)),
            ),
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
                      onPressed: () => setState(
                        () => _rotation = (_rotation + 1) % _rooms.length,
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
                onTap: () => _openScopedPage(
                  pageId: 'DS-002',
                  title: '全局搜索',
                  description: '搜索房间、用户或房间号，并查看匹配结果。',
                ),
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
              onPressed: () => _openScopedPage(
                pageId: 'RM-001',
                title: '创建房间',
                description: '创建普通固定 8 麦房间，配置标题、主题、权限和公告。',
              ),
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
              onTap: () => _openScopedPage(
                pageId: 'DS-008',
                title: '收藏与我的房间',
                description: '查看收藏、创建、管理和最近进入的有效房间。',
              ),
            ),
            const Spacer(),
            Text(
              '按实时活跃度与关系推荐',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }

  void _enterRoom(HomeRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoomPage(
          roomId: room.id,
          title: room.title,
        ),
      ),
    );
  }

  void _openScopedPage({
    required String pageId,
    required String title,
    required String description,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ScopedPlaceholderPage(
          pageId: pageId,
          title: title,
          description: description,
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

  final HomeRoom room;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF31245D), Color(0xFF161A35)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.14),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
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
                  color: AppColors.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 16,
                      color: AppColors.success,
                    ),
                    SizedBox(width: 5),
                    Text(
                      '正在热聊',
                      style: TextStyle(color: AppColors.success),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text('${room.listeners} 人在线'),
            ],
          ),
          const SizedBox(height: 18),
          Text(room.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          Text(
            room.topic,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          _SeatSummary(occupiedSeats: room.occupiedSeats),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              const Icon(
                Icons.people_alt_rounded,
                size: 18,
                color: AppColors.accent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  room.friendReason,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton(onPressed: onEnter, child: const Text('进入房间')),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveRoomCard extends StatelessWidget {
  const _LiveRoomCard({required this.room, required this.onTap});

  final HomeRoom room;
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
                    Text(
                      room.title,
                      style: Theme.of(context).textTheme.titleMedium,
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
                      '${room.occupiedSeats}/8 麦 · ${room.listeners} 人在线 · ${room.friendReason}',
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
    return Row(
      children: <Widget>[
        for (int index = 0; index < 8; index += 1)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index < occupiedSeats
                    ? AppColors.primary.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.07),
                border: Border.all(
                  color: index < occupiedSeats
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Icon(
                index < occupiedSeats
                    ? Icons.person_rounded
                    : Icons.add_rounded,
                size: 13,
                color: index < occupiedSeats
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        const Spacer(),
        Text('$occupiedSeats/8 麦'),
      ],
    );
  }
}
