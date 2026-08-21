import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';

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
      appBar: roomOxygenAppBar(title: '弱网重连与会话恢复'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          RoomOxygenContextBar(
            title: controller.snapshot?.title ?? '深夜温柔陪伴',
            subtitle: '房间会话保留 · 不自动上麦',
            seed: controller.roomId,
            status: reconnecting ? '恢复中' : '会话保留',
            statusColor: reconnecting ? RoomColors.warning : RoomColors.success,
          ),
          const SizedBox(height: 16),
          RoomOxygenSection(
            title: '恢复顺序',
            subtitle: '房间上下文保持在当前页面，逐项恢复连接。',
            icon: Icons.sync_rounded,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
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
                const Divider(height: 1, indent: 40),
                _RecoveryStatusCard(
                  icon: Icons.graphic_eq_rounded,
                  title: 'RTC ${_rtcLabel(controller.snapshot?.rtc.solution)}',
                  description: controller.isOnMic
                      ? '保留麦位状态；恢复后按服务端权威麦位同步。'
                      : '当前为听众状态，恢复时不会自动上麦。',
                ),
                const Divider(height: 1, indent: 40),
                const _RecoveryStatusCard(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: '实时公屏',
                  description: '只展示进房后的实时消息，不伪造断线期间历史正文。',
                ),
              ],
            ),
          ),
          if (_resultMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            RoomOxygenNotice(
              icon: Icons.info_outline_rounded,
              message: _resultMessage!,
              accent: controller.status == RoomSessionStatus.joined
                  ? RoomColors.success
                  : RoomColors.warning,
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: reconnecting ? null : _reconnect,
              icon: reconnecting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(reconnecting ? '正在恢复' : '重新连接房间'),
            ),
          ),
          const SizedBox(height: 12),
          const RoomOxygenNotice(
            icon: Icons.shield_outlined,
            message: '任何一步失败都会保留当前页面上下文，不会把未知状态显示为已恢复。',
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
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: (warning ? RoomColors.warning : RoomColors.accent)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 17,
              color: warning ? RoomColors.warning : RoomColors.accent,
            ),
          ),
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
