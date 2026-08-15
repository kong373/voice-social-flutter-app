import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_status_pages.dart';
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: snapshot == null
          ? _error == null
              ? const Center(child: CircularProgressIndicator())
              : _HubError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                children: <Widget>[
                  _AccountSummary(snapshot: snapshot),
                  const SizedBox(height: 14),
                  _Entry(
                    icon: Icons.tune_rounded,
                    title: '系统权限中心',
                    subtitle: '麦克风、通知和照片权限',
                    onTap: () => _open(SystemPermissionCenterPage(
                      account: widget.account,
                      currentVersion: widget.currentVersion,
                      platformType: widget.platformType,
                    )),
                  ),
                  _Entry(
                    icon: Icons.badge_outlined,
                    title: '实名认证',
                    subtitle: _verificationLabel(snapshot.verificationState),
                    onTap: () => _open(RealNamePage(
                      account: widget.account,
                      currentVersion: widget.currentVersion,
                      platformType: widget.platformType,
                    )),
                  ),
                  _Entry(
                    icon: Icons.devices_other_rounded,
                    title: '登录设备与会话',
                    subtitle: '${snapshot.sessions.length} 个已知会话',
                    onTap: () => _open(DeviceSessionsPage(
                      account: widget.account,
                      currentVersion: widget.currentVersion,
                      platformType: widget.platformType,
                    )),
                  ),
                  _Entry(
                    icon: Icons.gpp_maybe_outlined,
                    title: '账号状态',
                    subtitle: snapshot.restriction.isRestricted
                        ? snapshot.restriction.reason
                        : '当前账号没有已知限制',
                    onTap: () => _open(AccountRestrictionPage(
                      account: widget.account,
                      currentVersion: widget.currentVersion,
                      platformType: widget.platformType,
                    )),
                  ),
                  _Entry(
                    icon: Icons.fact_check_outlined,
                    title: '处罚申诉',
                    subtitle: '查询原因、提交说明并查看处理进度',
                    onTap: () => _open(
                      AccountAppealPage(account: widget.account),
                    ),
                  ),
                  _Entry(
                    icon: Icons.person_remove_alt_1_outlined,
                    title: '账号注销',
                    subtitle: snapshot.cancellation.message,
                    onTap: () => _open(AccountCancellationPage(
                      account: widget.account,
                      currentVersion: widget.currentVersion,
                      platformType: widget.platformType,
                    )),
                  ),
                  _Entry(
                    icon: Icons.system_update_alt_rounded,
                    title: '版本升级',
                    subtitle: snapshot.versionInfo.hasUpdate
                        ? '发现 ${snapshot.versionInfo.versionName}'
                        : '当前已是最新版本',
                    onTap: () => _open(VersionUpgradePage(
                      currentVersion: widget.currentVersion,
                      platformType: widget.platformType,
                    )),
                  ),
                  _Entry(
                    icon: Icons.child_care_rounded,
                    title: '青少年模式',
                    subtitle: snapshot.youthModeEnabled ? '已开启' : '未开启',
                    onTap: () => _open(YouthModePage(
                      account: widget.account,
                      currentVersion: widget.currentVersion,
                      platformType: widget.platformType,
                    )),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: <Widget>[
          const CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.surfaceHigh,
            child: Icon(Icons.shield_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(snapshot.nickname,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(snapshot.account,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(
                  snapshot.restriction.isRestricted
                      ? '账号存在限制'
                      : '账号状态正常',
                  style: TextStyle(
                    color: snapshot.restriction.isRestricted
                        ? AppColors.warning
                        : AppColors.success,
                  ),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.accent),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
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
