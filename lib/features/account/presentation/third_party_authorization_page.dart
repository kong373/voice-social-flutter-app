import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';

class ThirdPartyAuthorizationPage extends StatelessWidget {
  const ThirdPartyAuthorizationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('第三方账号绑定与分享授权')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: <Widget>[
            const _AuthorizationBoundary(),
            const SizedBox(height: 16),
            for (final _AuthorizationProvider provider
                in _AuthorizationProvider.values)
              Card(
                child: ListTile(
                  minVerticalPadding: 14,
                  leading: Icon(provider.icon, color: AppColors.accent),
                  title: Text(provider.label),
                  subtitle: Text(provider.description),
                  trailing: const Text(
                    'VENDOR_BLOCKED',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  enabled: false,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              '账号绑定、授权回调和原生分享都必须由已审核的供应商 SDK 与服务端状态共同确认。当前构建不会伪造绑定成功，也不会请求真实第三方凭据。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorizationBoundary extends StatelessWidget {
  const _AuthorizationBoundary();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.verified_user_outlined, color: AppColors.warning),
          SizedBox(width: 12),
          Expanded(child: Text('尚未接入第三方账号与原生分享适配器，所有操作保持失败关闭。')),
        ],
      ),
    );
  }
}

enum _AuthorizationProvider {
  wechat(
    label: '微信账号',
    description: '绑定、解绑与授权状态由微信 SDK 和服务端确认',
    icon: Icons.chat_bubble_outline_rounded,
  ),
  qq(label: 'QQ 账号', description: '登录授权能力尚未接入', icon: Icons.forum_outlined),
  nativeShare(
    label: '系统分享',
    description: '原生分享目标与回调适配器尚未接入',
    icon: Icons.ios_share_rounded,
  );

  const _AuthorizationProvider({
    required this.label,
    required this.description,
    required this.icon,
  });

  final String label;
  final String description;
  final IconData icon;
}
