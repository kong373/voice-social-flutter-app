import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';

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
  RoomController? _roomController;
  String? _roomTitle;
  bool _roomRouteOpen = false;

  List<Widget> get _pages => <Widget>[
    VideoRuntimeHomePage(
      dependencies: widget.dependencies,
      onOpenRoom: _openRoom,
    ),
    VideoRuntimeDiscoveryPage(dependencies: widget.dependencies),
    VideoRuntimeMessagesPage(dependencies: widget.dependencies),
    VideoRuntimeAccountPage(
      dependencies: widget.dependencies,
      onSignOut: widget.onSignOut,
    ),
  ];

  static const List<BottomNavigationBarItem> _items = <BottomNavigationBarItem>[
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
  void dispose() {
    _roomController?.dispose();
    super.dispose();
  }

  Future<void> _openRoom(DiscoveryRoom room) async {
    final RoomController? existing = _roomController;
    if (existing != null && existing.roomId != room.id) {
      await existing.leaveRoom();
      existing.dispose();
      _roomController = null;
    }
    _roomTitle = room.title;
    _roomController ??= widget.dependencies.createRoomController(
      roomId: room.id,
      title: room.title,
    );
    if (mounted) {
      setState(() {});
    }
    await _restoreRoom();
  }

  Future<void> _restoreRoom() async {
    final RoomController? controller = _roomController;
    if (controller == null || _roomRouteOpen || !mounted) {
      return;
    }
    _roomRouteOpen = true;
    final VideoRoomExit? result = await Navigator.of(context)
        .push<VideoRoomExit>(
          PageRouteBuilder<VideoRoomExit>(
            transitionDuration: const Duration(milliseconds: 260),
            reverseTransitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (_, Animation<double> animation, __) => FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: VideoRuntimeRoomPage(controller: controller),
            ),
          ),
        );
    _roomRouteOpen = false;
    if (!mounted) {
      return;
    }
    if (result == VideoRoomExit.ended ||
        controller.status == RoomSessionStatus.left ||
        controller.status == RoomSessionStatus.closed ||
        controller.status == RoomSessionStatus.kicked) {
      controller.dispose();
      _roomController = null;
      _roomTitle = null;
    }
    setState(() {});
  }

  Future<void> _closeMinimizedRoom() async {
    final RoomController? controller = _roomController;
    if (controller == null) {
      return;
    }
    await controller.leaveRoom();
    controller.dispose();
    if (!mounted) {
      return;
    }
    setState(() {
      _roomController = null;
      _roomTitle = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showMiniRoom = _roomController != null && !_roomRouteOpen;
    return Theme(
      data: AppTheme.social(),
      child: Scaffold(
        extendBody: true,
        backgroundColor: SocialColors.page,
        body: Stack(
          children: <Widget>[
            IndexedStack(index: _selectedIndex, children: _pages),
            if (showMiniRoom)
              Positioned(
                right: 14,
                bottom: 86,
                child: MinimizedRoomPill(
                  title: _roomTitle ?? _roomController!.displayTitle,
                  onRestore: _restoreRoom,
                  onClose: _closeMinimizedRoom,
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Color(0xFAFFFFFF),
            border: Border(top: BorderSide(color: SocialColors.divider)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x140F1A35),
                blurRadius: 22,
                offset: Offset(0, -8),
              ),
            ],
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
}
