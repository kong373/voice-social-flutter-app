import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/room/presentation/room_oxygen_components.dart';

class RoomSharePage extends StatelessWidget {
  const RoomSharePage({
    required this.roomId,
    required this.roomCode,
    required this.roomTitle,
    super.key,
  });

  final String roomId;
  final String roomCode;
  final String roomTitle;

  /// Native system sharing is intentionally outside the first-party scope.
  /// Keep this boundary explicit so this page never reports a vendor action as
  /// successful before a reviewed platform/share adapter is configured.
  static const String nativeShareStatus = 'VENDOR_BLOCKED';

  String get _shareText =>
      '$roomTitle\n房间号：$roomCode\nvoice-social://room/$roomId';

  Future<void> _copy(BuildContext context, String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return RoomPageScaffold(
      appBar: roomOxygenAppBar(title: '房间分享'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: <Widget>[
          OriginalRoomArtwork(
            seed: roomId,
            height: 164,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  const RoomOxygenPill(
                    label: '语音房邀请',
                    icon: Icons.graphic_eq_rounded,
                    active: true,
                    accent: RoomColors.accent,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    roomTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '房间号 $roomCode · 点击有效链接直接进入',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: RoomColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          RoomOxygenSection(
            title: '分享给朋友',
            subtitle: '复制邀请后可发送到任意会话，失效链接会被安全拦截。',
            icon: Icons.ios_share_rounded,
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                ListTile(
                  key: const Key('rm-009-copy-room-code'),
                  leading: const Icon(Icons.tag_rounded),
                  title: const Text('复制房间号'),
                  subtitle: Text(roomCode),
                  trailing: const Icon(Icons.copy_rounded, size: 19),
                  onTap: () => _copy(context, roomCode, '房间号已复制'),
                ),
                const Divider(height: 1, indent: 54),
                ListTile(
                  key: const Key('rm-009-copy-room-invite'),
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('复制房间邀请'),
                  subtitle: const Text('包含房间标题、房间号和深链'),
                  trailing: const Icon(Icons.copy_all_rounded, size: 19),
                  onTap: () => _copy(context, _shareText, '房间邀请已复制'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const RoomOxygenNotice(
            key: Key('rm-009-native-share-status'),
            icon: Icons.info_outline_rounded,
            title: '系统分享：$nativeShareStatus',
            message: '原生系统分享属于未接入的厂商/平台能力，当前不会伪造分享成功。复制房间号和房间邀请仍可用。',
          ),
        ],
      ),
    );
  }
}
