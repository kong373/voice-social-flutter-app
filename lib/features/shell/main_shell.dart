import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/video_ui_components.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/room/application/room_session_coordinator.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/shell/live_read_only_pages.dart';
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
  final RoomSessionCoordinator _roomSession = RoomSessionCoordinator.instance;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _roomSession.addListener(_handleRoomSessionChanged);
  }

  @override
  void dispose() {
    _roomSession.removeListener(_handleRoomSessionChanged);
    super.dispose();
  }

  void _handleRoomSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<Widget> get _pages {
    if (widget.dependencies.environment.isLive) {
      return <Widget>[
        const HomePage(),
        const LiveDiscoveryHoldingPage(),
        const LiveMessageHoldingPage(),
        LiveReadOnlyAccountPage(
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

  static const List<BottomNavigationBarItem> _items =
      <BottomNavigationBarItem>[
    BottomNavigationBarItem(
      icon: Icon(Icons.home_outlined),
      activeIcon: Icon(Icons.home_rounded),
      label: '首页',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.explore_outlined),
      activeIcon: Icon(Icons.explore_rounded),
      label: '发现',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.chat_bubble_outline_rounded),
      activeIcon: Icon(Icons.chat_bubble_rounded),
      label: '消息',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.person_outline_rounded),
      activeIcon: Icon(Icons.person_rounded),
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LobbyTheme(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: IndexedStack(index: _selectedIndex, children: _pages),
            ),
            if (_roomSession.isMinimized)
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: _MinimizedRoomPill(
                  title: _roomSession.title ?? '正在收听的房间',
                  onRestore: _restoreRoom,
                  onLeave: _leaveMinimizedRoom,
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.lobbyDivider)),
          ),
          child: SafeArea(
            top: false,
            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (int index) => setState(() => _selectedIndex = index),
              items: _items,
            ),
          ),
        ),
      ),
    );
  }

  void _restoreRoom() {
    final String? roomId = _roomSession.roomId;
    final String? title = _roomSession.title;
    if (roomId == null || title == null) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RoomPage(
          roomId: roomId,
          title: title,
          entrySource: RoomEntrySource.home,
        ),
      ),
    );
  }

  Future<void> _leaveMinimizedRoom() async {
    await _roomSession.leaveMinimizedSession();
  }
}

class _MinimizedRoomPill extends StatelessWidget {
  const _MinimizedRoomPill({
    required this.title,
    required this.onRestore,
    required this.onLeave,
  });

  final String title;
  final VoidCallback onRestore;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('minimized-room-pill'),
        onTap: onRestore,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 58,
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF342A78), Color(0xFF171A40)],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF4C3F9A).withValues(alpha: 0.34),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              ColorAvatar(seed: title, size: 44, ringColor: AppColors.accent),
              const SizedBox(width: 10),
              const VoiceWave(width: 34),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      '房间仍在继续 · 点击恢复',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '离开房间',
                onPressed: onLeave,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
