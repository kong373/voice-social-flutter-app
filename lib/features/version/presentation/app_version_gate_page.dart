import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';

/// Version policy gate used before MainShell.
///
/// No external URL launcher is bundled in this client. The optional callback
/// lets an approved host provide a controlled opener; when it is absent, the
/// button fails closed and never claims that an update was installed.
class AppVersionGatePage extends StatefulWidget {
  const AppVersionGatePage({
    required this.info,
    required this.mandatory,
    required this.onRetry,
    required this.onLater,
    required this.onSignOut,
    this.openPackageUrl,
    super.key,
  });

  final VersionUpdateInfo info;
  final bool mandatory;
  final Future<void> Function() onRetry;
  final VoidCallback? onLater;
  final Future<void> Function() onSignOut;
  final Future<bool> Function(Uri packageUri)? openPackageUrl;

  @override
  State<AppVersionGatePage> createState() => _AppVersionGatePageState();
}

class _AppVersionGatePageState extends State<AppVersionGatePage> {
  bool _busy = false;
  String? _error;
  String? _status;

  Future<void> _openUpdate() async {
    if (_busy) {
      return;
    }
    final String rawUrl = widget.info.packageUrl.trim();
    final Uri? packageUri = Uri.tryParse(rawUrl);
    if (packageUri == null ||
        packageUri.host.isEmpty ||
        packageUri.scheme.toLowerCase() != 'https') {
      setState(() {
        _error = '升级地址缺失或不安全，未打开外部地址，也未标记升级完成。';
        _status = null;
      });
      return;
    }
    final Future<bool> Function(Uri packageUri)? opener = widget.openPackageUrl;
    if (opener == null) {
      setState(() {
        _error = '升级通道尚未批准，当前不会打开外部地址或伪造升级成功。';
        _status = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final bool opened = await opener(packageUri);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        if (opened) {
          _status = '升级地址已打开。请完成安装并重新启动应用；当前不会把打开地址视为升级完成。';
        } else {
          _error = '升级地址未能打开，当前没有完成升级。请重试或退出登录。';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '升级动作失败，当前没有完成升级。请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VersionUpdateInfo info = widget.info;
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
                      decoration: const BoxDecoration(
                        color: Color(0xFFEFF0FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        size: 31,
                        color: AccountOxygenColors.violet,
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      widget.mandatory ? '必须更新后继续' : '发现新版本',
                      key: const Key('app-version-gate-title'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AccountOxygenColors.ink,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '版本 ${info.versionName.isEmpty ? '未知' : info.versionName}',
                      key: const Key('app-version-gate-version'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AccountOxygenColors.violet,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      info.releaseNotes.isEmpty
                          ? '服务端要求更新客户端。'
                          : info.releaseNotes,
                      key: const Key('app-version-gate-notes'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AccountNoticeStrip(
                      icon: Icons.link_outlined,
                      text: info.packageUrl.trim().isEmpty
                          ? '服务端未提供升级地址，当前不会伪造下载或升级成功。'
                          : '升级地址将经过受控动作处理；打开地址不等于已安装更新。',
                      tone: AppColors.warning,
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        key: const Key('app-version-gate-error'),
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                      ),
                    ],
                    if (_status != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        _status!,
                        key: const Key('app-version-gate-status'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    AccountPrimaryAction(
                      key: const Key('app-version-gate-open'),
                      label: _busy ? '处理中…' : '打开升级地址',
                      busy: _busy,
                      icon: Icons.open_in_new_rounded,
                      onPressed: _busy ? null : _openUpdate,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const Key('app-version-gate-retry'),
                        onPressed: _busy ? null : widget.onRetry,
                        child: const Text('重新检查版本'),
                      ),
                    ),
                    if (!widget.mandatory &&
                        widget.onLater != null) ...<Widget>[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          key: const Key('app-version-gate-later'),
                          onPressed: _busy ? null : widget.onLater,
                          child: const Text('稍后更新'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        key: const Key('app-version-gate-signout'),
                        onPressed: _busy ? null : widget.onSignOut,
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
