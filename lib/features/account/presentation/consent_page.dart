import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

class ConsentPage extends StatelessWidget {
  const ConsentPage({required this.onAccept, super.key});

  final Future<void> Function() onAccept;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          child: ListView(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                '欢迎使用',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '在开始使用前，请阅读并同意用户协议与隐私政策。我们会在提供账号、语音房、消息和支付等功能所必需的范围内处理信息。',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              const _ConsentPoint(
                icon: Icons.mic_none_rounded,
                title: '麦克风权限',
                description: '仅在你申请上麦或发送语音时申请。',
              ),
              const _ConsentPoint(
                icon: Icons.notifications_none_rounded,
                title: '通知权限',
                description: '用于私聊、好友互动和房间邀请提醒。',
              ),
              const _ConsentPoint(
                icon: Icons.lock_outline_rounded,
                title: '账号与设备信息',
                description: '用于登录安全、异常会话识别和账号保护。',
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 4,
                children: <Widget>[
                  const Text('点击同意即表示你已阅读并接受'),
                  TextButton(
                    onPressed: () => _showDocument(context, '用户协议'),
                    child: const Text('用户协议'),
                  ),
                  const Text('与'),
                  TextButton(
                    onPressed: () => _showDocument(context, '隐私政策'),
                    child: const Text('隐私政策'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAccept,
                  child: const Text('同意并继续'),
                ),
              ),
              const SizedBox(height: 8),
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
              const Text(
                '当前为研发阶段的协议入口。正式版本将加载经法务审核并按版本留档的完整文本。',
              ),
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
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: AppColors.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
