import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_status_pages.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';

/// Global live access gate shown before MainShell when the server says that an
/// account is restricted or when its usability cannot be confirmed.
class AccountAccessGatePage extends StatelessWidget {
  const AccountAccessGatePage({
    required this.account,
    required this.onRetry,
    required this.onSignOut,
    this.restriction,
    this.accountUsable = true,
    this.errorMessage,
    this.loading = false,
    super.key,
  });

  final String account;
  final AccountRestriction? restriction;
  final bool accountUsable;
  final String? errorMessage;
  final bool loading;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  bool get _hasRestriction => restriction?.isRestricted == true;

  Future<void> _openAppeal(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AccountAppealPage(account: account),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isError = errorMessage != null;
    final String reason = restriction?.reason.trim() ?? '';
    final String description = isError
        ? '网络或服务异常，当前无法确认 account restrictions/accountUsable。为保护账号，应用不会默认放行。'
        : reason.isEmpty
        ? '服务端尚未确认当前账号可以使用主要功能。请重试或联系平台处理。'
        : reason;
    return SocialPageScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AccountSheet(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: loading
                            ? const Color(0xFFEFF0FF)
                            : isError || _hasRestriction
                            ? const Color(0xFFFFF2E4)
                            : const Color(0xFFEFF0FF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        loading
                            ? Icons.sync_rounded
                            : isError
                            ? Icons.cloud_off_rounded
                            : Icons.gpp_maybe_outlined,
                        size: 31,
                        color: loading
                            ? AccountOxygenColors.violet
                            : isError || _hasRestriction
                            ? AppColors.warning
                            : AccountOxygenColors.violet,
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      loading
                          ? '正在确认账号状态'
                          : isError
                          ? '无法确认账号状态'
                          : _hasRestriction
                          ? '账号访问受限'
                          : '账号暂不可用',
                      key: const Key('account-access-gate-title'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AccountOxygenColors.ink,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: CircularProgressIndicator(),
                      ),
                    if (!loading && _hasRestriction)
                      const Text(
                        'ACCOUNT_RESTRICTED',
                        key: Key('account-restricted-status'),
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    if (!loading &&
                        !_hasRestriction &&
                        !isError &&
                        !accountUsable)
                      const Text(
                        'accountUsable=false',
                        key: Key('account-unusable-status'),
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      key: const Key('account-access-gate-reason'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (!loading && isError) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        errorMessage!,
                        key: const Key('account-access-gate-error'),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 22),
                    AccountPrimaryAction(
                      key: const Key('account-access-gate-retry'),
                      label: '重新检查',
                      icon: Icons.refresh_rounded,
                      onPressed: loading ? null : onRetry,
                    ),
                    if (!loading &&
                        !isError &&
                        (_hasRestriction || !accountUsable)) ...<Widget>[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const Key('account-access-gate-appeal'),
                          onPressed: () => _openAppeal(context),
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('进入申诉入口'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        key: const Key('account-access-gate-signout'),
                        onPressed: onSignOut,
                        child: const Text('退出并重新登录'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
