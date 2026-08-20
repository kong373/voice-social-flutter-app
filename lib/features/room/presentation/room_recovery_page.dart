import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

class RoomRecoveryPage extends StatefulWidget {
  const RoomRecoveryPage({required this.controller, super.key});

  final RoomController controller;

  @override
  State<RoomRecoveryPage> createState() => _RoomRecoveryPageState();
}

class _RoomRecoveryPageState extends State<RoomRecoveryPage> {
  String? _resultMessage;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _reconnect() async {
    setState(() => _resultMessage = null);
    await widget.controller.reconnect();
    if (!mounted) {
      return;
    }
    setState(() {
      _resultMessage = widget.controller.status == RoomSessionStatus.joined
          ? '房间状态已刷新。断线期间公屏消息可能未显示。'
          : widget.controller.errorMessage ?? '房间恢复失败，请重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    final RoomController controller = widget.controller;
    final bool reconnecting =
        controller.status == RoomSessionStatus.reconnecting;
    return RoomPageScaffold(
      appBar: AppBar(title: const Text('弱网重连与会话恢复')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: <Widget>[
          _RecoveryStatusCard(
            icon: controller.realtimeDegraded
                ? Icons.wifi_off_rounded
                : Icons.wifi_rounded,
            title: controller.realtimeDegraded ? '实时通道状态异常' : '实时通道已连接',
            description: controller.realtimeDegraded
                ? '麦位和操作区保持显示；状态可能延迟。'
                : '麦位、公屏和成员状态正在正常更新。',
            warning: controller.realtimeDegraded,
          ),
          const SizedBox(height: 12),
          _RecoveryStatusCard(
            icon: Icons.graphic_eq_rounded,
            title: 'RTC ${_rtcLabel(controller.snapshot?.rtc.solution)}',
            description: controller.isOnMic
                ? '当前仍保留麦位状态；恢复后继续按服务端权威麦位同步。'
                : '当前为听众状态，恢复时不会自动上麦。',
          ),
          const SizedBox(height: 12),
          const _RecoveryStatusCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: '实时公屏',
            description: '只展示进入房间后的实时消息，不补拉或伪造断线期间历史正文。',
          ),
          if (_resultMessage != null) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RoomColors.surfaceHigh,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(_resultMessage!),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: reconnecting ? null : _reconnect,
            icon: reconnecting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(reconnecting ? '正在恢复' : '重新连接房间'),
          ),
          const SizedBox(height: 12),
          Text(
            '恢复顺序：获取服务端房间状态 → 刷新 RTC 凭据 → 恢复实时消息 → 重新渲染麦位。任何一步失败都会保留当前页面上下文。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _rtcLabel(RtcSolution? solution) {
    return switch (solution) {
      RtcSolution.agora => '声网方案',
      RtcSolution.zego => '即构方案',
      RtcSolution.unknown || null => '方案待确认',
    };
  }
}

class _RecoveryStatusCard extends StatelessWidget {
  const _RecoveryStatusCard({
    required this.icon,
    required this.title,
    required this.description,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warning
            ? RoomColors.warning.withValues(alpha: 0.1)
            : RoomColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: warning ? RoomColors.warning : RoomColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
