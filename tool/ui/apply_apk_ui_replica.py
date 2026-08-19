#!/usr/bin/env python3
"""Apply the approved APK-inspired visual system to the Flutter client.

The script intentionally changes presentation only. Repository contracts,
route IDs, page count, business permissions, provider fail-closed adapters and
network behavior are left intact.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def write(relative: str, content: str) -> None:
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def replace(relative: str, old: str, new: str) -> None:
    path = ROOT / relative
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if old in text:
        path.write_text(text.replace(old, new), encoding="utf-8")


write(
    "lib/core/design_system/app_theme.dart",
    r'''
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color background = Color(0xFF070A19);
  static const Color backgroundRaised = Color(0xFF0B1027);
  static const Color surface = Color(0xFF11172F);
  static const Color surfaceHigh = Color(0xFF192142);
  static const Color surfaceMuted = Color(0xFF20284D);
  static const Color primary = Color(0xFF8D68FF);
  static const Color primaryBright = Color(0xFFA77CFF);
  static const Color primarySoft = Color(0x338D68FF);
  static const Color secondary = Color(0xFFFF70B7);
  static const Color secondarySoft = Color(0x33FF70B7);
  static const Color accent = Color(0xFF5FE0FF);
  static const Color gold = Color(0xFFFFC66D);
  static const Color textPrimary = Color(0xFFF8F6FF);
  static const Color textSecondary = Color(0xFFA8AEC9);
  static const Color textMuted = Color(0xFF737B9D);
  static const Color divider = Color(0xFF293154);
  static const Color glassStroke = Color(0x1FFFFFFF);
  static const Color success = Color(0xFF62E5A4);
  static const Color warning = Color(0xFFFFC56E);
  static const Color error = Color(0xFFFF667D);
  static const Color danger = Color(0xFFFF5573);
  static const Color roomGradientTop = Color(0xFF1D1642);
  static const Color roomGradientBottom = Color(0xFF090D20);
}

abstract final class AppTheme {
  static ThemeData dark() {
    const ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.divider,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.16,
        ),
        headlineSmall: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleSmall: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          height: 1.48,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          height: 1.48,
        ),
        bodySmall: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          height: 1.42,
        ),
        labelLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh.withValues(alpha: 0.82),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.glassStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: AppColors.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryBright,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: AppColors.textPrimary,
          backgroundColor: Colors.transparent,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: const Color(0xF20B1026),
        indicatorColor: AppColors.primary.withValues(alpha: 0.24),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        elevation: 0,
        backgroundColor: Color(0xF20B1026),
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textSecondary,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.divider,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.glassStroke),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.glassStroke),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.primary.withValues(alpha: 0.25),
        disabledColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        secondaryLabelStyle: const TextStyle(color: AppColors.textPrimary),
        side: const BorderSide(color: AppColors.glassStroke),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.7,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryBright,
        linearTrackColor: AppColors.surfaceHigh,
        circularTrackColor: AppColors.surfaceHigh,
      ),
    );
  }
}
''',
)

write(
    "lib/core/design_system/apk_visuals.dart",
    r'''
import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

class ApkPageBackground extends StatelessWidget {
  const ApkPageBackground({required this.child, super.key, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF171238),
            AppColors.backgroundRaised,
            AppColors.background,
          ],
          stops: <double>[0, 0.42, 1],
        ),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned(
            top: -110,
            right: -90,
            child: _GlowOrb(size: 250, color: AppColors.primary),
          ),
          const Positioned(
            top: 210,
            left: -130,
            child: _GlowOrb(size: 240, color: AppColors.secondary),
          ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );
  }
}

class ApkGlassCard extends StatelessWidget {
  const ApkGlassCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.radius = 22,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highlight
              ? <Color>[
                  AppColors.primary.withValues(alpha: 0.28),
                  AppColors.surface.withValues(alpha: 0.94),
                ]
              : <Color>[
                  AppColors.surfaceHigh.withValues(alpha: 0.88),
                  AppColors.surface.withValues(alpha: 0.96),
                ],
        ),
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.glassStroke),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) {
      return body;
    }
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: body,
      ),
    );
  }
}

class ApkSectionHeader extends StatelessWidget {
  const ApkSectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 3),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class ApkStatusPill extends StatelessWidget {
  const ApkStatusPill({
    required this.label,
    super.key,
    this.icon,
    this.color = AppColors.primary,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
''',
)

write(
    "lib/features/discovery/home_page.dart",
    r'''
import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/apk_visuals.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
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
  bool _loading = true;
  String? _error;
  int _rotation = 0;
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
      final List<DiscoveryRoom> rooms = await _repository.fetchHomeRooms();
      if (!mounted) {
        return;
      }
      setState(() {
        _rooms
          ..clear()
          ..addAll(rooms);
        _loading = false;
        _rotation = 0;
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

  List<DiscoveryRoom> get _visibleRooms {
    if (_rooms.isEmpty) {
      return const <DiscoveryRoom>[];
    }
    return <DiscoveryRoom>[
      for (int index = 0; index < _rooms.length; index += 1)
        _rooms[(index + _rotation) % _rooms.length],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final List<DiscoveryRoom> rooms = _visibleRooms;
    return ApkPageBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            key: const Key('home-room-discovery'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                sliver: SliverToBoxAdapter(child: _buildHeader()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                sliver: SliverToBoxAdapter(child: _buildCategories()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
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
                    child: ApkSectionHeader(
                      title: '正在发生',
                      subtitle: '听见此刻真实的声音',
                      action: TextButton.icon(
                        onPressed: rooms.length <= 1
                            ? null
                            : () => setState(() {
                                  _rotation = (_rotation + 1) % rooms.length;
                                }),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('换一批'),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  sliver: SliverToBoxAdapter(
                    child: _FeaturedRoomCard(
                      room: rooms.first,
                      onEnter: () => _enterRoom(rooms.first),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      '更多房间',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                  sliver: SliverList.separated(
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (BuildContext context, int index) {
                      final DiscoveryRoom room = rooms[index];
                      return _RoomListCard(
                        room: room,
                        index: index,
                        onTap: () => _enterRoom(room),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
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
    );
  }

  Widget _buildCategories() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final bool selected = index == _selectedCategory;
          return ChoiceChip(
            label: Text(_categories[index]),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => setState(() => _selectedCategory = index),
          );
        },
      ),
    );
  }

  Widget _buildShortcuts() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _ShortcutCard(
            icon: Icons.favorite_rounded,
            color: AppColors.secondary,
            title: '收藏与我的房间',
            subtitle: '快速回到常听房间',
            onTap: _openSavedRooms,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ShortcutCard(
            icon: Icons.emoji_events_rounded,
            color: AppColors.gold,
            title: '热门榜单',
            subtitle: '发现高人气房间',
            onTap: _openSearch,
          ),
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

class _FeaturedRoomCard extends StatelessWidget {
  const _FeaturedRoomCard({required this.room, required this.onEnter});

  final DiscoveryRoom room;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    return ApkGlassCard(
      highlight: true,
      padding: EdgeInsets.zero,
      onTap: onEnter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 150,
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF5A3FB1),
                  Color(0xFF22285A),
                  Color(0xFF101A38),
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
                _SeatDots(count: room.occupiedSeats),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    room.relationReason ?? '${room.occupiedSeats}/8 麦正在互动',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton(
                  onPressed: onEnter,
                  child: const Text('进入'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomListCard extends StatelessWidget {
  const _RoomListCard({
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
      const <Color>[Color(0xFF244A68), Color(0xFF161B38)],
      const <Color>[Color(0xFF673A6A), Color(0xFF1D1738)],
      const <Color>[Color(0xFF315060), Color(0xFF131B38)],
    ];
    final List<Color> gradient = gradients[index % gradients.length];
    return ApkGlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              room.isSpeaking
                  ? Icons.graphic_eq_rounded
                  : Icons.nightlight_round,
              size: 30,
              color: Colors.white.withValues(alpha: 0.9),
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
                const SizedBox(height: 9),
                Row(
                  children: <Widget>[
                    _SeatDots(count: room.occupiedSeats),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${room.occupiedSeats}/8 麦 · ${room.onlineCount} 人',
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

class _SeatDots extends StatelessWidget {
  const _SeatDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final int safeCount = count.clamp(0, 4);
    return SizedBox(
      width: 16.0 + safeCount * 13,
      height: 24,
      child: Stack(
        children: <Widget>[
          for (int index = 0; index < safeCount; index += 1)
            Positioned(
              left: index * 13,
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
                child: const Icon(Icons.person_rounded, size: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
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
      padding: const EdgeInsets.all(13),
      radius: 18,
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
        child: ApkGlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
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
''',
)

write(
    "lib/features/account/presentation/login_page.dart",
    r'''
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/design_system/apk_visuals.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/presentation/live_backend_readiness_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.controller,
    this.liveReadinessService,
    this.showLiveReadiness = false,
    super.key,
  });

  final AuthController controller;
  final LiveBackendReadinessService? liveReadinessService;
  final bool showLiveReadiness;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  Timer? _timer;
  int _secondsRemaining = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthController controller = widget.controller;
    final String? developmentCode = controller.developmentSmsCode;
    return Scaffold(
      body: ApkPageBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
            children: <Widget>[
              const _LoginBrand(),
              const SizedBox(height: 34),
              ApkGlassCard(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        '手机号登录',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '验证手机号后即可进入语音房，认识正在聊天的人。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        autofillHints: const <String>[
                          AutofillHints.telephoneNumber,
                        ],
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        decoration: const InputDecoration(
                          labelText: '手机号码',
                          prefixText: '+86  ',
                          prefixIcon: Icon(Icons.phone_iphone_rounded),
                        ),
                        validator: (String? value) {
                          final String phone = value?.trim() ?? '';
                          return RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)
                              ? null
                              : '请输入正确的手机号码';
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        autofillHints: const <String>[AutofillHints.oneTimeCode],
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          labelText: '短信验证码',
                          prefixIcon: const Icon(Icons.shield_outlined),
                          suffixIcon: TextButton(
                            onPressed:
                                controller.sendingCode || _secondsRemaining > 0
                                    ? null
                                    : _sendCode,
                            child: Text(
                              _secondsRemaining > 0
                                  ? '${_secondsRemaining}s'
                                  : controller.sendingCode
                                      ? '发送中'
                                      : '获取验证码',
                            ),
                          ),
                        ),
                        validator: (String? value) =>
                            (value?.trim().length ?? 0) == 6
                                ? null
                                : '请输入 6 位验证码',
                      ),
                      if (developmentCode != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _DevelopmentCodeNotice(code: developmentCode),
                      ],
                      if (controller.errorMessage != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _ErrorNotice(message: controller.errorMessage!),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: controller.busy ? null : _signIn,
                        child: controller.busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('登录 / 注册'),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '未注册手机号验证后将进入资料完善流程',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.showLiveReadiness &&
                  widget.liveReadinessService != null) ...<Widget>[
                const SizedBox(height: 14),
                TextButton.icon(
                  key: const Key('live-backend-readiness-entry'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          LiveBackendReadinessPage(
                        service: widget.liveReadinessService!,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.developer_mode_outlined),
                  label: const Text('开发环境联调诊断'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendCode() async {
    final String phone = _phoneController.text.trim();
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入正确的手机号码')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final bool sent = await widget.controller.sendSmsCode(phone);
    if (!mounted || !sent) {
      return;
    }
    final SmsChallenge? challenge = widget.controller.lastSmsChallenge;
    final String? developmentCode = challenge?.developmentCode;
    if (developmentCode != null) {
      _codeController.text = developmentCode;
      _codeController.selection = TextSelection.collapsed(
        offset: developmentCode.length,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          developmentCode == null
              ? '验证码已发送，请注意查收'
              : '开发环境验证码已填入',
        ),
      ),
    );
    _startCountdown(challenge?.retryAfter ?? 60);
  }

  void _startCountdown(int seconds) {
    setState(() => _secondsRemaining = seconds < 1 ? 1 : seconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining -= 1);
      }
    });
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.signInWithSms(
      phone: _phoneController.text,
      smsCode: _codeController.text,
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[AppColors.secondary, AppColors.primary],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Icon(Icons.graphic_eq_rounded, size: 38),
        ),
        const SizedBox(height: 18),
        Text('听见此刻', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          '在声音里相遇，在房间里陪伴',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _DevelopmentCodeNotice extends StatelessWidget {
  const _DevelopmentCodeNotice({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.science_outlined, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text('仅开发环境可见：验证码 $code')),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
''',
)

write(
    "lib/features/room/presentation/room_widgets.dart",
    r'''
part of 'room_page.dart';

class _RoomBackground extends StatelessWidget {
  const _RoomBackground();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                AppColors.roomGradientTop,
                Color(0xFF10152C),
                AppColors.roomGradientBottom,
              ],
              stops: <double>[0, 0.46, 1],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(
          top: -110,
          right: -90,
          child: _RoomGlow(size: 260, color: AppColors.primary),
        ),
        Positioned(
          top: 230,
          left: -145,
          child: _RoomGlow(size: 260, color: AppColors.secondary),
        ),
      ],
    );
  }
}

class _RoomGlow extends StatelessWidget {
  const _RoomGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicSeatTile extends StatelessWidget {
  const _MicSeatTile({required this.seat});

  final MicSeat seat;

  @override
  Widget build(BuildContext context) {
    final bool occupied = seat.userName != null;
    final Color ringColor = seat.isSpeaking
        ? AppColors.success
        : occupied
            ? AppColors.primaryBright
            : Colors.white.withValues(alpha: 0.16);
    final IconData stateIcon = switch (seat.state) {
      MicSeatState.locked => Icons.lock_rounded,
      MicSeatState.mutedAvailable => Icons.mic_off_rounded,
      MicSeatState.occupiedMuted => Icons.mic_off_rounded,
      MicSeatState.available => Icons.add_rounded,
      MicSeatState.occupied => Icons.mic_rounded,
    };

    return Semantics(
      label: '${seat.number} 号麦，${seat.userName ?? _seatStatus(seat.state)}',
      child: Column(
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: occupied
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            Color(0xFF383D72),
                            Color(0xFF1A2043),
                          ],
                        )
                      : null,
                  color: occupied
                      ? null
                      : Colors.white.withValues(alpha: 0.045),
                  border: Border.all(
                    color: ringColor,
                    width: seat.isSpeaking ? 3.2 : 1.5,
                  ),
                  boxShadow: seat.isSpeaking
                      ? <BoxShadow>[
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.34),
                            blurRadius: 22,
                            spreadRadius: 2,
                          ),
                        ]
                      : <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 7),
                          ),
                        ],
                ),
                child: Icon(
                  occupied ? Icons.person_rounded : stateIcon,
                  size: occupied ? 31 : 23,
                  color: occupied
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
              Positioned(
                left: -3,
                top: -3,
                child: Container(
                  width: 21,
                  height: 21,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.glassStroke),
                  ),
                  child: Text(
                    '${seat.number}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -1,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: seat.isSpeaking
                        ? AppColors.success
                        : AppColors.surfaceHigh,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                  child: Icon(
                    stateIcon,
                    size: 12,
                    color: seat.isSpeaking ? Colors.black : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            seat.userName ?? '${seat.number} 号麦',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: occupied
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: occupied ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }

  String _seatStatus(MicSeatState state) {
    return switch (state) {
      MicSeatState.available => '空闲',
      MicSeatState.locked => '已锁定',
      MicSeatState.mutedAvailable => '空麦且闭麦',
      MicSeatState.occupied => '已占用',
      MicSeatState.occupiedMuted => '已占用且闭麦',
    };
  }
}

class _RoomAction extends StatelessWidget {
  const _RoomAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: enabled
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          AppColors.primary.withValues(alpha: 0.34),
                          AppColors.surfaceHigh,
                        ],
                      )
                    : null,
                color: enabled ? null : Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppColors.glassStroke),
                boxShadow: enabled
                    ? <BoxShadow>[
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                size: 22,
                color: enabled ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.fromLTRB(18, 58, 18, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(999),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockingProgress extends StatelessWidget {
  const _BlockingProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.58),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassStroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteExitOverlay extends StatelessWidget {
  const _RemoteExitOverlay({
    required this.title,
    required this.message,
    required this.onExit,
  });

  final String title;
  final String message;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          width: 320,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[AppColors.surfaceHigh, AppColors.surface],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.glassStroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 32,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: onExit, child: const Text('返回首页')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''',
)

replace(
    "lib/features/room/presentation/room_page.dart",
    "正在获取房间状态并建立音频连接",
    "正在获取房间状态…",
)
replace(
    "lib/features/room/presentation/room_page.dart",
    "padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),",
    "padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),",
)
replace(
    "lib/features/room/presentation/room_page.dart",
    "height: 210,",
    "height: 220,",
)
replace(
    "lib/features/room/presentation/room_page.dart",
    "color: const Color(0xB20D1020),",
    "color: AppColors.surface.withValues(alpha: 0.82),",
)
replace(
    "lib/features/room/presentation/room_page.dart",
    "borderRadius: BorderRadius.circular(22),",
    "borderRadius: BorderRadius.circular(24),",
)

print("APK-inspired UI migration applied")
