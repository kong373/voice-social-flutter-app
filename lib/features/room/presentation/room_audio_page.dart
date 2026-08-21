import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_audio_service.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';

class RoomAudioPage extends StatefulWidget {
  const RoomAudioPage({required this.isOnMic, super.key});

  final bool isOnMic;

  @override
  State<RoomAudioPage> createState() => _RoomAudioPageState();
}

class _RoomAudioPageState extends State<RoomAudioPage> {
  RoomAudioService? _serviceInstance;
  RoomAudioService get _service => _serviceInstance!;
  RoomAudioSnapshot? _snapshot;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serviceInstance != null) {
      return;
    }
    _serviceInstance = AppDependencyScope.of(context).roomAudioService;
    _inspect();
  }

  Future<void> _inspect() async {
    setState(() => _loading = true);
    final RoomAudioSnapshot snapshot = await _service.inspect();
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _selectRoute(RoomAudioRoute route) async {
    final RoomAudioSnapshot snapshot = await _service.selectRoute(route);
    if (!mounted) {
      return;
    }
    setState(() => _snapshot = snapshot);
  }

  Future<void> _toggleMicrophone(bool enabled) async {
    final RoomAudioSnapshot snapshot = await _service.setMicrophoneEnabled(
      enabled,
    );
    if (!mounted) {
      return;
    }
    setState(() => _snapshot = snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final RoomAudioSnapshot? snapshot = _snapshot;
    return RoomPageScaffold(
      appBar: roomOxygenAppBar(
        title: '音频与麦克风',
        actions: <Widget>[
          IconButton(
            tooltip: '刷新设备状态',
            onPressed: _inspect,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading || snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: <Widget>[
                RoomOxygenContextBar(
                  title: '深夜温柔陪伴',
                  subtitle: widget.isOnMic ? '麦上发言中 · 音频控制' : '听众模式 · 音频控制',
                  status: widget.isOnMic ? '麦上' : '听众',
                  statusColor: widget.isOnMic
                      ? RoomColors.success
                      : RoomColors.accent,
                ),
                const SizedBox(height: 14),
                if (!snapshot.configured)
                  const RoomOxygenNotice(
                    icon: Icons.info_outline_rounded,
                    title: '音频能力未配置',
                    message: '当前构建不会伪造路由切换或麦克风授权结果。',
                    accent: RoomColors.warning,
                  ),
                if (!snapshot.configured) const SizedBox(height: 14),
                RoomOxygenSection(
                  title: '播放设备',
                  subtitle: '只展示当前设备真实可用的音频路由。',
                  icon: Icons.speaker_group_outlined,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      for (final RoomAudioRoute route in RoomAudioRoute.values)
                        ListTile(
                          leading: Icon(
                            snapshot.route == route
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: snapshot.route == route
                                ? RoomColors.accent
                                : null,
                          ),
                          title: Text(_routeLabel(route)),
                          subtitle: Text(_routeDescription(route)),
                          trailing: snapshot.route == route
                              ? const RoomOxygenPill(
                                  label: '当前',
                                  active: true,
                                  accent: RoomColors.accent,
                                )
                              : null,
                          enabled:
                              snapshot.configured &&
                              snapshot.availableRoutes.contains(route),
                          onTap:
                              snapshot.configured &&
                                  snapshot.availableRoutes.contains(route)
                              ? () => _selectRoute(route)
                              : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                RoomOxygenSection(
                  title: '麦克风',
                  subtitle: !widget.isOnMic
                      ? '上麦后才能打开麦克风。'
                      : snapshot.microphonePermissionGranted
                      ? '用于在当前语音房发言。'
                      : '需要系统麦克风权限。',
                  icon: Icons.mic_none_rounded,
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    value: snapshot.microphoneEnabled,
                    title: Text(snapshot.microphoneEnabled ? '已打开' : '已关闭'),
                    subtitle: const Text('状态仅作用于当前房间会话'),
                    onChanged:
                        snapshot.configured &&
                            widget.isOnMic &&
                            snapshot.microphonePermissionGranted
                        ? _toggleMicrophone
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                const RoomOxygenNotice(
                  icon: Icons.headphones_rounded,
                  message: '蓝牙或有线耳机不可用时，对应选项会禁用，不会静默切换。',
                ),
              ],
            ),
    );
  }

  static String _routeLabel(RoomAudioRoute route) {
    return switch (route) {
      RoomAudioRoute.speaker => '扬声器',
      RoomAudioRoute.earpiece => '听筒',
      RoomAudioRoute.bluetooth => '蓝牙设备',
      RoomAudioRoute.wiredHeadset => '有线耳机',
    };
  }

  static String _routeDescription(RoomAudioRoute route) {
    return switch (route) {
      RoomAudioRoute.speaker => '外放收听，适合安静环境',
      RoomAudioRoute.earpiece => '贴近耳朵收听，降低外放声音',
      RoomAudioRoute.bluetooth => '使用已连接的蓝牙耳机或音箱',
      RoomAudioRoute.wiredHeadset => '使用已连接的有线耳机',
    };
  }
}
