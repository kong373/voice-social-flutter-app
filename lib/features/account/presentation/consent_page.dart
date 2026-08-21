import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';

class ConsentPage extends StatelessWidget {
  const ConsentPage({required this.onAccept, super.key});

  final Future<void> Function() onAccept;

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      bottomNavigationBar: AccountBottomActionBar(
        child: AccountPrimaryAction(
          label: '同意并继续',
          icon: Icons.arrow_forward_rounded,
          onPressed: onAccept,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 32),
          children: <Widget>[
            const AccountMistHero(
              eyebrow: 'WELCOME',
              title: '欢迎使用',
              subtitle: '先确认必要的信息使用边界，之后每项系统权限仍会在实际使用时单独询问。',
              markSize: 60,
              centered: false,
            ),
            const SizedBox(height: 25),
            const AccountSectionLabel(text: '我们如何使用权限'),
            const AccountSheet(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Column(
                children: <Widget>[
                  _ConsentPoint(
                    icon: Icons.mic_none_rounded,
                    title: '麦克风权限',
                    description: '仅在你申请上麦或发送语音时申请。',
                  ),
                  _ConsentPoint(
                    icon: Icons.notifications_none_rounded,
                    title: '通知权限',
                    description: '用于私聊、好友互动和房间邀请提醒。',
                  ),
                  _ConsentPoint(
                    icon: Icons.lock_outline_rounded,
                    title: '账号与设备信息',
                    description: '用于登录安全、异常会话识别和账号保护。',
                    showDivider: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AccountNoticeStrip(
              icon: Icons.privacy_tip_outlined,
              text: '在开始使用前，请阅读并同意用户协议与隐私政策。我们只在账号、语音房、消息与支付等功能所必需的范围内处理信息。',
              tone: AccountOxygenColors.cyan,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TextButton(
                  onPressed: () => _showDocument(context, '用户协议'),
                  child: const Text('用户协议'),
                ),
                Text('和', style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                  onPressed: () => _showDocument(context, '隐私政策'),
                  child: const Text('隐私政策'),
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: const Text('暂不使用'),
                    content: const Text('不同意协议将无法进入应用。你可以关闭应用后再决定。'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('返回'),
                      ),
                    ],
                  ),
                ),
                child: const Text('暂不使用'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showDocument(BuildContext context, String title) =>
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (BuildContext context) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              const Text('当前为研发阶段的协议入口。正式版本将加载经法务审核并按版本留档的完整文本。'),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ConsentPoint extends StatelessWidget {
  const _ConsentPoint({
    required this.icon,
    required this.title,
    required this.description,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return AccountSettingRow(
      icon: icon,
      title: title,
      subtitle: description,
      tone: AccountOxygenColors.violet,
      showDivider: showDivider,
    );
  }
}
