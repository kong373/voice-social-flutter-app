import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';

class RoomDeepLinkPage extends StatefulWidget {
  const RoomDeepLinkPage({required this.input, super.key});

  final String input;

  @override
  State<RoomDeepLinkPage> createState() => _RoomDeepLinkPageState();
}

class _RoomDeepLinkPageState extends State<RoomDeepLinkPage> {
  final TextEditingController _controller = TextEditingController();
  RoomLifecycleRepository? _repositoryInstance;
  RoomLifecycleRepository get _repository => _repositoryInstance!;
  RoomLinkResolution? _resolution;
  bool _resolving = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.input;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance = AppDependencyScope.of(
      context,
    ).roomLifecycleRepository;
    _resolve();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() {
      _resolving = true;
      _error = null;
      _resolution = null;
    });
    try {
      final RoomLinkResolution resolution = await _repository.resolveRoomLink(
        _controller.text,
      );
      if (!mounted) {
        return;
      }
      if (resolution.canEnter) {
        final RoomConfiguration room = resolution.room!;
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => RoomPage(
              roomId: room.roomId ?? room.roomCode!,
              title: room.title,
              entrySource: RoomEntrySource.share,
            ),
          ),
        );
        return;
      }
      setState(() {
        _resolution = resolution;
        _resolving = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _resolving = false;
        _error = error is ApiException ? error.message : '房间链接校验失败，请检查网络后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return const RoomPageScaffold(body: SizedBox.expand());
    }
    final RoomLinkResolution? resolution = _resolution;
    final String title = switch (resolution?.status) {
      RoomLinkStatus.closed => '房间已经关闭',
      RoomLinkStatus.unavailable => '目标房间不可用',
      RoomLinkStatus.invalid => '房间链接无效',
      _ => '暂时无法进入房间',
    };
    final IconData icon = switch (resolution?.status) {
      RoomLinkStatus.closed => Icons.door_back_door_outlined,
      RoomLinkStatus.unavailable => Icons.block_rounded,
      RoomLinkStatus.invalid => Icons.link_off_rounded,
      _ => Icons.cloud_off_rounded,
    };
    return RoomPageScaffold(
      appBar: roomOxygenAppBar(title: '房间直达'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: RoomGlassCard(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Column(
                children: <Widget>[
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: RoomColors.warning.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: RoomColors.warning.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Icon(icon, size: 29, color: RoomColors.warning),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _error ?? resolution?.message ?? '请确认房间号后重试。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _resolve(),
                    decoration: const InputDecoration(
                      labelText: '房间号或完整链接',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _resolve,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重新校验'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回上一页'),
                  ),
                  const SizedBox(height: 10),
                  const RoomOxygenNotice(
                    icon: Icons.shield_outlined,
                    title: '安全校验',
                    message: '有效链接会直接进入房间；关闭、失效或不可用的目标不会进入中间页。',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
