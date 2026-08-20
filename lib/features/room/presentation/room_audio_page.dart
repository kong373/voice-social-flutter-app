import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_audio_service.dart';

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
      appBar: AppBar(
        title: const Text('音频与麦克风'),
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: <Widget>[
                if (!snapshot.configured)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: RoomColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text('当前构建尚未接入设备音频能力，不会伪造路由切换或麦克风授权结果。'),
                  ),
                const SizedBox(height: 18),
                Text('播放设备', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                for (final RoomAudioRoute route in RoomAudioRoute.values)
                  ListTile(
                    leading: Icon(
                      snapshot.route == route
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: snapshot.route == route
                          ? RoomColors.primary
                          : null,
                    ),
                    title: Text(_routeLabel(route)),
                    subtitle: Text(_routeDescription(route)),
                    enabled:
                        snapshot.configured &&
                        snapshot.availableRoutes.contains(route),
                    onTap:
                        snapshot.configured &&
                            snapshot.availableRoutes.contains(route)
                        ? () => _selectRoute(route)
                        : null,
                  ),
                const Divider(height: 32),
                SwitchListTile(
                  value: snapshot.microphoneEnabled,
                  title: const Text('麦克风'),
                  subtitle: Text(
                    !widget.isOnMic
                        ? '上麦后才能打开麦克风'
                        : snapshot.microphonePermissionGranted
                        ? '用于在当前语音房发言'
                        : '需要系统麦克风权限',
                  ),
                  onChanged:
                      snapshot.configured &&
                          widget.isOnMic &&
                          snapshot.microphonePermissionGranted
                      ? _toggleMicrophone
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  '蓝牙或有线耳机不可用时，对应选项会禁用而不是静默切换。',
                  style: Theme.of(context).textTheme.bodySmall,
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
