import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
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
  bool _roomOpenInFlight = false;
  DiscoveryRoom? _pendingRoom;

  List<Widget> get _pages {
    return <Widget>[
      VideoRuntimeHomePage(
        dependencies: widget.dependencies,
        onOpenRoom: _openRoom,
      ),
      VideoRuntimeDiscoveryPage(dependencies: widget.dependencies),
      VideoRuntimeMessagesPage(dependencies: widget.dependencies),
      VideoRuntimeAccountPage(
        dependencies: widget.dependencies,
        onOpenRoom: _openRoom,
        onSignOut: widget.onSignOut,
      ),
    ];
  }

  @override
  void dispose() {
    _roomController?.dispose();
    super.dispose();
  }

  Future<void> _openRoom(DiscoveryRoom room) async {
    if (widget.dependencies.environment.isLive) {
      if (_roomRouteOpen) {
        _pendingRoom = room;
        return;
      }
      await _openLiveRoom(room);
      return;
    }
    _pendingRoom = room;
    if (_roomRouteOpen || !mounted) {
      return;
    }
    await _drainRoomRequests();
  }

  Future<void> _openLiveRoom(DiscoveryRoom room) async {
    if (!mounted) {
      return;
    }
    _roomRouteOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AppDependencyScope(
            dependencies: widget.dependencies,
            child: RoomPage(
              roomId: room.id,
              title: room.title,
              entrySource: RoomEntrySource.home,
            ),
          ),
        ),
      );
    } finally {
      _roomRouteOpen = false;
    }
    if (!mounted || _pendingRoom == null) {
      return;
    }
    final DiscoveryRoom nextRoom = _pendingRoom!;
    _pendingRoom = null;
    await _openLiveRoom(nextRoom);
  }

  Future<void> _restoreRoom() async {
    final RoomController? controller = _roomController;
    if (controller == null || _roomRouteOpen || !mounted) {
      return;
    }
    _roomRouteOpen = true;
    final VideoRoomExit? result;
    try {
      result = await Navigator.of(context).push<VideoRoomExit>(
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
    } finally {
      _roomRouteOpen = false;
    }
    if (!mounted) {
      return;
    }
    // A pending room may have been requested while this route was open. The
    // route's controller owns the result, so never clear a newer controller.
    if (_roomController == controller &&
        (result == VideoRoomExit.ended ||
            controller.status == RoomSessionStatus.left ||
            controller.status == RoomSessionStatus.closed ||
            controller.status == RoomSessionStatus.kicked)) {
      controller.dispose();
      _roomController = null;
      _roomTitle = null;
    }
    setState(() {});
    if (!_roomOpenInFlight) {
      await _drainRoomRequests();
    }
  }

  Future<void> _closeMinimizedRoom() async {
    final RoomController? controller = _roomController;
    if (controller == null) {
      return;
    }
    final bool left = await controller.leaveRoom();
    if (!mounted) {
      return;
    }
    // Keep the pill and its controller when the server rejected the leave.
    if (!left || _roomController != controller) {
      return;
    }
    controller.dispose();
    setState(() {
      _roomController = null;
      _roomTitle = null;
    });
  }

  Future<void> _drainRoomRequests() async {
    if (_roomOpenInFlight || !mounted) {
      return;
    }
    _roomOpenInFlight = true;
    try {
      while (mounted && _pendingRoom != null) {
        if (_roomRouteOpen) {
          return;
        }
        DiscoveryRoom room = _pendingRoom!;
        _pendingRoom = null;
        final RoomController? existing = _roomController;
        if (existing != null && existing.roomId != room.id) {
          final bool left = await existing.leaveRoom();
          if (!mounted || _roomController != existing) {
            return;
          }
          if (!left) {
            // A failed leave is recoverable from the currently displayed pill;
            // do not replace it with a controller that cannot be entered.
            return;
          }
          existing.dispose();
          _roomController = null;
          _roomTitle = null;
          // A newer request may have arrived while the previous controller
          // was leaving. Skip the stale intermediate room.
          if (_pendingRoom != null) {
            room = _pendingRoom!;
            _pendingRoom = null;
          }
        }
        if (_roomController == null) {
          _roomController = widget.dependencies.createRoomController(
            roomId: room.id,
            title: room.title,
          );
        }
        _roomTitle = room.title;
        if (mounted) {
          setState(() {});
        }
        await _restoreRoom();
      }
    } finally {
      _roomOpenInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showMiniRoom = _roomController != null && !_roomRouteOpen;
    final String? inheritedFontFamily = Theme.of(
      context,
    ).textTheme.bodyMedium?.fontFamily;
    return Theme(
      data: AppTheme.social(fontFamily: inheritedFontFamily),
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
        bottomNavigationBar: _VideoNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (int index) => setState(() => _selectedIndex = index),
        ),
      ),
    );
  }
}

class _VideoNavigationBar extends StatelessWidget {
  const _VideoNavigationBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<(IconData, IconData, String, Color)> _items =
      <(IconData, IconData, String, Color)>[
        (Icons.home_outlined, Icons.home_rounded, '首页', Color(0xFFFFB45F)),
        (
          Icons.explore_outlined,
          Icons.explore_rounded,
          '发现',
          Color(0xFF8A7BF6),
        ),
        (
          Icons.chat_bubble_outline_rounded,
          Icons.chat_bubble_rounded,
          '消息',
          Color(0xFF68B7F6),
        ),
        (
          Icons.person_outline_rounded,
          Icons.person_rounded,
          '我的',
          Color(0xFF9D82F4),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFAFFFFFF),
        border: Border(top: BorderSide(color: Color(0x91FFFFFF))),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x160F1A35),
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: <Widget>[
              for (int index = 0; index < _items.length; index += 1)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(index),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5, bottom: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: currentIndex == index ? 42 : 34,
                            height: 28,
                            decoration: BoxDecoration(
                              color: currentIndex == index
                                  ? _items[index].$4.withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Icon(
                              currentIndex == index
                                  ? _items[index].$2
                                  : _items[index].$1,
                              size: 23,
                              color: currentIndex == index
                                  ? _items[index].$4
                                  : SocialColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _items[index].$3,
                            style: TextStyle(
                              color: currentIndex == index
                                  ? SocialColors.textPrimary
                                  : SocialColors.textTertiary,
                              fontSize: 10,
                              fontWeight: currentIndex == index
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
