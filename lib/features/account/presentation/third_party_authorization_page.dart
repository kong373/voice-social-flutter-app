import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';

class ThirdPartyAuthorizationPage extends StatelessWidget {
  const ThirdPartyAuthorizationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('第三方账号绑定与分享授权')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: <Widget>[
            const _AuthorizationBoundary(),
            const SizedBox(height: 20),
            const AccountSectionLabel(text: '可用授权方式'),
            AccountSheet(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Column(
                children: <Widget>[
                  for (
                    int index = 0;
                    index < _AuthorizationProvider.values.length;
                    index += 1
                  )
                    AccountSettingRow(
                      icon: _AuthorizationProvider.values[index].icon,
                      title: _AuthorizationProvider.values[index].label,
                      subtitle:
                          _AuthorizationProvider.values[index].description,
                      trailing: const AccountStatusPill(
                        label: 'VENDOR_BLOCKED',
                        color: AppColors.warning,
                      ),
                      tone: _AuthorizationProvider.values[index].tone,
                      showDivider:
                          index != _AuthorizationProvider.values.length - 1,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const AccountNoticeStrip(
              icon: Icons.lock_outline_rounded,
              text:
                  '账号绑定、授权回调和原生分享都必须由已审核的供应商 SDK 与服务端状态共同确认。当前构建不会伪造绑定成功，也不会请求真实第三方凭据。',
              tone: AccountOxygenColors.cyan,
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
    return const AccountStatusHero(
      icon: Icons.verified_user_outlined,
      title: '授权服务暂不可用',
      description: '尚未接入第三方账号与原生分享适配器，所有操作保持失败关闭。',
      tone: AppColors.warning,
      badge: '安全关闭',
    );
  }
}

enum _AuthorizationProvider {
  wechat(
    label: '微信账号',
    description: '绑定、解绑与授权状态由微信 SDK 和服务端确认',
    icon: Icons.chat_bubble_outline_rounded,
    tone: Color(0xFF48B778),
  ),
  qq(
    label: 'QQ 账号',
    description: '登录授权能力尚未接入',
    icon: Icons.forum_outlined,
    tone: AccountOxygenColors.cyan,
  ),
  nativeShare(
    label: '系统分享',
    description: '原生分享目标与回调适配器尚未接入',
    icon: Icons.ios_share_rounded,
    tone: AccountOxygenColors.violet,
  );

  const _AuthorizationProvider({
    required this.label,
    required this.description,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color tone;
}
