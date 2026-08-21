import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

class RoomPage extends StatelessWidget {
  const RoomPage({
    required this.roomId,
    required this.title,
    this.entrySource = RoomEntrySource.home,
    super.key,
  });

  final String roomId;
  final String title;
  final RoomEntrySource entrySource;

  @override
  Widget build(BuildContext context) {
    final String? inheritedFontFamily = Theme.of(
      context,
    ).textTheme.bodyMedium?.fontFamily;
    return Theme(
      data: AppTheme.room(fontFamily: inheritedFontFamily),
      child: _RoomPageRuntimeHost(
        roomId: roomId,
        title: title,
        entrySource: entrySource,
      ),
    );
  }
}

class _RoomPageRuntimeHost extends StatefulWidget {
  const _RoomPageRuntimeHost({
    required this.roomId,
    required this.title,
    required this.entrySource,
  });

  final String roomId;
  final String title;
  final RoomEntrySource entrySource;

  @override
  State<_RoomPageRuntimeHost> createState() => _RoomPageRuntimeHostState();
}

class _RoomPageRuntimeHostState extends State<_RoomPageRuntimeHost> {
  RoomController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= AppDependencyScope.of(
      context,
    ).createRoomController(roomId: widget.roomId, title: widget.title);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VideoRuntimeRoomPage(
      controller: _controller!,
      allowMinimize: false,
      entrySource: widget.entrySource,
    );
  }
}
