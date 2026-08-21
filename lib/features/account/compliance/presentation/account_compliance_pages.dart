import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_status_pages.dart';
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';
import 'package:voice_social_app/features/account/presentation/third_party_authorization_page.dart';

export 'account_status_pages.dart';
export 'system_permission_pages.dart';

class AccountComplianceHubPage extends StatefulWidget {
  const AccountComplianceHubPage({
    required this.account,
    required this.currentVersion,
    required this.platformType,
    super.key,
  });

  final String account;
  final int currentVersion;
  final int platformType;

  @override
  State<AccountComplianceHubPage> createState() =>
      _AccountComplianceHubPageState();
}

class _AccountComplianceHubPageState extends State<AccountComplianceHubPage> {
  AccountComplianceSnapshot? _snapshot;
  String? _error;

  AccountComplianceRepository get _repository =>
      AppDependencyScope.of(context).accountComplianceRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final AccountComplianceSnapshot value = await _repository.fetchSnapshot(
        account: widget.account,
        currentVersion: widget.currentVersion,
        platformType: widget.platformType,
      );
      if (mounted) {
        setState(() {
          _snapshot = value;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AccountComplianceSnapshot? snapshot = _snapshot;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: snapshot == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _HubError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                children: <Widget>[
                  _AccountSummary(snapshot: snapshot),
                  const SizedBox(height: 20),
                  const AccountSectionLabel(text: '账号保护'),
                  AccountSheet(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    child: Column(
                      children: <Widget>[
                        _Entry(
                          icon: Icons.link_rounded,
                          title: '第三方账号绑定与分享授权',
                          subtitle: '供应商 SDK 未接入时明确保持不可用',
                          tone: const Color(0xFF57B785),
                          onTap: () =>
                              _open(const ThirdPartyAuthorizationPage()),
                        ),
                        _Entry(
                          icon: Icons.tune_rounded,
                          title: '系统权限中心',
                          subtitle: '麦克风、通知和照片权限',
                          tone: AccountOxygenColors.cyan,
                          onTap: () => _open(
                            SystemPermissionCenterPage(
                              account: widget.account,
                              currentVersion: widget.currentVersion,
                              platformType: widget.platformType,
                            ),
                          ),
                        ),
                        _Entry(
                          icon: Icons.badge_outlined,
                          title: '实名认证',
                          subtitle: _verificationLabel(
                            snapshot.verificationState,
                          ),
                          onTap: () => _open(
                            RealNamePage(
                              account: widget.account,
                              currentVersion: widget.currentVersion,
                              platformType: widget.platformType,
                            ),
                          ),
                        ),
                        _Entry(
                          icon: Icons.devices_other_rounded,
                          title: '登录设备与会话',
                          subtitle: '${snapshot.sessions.length} 个已知会话',
                          tone: const Color(0xFF5D84E8),
                          onTap: () => _open(
                            DeviceSessionsPage(
                              account: widget.account,
                              currentVersion: widget.currentVersion,
                              platformType: widget.platformType,
                            ),
                          ),
                        ),
                        _Entry(
                          icon: Icons.gpp_maybe_outlined,
                          title: '账号状态',
                          subtitle: snapshot.restriction.isRestricted
                              ? snapshot.restriction.reason
                              : '当前账号没有已知限制',
                          tone: snapshot.restriction.isRestricted
                              ? AppColors.warning
                              : AppColors.success,
                          showDivider: false,
                          onTap: () => _open(
                            AccountRestrictionPage(
                              account: widget.account,
                              currentVersion: widget.currentVersion,
                              platformType: widget.platformType,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const AccountSectionLabel(text: '平台与使用规则'),
                  AccountSheet(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    child: Column(
                      children: <Widget>[
                        _Entry(
                          icon: Icons.fact_check_outlined,
                          title: '处罚申诉',
                          subtitle: '查询原因、提交说明并查看处理进度',
                          tone: const Color(0xFF9471DA),
                          onTap: () =>
                              _open(AccountAppealPage(account: widget.account)),
                        ),
                        _Entry(
                          icon: Icons.person_remove_alt_1_outlined,
                          title: '账号注销',
                          subtitle: snapshot.cancellation.message,
                          tone: AppColors.warning,
                          onTap: () => _open(
                            AccountCancellationPage(
                              account: widget.account,
                              currentVersion: widget.currentVersion,
                              platformType: widget.platformType,
                            ),
                          ),
                        ),
                        _Entry(
                          icon: Icons.system_update_alt_rounded,
                          title: '版本升级',
                          subtitle: snapshot.versionInfo.hasUpdate
                              ? '发现 ${snapshot.versionInfo.versionName}'
                              : '当前已是最新版本',
                          tone: AccountOxygenColors.cyan,
                          onTap: () => _open(
                            VersionUpgradePage(
                              currentVersion: widget.currentVersion,
                              platformType: widget.platformType,
                            ),
                          ),
                        ),
                        _Entry(
                          icon: Icons.child_care_rounded,
                          title: '青少年模式',
                          subtitle: snapshot.youthModeEnabled ? '已开启' : '未开启',
                          tone: const Color(0xFF5D84E8),
                          showDivider: false,
                          onTap: () => _open(
                            YouthModePage(
                              account: widget.account,
                              currentVersion: widget.currentVersion,
                              platformType: widget.platformType,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const AccountNoticeStrip(
                    icon: Icons.lock_outline_rounded,
                    text: '敏感状态以服务端返回为准；未接入的原生能力不会显示为已完成。',
                    tone: AccountOxygenColors.cyan,
                  ),
                ],
              ),
            ),
    );
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.snapshot});

  final AccountComplianceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return AccountSheet(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              image: const DecorationImage(
                image: AssetImage('assets/runtime/avatar-copper.png'),
                fit: BoxFit.cover,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x1A7867E8), blurRadius: 14),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  snapshot.nickname,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  snapshot.account,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                AccountStatusPill(
                  label: snapshot.restriction.isRestricted
                      ? '账号存在限制'
                      : '账号状态正常',
                  color: snapshot.restriction.isRestricted
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone = AccountOxygenColors.violet,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color tone;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return AccountSettingRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      tone: tone,
      showDivider: showDivider,
      onTap: onTap,
    );
  }
}

class _HubError extends StatelessWidget {
  const _HubError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

String _verificationLabel(VerificationState state) => switch (state) {
  VerificationState.unverified => '未认证',
  VerificationState.pending => '审核中',
  VerificationState.verified => '已认证',
  VerificationState.rejected => '认证未通过',
  VerificationState.unavailable => '认证服务不可用',
};

String _messageFor(Object error) =>
    error is ApiException ? error.message : '操作失败，请稍后重试';
