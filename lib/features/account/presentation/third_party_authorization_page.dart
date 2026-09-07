import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';

/// Explicit AC-004 exclusion contract. These capabilities are intentionally
/// represented as unavailable until a reviewed provider adapter and
/// server-authoritative callback exist; no UI action is allowed to claim
/// binding or sharing success while the contract is blocked.
class AccountVendorBoundaryContract {
  const AccountVendorBoundaryContract({
    required this.capability,
    required this.label,
    required this.description,
    required this.icon,
    required this.tone,
    this.status = 'VENDOR_BLOCKED',
    this.providerInvocation = false,
    this.successClaimAllowed = false,
  });

  final String capability;
  final String label;
  final String description;
  final IconData icon;
  final Color tone;
  final String status;
  final bool providerInvocation;
  final bool successClaimAllowed;
}

const String accountVendorBoundaryContractVersion =
    'account-vendor-boundary-v1';

const List<AccountVendorBoundaryContract> accountVendorBoundaryContracts =
    <AccountVendorBoundaryContract>[
      AccountVendorBoundaryContract(
        capability: 'SOCIAL_ACCOUNT_BINDING',
        label: '社交账号绑定',
        description: '暂不支持绑定或解绑微信、QQ等社交账号',
        icon: Icons.chat_bubble_outline_rounded,
        tone: Color(0xFF48B778),
      ),
      AccountVendorBoundaryContract(
        capability: 'NATIVE_SHARE',
        label: '原生分享',
        description: '暂不支持通过系统分享面板分享内容',
        icon: Icons.ios_share_rounded,
        tone: AccountOxygenColors.violet,
      ),
    ];

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
            const AccountSectionLabel(text: '授权方式'),
            AccountSheet(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: Column(
                children: <Widget>[
                  for (
                    int index = 0;
                    index < accountVendorBoundaryContracts.length;
                    index += 1
                  )
                    AccountSettingRow(
                      key: ValueKey<String>(
                        'ac004-${accountVendorBoundaryContracts[index].capability}',
                      ),
                      icon: accountVendorBoundaryContracts[index].icon,
                      title: accountVendorBoundaryContracts[index].label,
                      subtitle:
                          accountVendorBoundaryContracts[index].description,
                      trailing: AccountStatusPill(
                        label: '暂不可用',
                        color: AppColors.warning,
                      ),
                      tone: accountVendorBoundaryContracts[index].tone,
                      showDivider:
                          index != accountVendorBoundaryContracts.length - 1,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const AccountNoticeStrip(
              icon: Icons.lock_outline_rounded,
              text: '当前版本暂不支持社交账号绑定及系统分享，不会发起第三方授权。',
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
      description: '社交账号绑定及系统分享暂不可用，后续开放时会在这里显示。',
      tone: AppColors.warning,
      badge: '暂不可用',
    );
  }
}
