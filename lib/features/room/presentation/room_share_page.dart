import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';

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
      appBar: AppBar(title: const Text('房间分享')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF242752), Color(0xFF151832)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.graphic_eq_rounded, color: RoomColors.accent),
                const SizedBox(height: 20),
                Text(roomTitle, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '房间号 $roomCode',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                Text(
                  '点击有效房间链接后直接进入语音房；链接失效时展示恢复界面。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.tag_rounded),
            title: const Text('复制房间号'),
            subtitle: Text(roomCode),
            trailing: const Icon(Icons.copy_rounded),
            onTap: () => _copy(context, roomCode, '房间号已复制'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('复制房间邀请'),
            subtitle: const Text('包含房间标题、房间号和深链'),
            trailing: const Icon(Icons.copy_all_rounded),
            onTap: () => _copy(context, _shareText, '房间邀请已复制'),
          ),
          const SizedBox(height: 20),
          Text(
            '更多系统分享渠道暂不可用，可先复制房间邀请。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
