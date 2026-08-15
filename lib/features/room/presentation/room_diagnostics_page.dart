import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_audio_service.dart';

class RoomDiagnosticsPage extends StatefulWidget {
  const RoomDiagnosticsPage({required this.controller, super.key});

  final RoomController controller;

  @override
  State<RoomDiagnosticsPage> createState() => _RoomDiagnosticsPageState();
}

class _RoomDiagnosticsPageState extends State<RoomDiagnosticsPage> {
  RoomAudioService? _serviceInstance;
  RoomAudioService get _service => _serviceInstance!;
  RoomAudioSnapshot? _snapshot;
  bool _running = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serviceInstance != null) {
      return;
    }
    _serviceInstance = AppDependencyScope.of(context).roomAudioService;
    _run();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final RoomAudioSnapshot snapshot = await _service.inspect();
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final RoomAudioSnapshot? snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('房间质量诊断')),
      body: _running || snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: <Widget>[
                _DiagnosticHero(snapshot: snapshot),
                const SizedBox(height: 18),
                _DiagnosticRow(
                  label: '网络延迟',
                  value: snapshot.latencyMs == null
                      ? '未获取'
                      : '${snapshot.latencyMs} ms',
                  ok: snapshot.latencyMs != null && snapshot.latencyMs! < 180,
                ),
                _DiagnosticRow(
                  label: '丢包率',
                  value: snapshot.packetLossPercent == null
                      ? '未获取'
                      : '${snapshot.packetLossPercent!.toStringAsFixed(1)}%',
                  ok: snapshot.packetLossPercent != null &&
                      snapshot.packetLossPercent! < 5,
                ),
                _DiagnosticRow(
                  label: 'RTC 音频',
                  value: snapshot.rtcConnected ? '已连接' : '未连接',
                  ok: snapshot.rtcConnected,
                ),
                _DiagnosticRow(
                  label: '实时消息',
                  value: widget.controller.realtimeDegraded ||
                          !snapshot.realtimeConnected
                      ? '状态可能延迟'
                      : '已连接',
                  ok: !widget.controller.realtimeDegraded &&
                      snapshot.realtimeConnected,
                ),
                _DiagnosticRow(
                  label: '麦克风权限',
                  value: snapshot.microphonePermissionGranted
                      ? '已授权'
                      : '未授权',
                  ok: snapshot.microphonePermissionGranted,
                ),
                _DiagnosticRow(
                  label: '当前音频路由',
                  value: _routeLabel(snapshot.route),
                  ok: snapshot.configured,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.monitor_heart_rounded),
                  label: const Text('重新运行诊断'),
                ),
                const SizedBox(height: 12),
                Text(
                  snapshot.configured
                      ? '诊断结果仅用于定位当前设备和网络问题，不改变麦位或房间权限。'
                      : '当前构建尚未接入真实设备音频与 RTC 遥测，未知数据不会被显示为正常。',
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
}

class _DiagnosticHero extends StatelessWidget {
  const _DiagnosticHero({required this.snapshot});

  final RoomAudioSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final bool healthy = snapshot.configured &&
        snapshot.rtcConnected &&
        snapshot.realtimeConnected &&
        snapshot.grade != RoomConnectionGrade.poor;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: healthy
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            healthy
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            size: 38,
            color: healthy ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  healthy ? '当前房间质量正常' : '发现需要关注的项目',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '更新时间 ${_time(snapshot.updatedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _time(DateTime value) {
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    final String second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.label,
    required this.value,
    required this.ok,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(value),
          const SizedBox(width: 8),
          Icon(
            ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 18,
            color: ok ? AppColors.success : AppColors.warning,
          ),
        ],
      ),
    );
  }
}
