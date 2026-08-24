import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_audio_service.dart';
import 'package:voice_social_app/features/room/presentation/room_authority_display.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';

class RoomDiagnosticsPage extends StatefulWidget {
  const RoomDiagnosticsPage({
    required this.controller,
    this.roomTitle,
    super.key,
  });

  final RoomController controller;
  final String? roomTitle;

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
    return RoomPageScaffold(
      appBar: roomOxygenAppBar(title: '房间质量诊断'),
      body: _running || snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: <Widget>[
                RoomOxygenContextBar(
                  title: roomAuthorityTitle(
                    widget.controller.snapshot?.title ?? widget.roomTitle,
                  ),
                  subtitle: '只读诊断 · 不改变麦位和权限',
                  seed: widget.controller.roomId,
                  status: snapshot.configured ? '已采样' : '未配置',
                  statusColor: snapshot.configured
                      ? RoomColors.success
                      : RoomColors.warning,
                ),
                const SizedBox(height: 14),
                _DiagnosticHero(snapshot: snapshot),
                const SizedBox(height: 16),
                RoomOxygenSection(
                  title: '实时采样',
                  subtitle: '本次结果只用于定位当前设备与网络问题。',
                  icon: Icons.monitor_heart_outlined,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: Column(
                    children: <Widget>[
                      _DiagnosticRow(
                        label: '网络延迟',
                        value: snapshot.latencyMs == null
                            ? '未获取'
                            : '${snapshot.latencyMs} ms',
                        ok:
                            snapshot.latencyMs != null &&
                            snapshot.latencyMs! < 180,
                      ),
                      const Divider(height: 1),
                      _DiagnosticRow(
                        label: '丢包率',
                        value: snapshot.packetLossPercent == null
                            ? '未获取'
                            : '${snapshot.packetLossPercent!.toStringAsFixed(1)}%',
                        ok:
                            snapshot.packetLossPercent != null &&
                            snapshot.packetLossPercent! < 5,
                      ),
                      const Divider(height: 1),
                      _DiagnosticRow(
                        label: 'RTC 音频',
                        value: snapshot.rtcConnected ? '已连接' : '未连接',
                        ok: snapshot.rtcConnected,
                      ),
                      const Divider(height: 1),
                      _DiagnosticRow(
                        label: '实时消息',
                        value:
                            widget.controller.realtimeDegraded ||
                                !snapshot.realtimeConnected
                            ? '状态可能延迟'
                            : '已连接',
                        ok:
                            !widget.controller.realtimeDegraded &&
                            snapshot.realtimeConnected,
                      ),
                      const Divider(height: 1),
                      _DiagnosticRow(
                        label: '麦克风权限',
                        value: snapshot.microphonePermissionGranted
                            ? '已授权'
                            : '未授权',
                        ok: snapshot.microphonePermissionGranted,
                      ),
                      const Divider(height: 1),
                      _DiagnosticRow(
                        label: '当前音频路由',
                        value: _routeLabel(snapshot.route),
                        ok: snapshot.configured,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _run,
                    icon: const Icon(Icons.monitor_heart_rounded),
                    label: const Text('重新运行诊断'),
                  ),
                ),
                const SizedBox(height: 12),
                RoomOxygenNotice(
                  icon: Icons.shield_outlined,
                  message: snapshot.configured
                      ? '诊断结果不会改变麦位或房间权限。'
                      : '真实设备音频与 RTC 遥测未接入，未知数据不会显示为正常。',
                  accent: snapshot.configured
                      ? RoomColors.accent
                      : RoomColors.warning,
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
    final bool healthy =
        snapshot.configured &&
        snapshot.rtcConnected &&
        snapshot.realtimeConnected &&
        snapshot.grade != RoomConnectionGrade.poor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: healthy
            ? RoomColors.success.withValues(alpha: 0.1)
            : RoomColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: (healthy ? RoomColors.success : RoomColors.warning).withValues(
            alpha: 0.2,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            healthy
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            size: 30,
            color: healthy ? RoomColors.success : RoomColors.warning,
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
    return RoomOxygenMetric(label: label, value: value, ok: ok);
  }
}
