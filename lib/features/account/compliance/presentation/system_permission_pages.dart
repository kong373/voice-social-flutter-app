import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_compliance_error.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';

class SystemPermissionCenterPage extends StatefulWidget {
  const SystemPermissionCenterPage({
    required this.account,
    required this.currentVersion,
    required this.platformType,
    super.key,
  });

  final String account;
  final int currentVersion;
  final int platformType;

  @override
  State<SystemPermissionCenterPage> createState() =>
      _SystemPermissionCenterPageState();
}

class _SystemPermissionCenterPageState extends State<SystemPermissionCenterPage>
    with WidgetsBindingObserver {
  AccountComplianceSnapshot? _snapshot;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _snapshot != null) {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final AccountComplianceSnapshot value =
          await AppDependencyScope.of(
            context,
          ).accountComplianceRepository.fetchSnapshot(
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

  Future<void> _request(PermissionSetting setting) async {
    try {
      await AppDependencyScope.of(
        context,
      ).accountComplianceRepository.setPermissionState(
        kind: setting.kind,
        state: PermissionState.granted,
      );
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        showAccountComplianceRetrySnackBar(
          context,
          message: _messageFor(error),
          onRetry: () => _request(setting),
        );
      }
    }
  }

  Future<void> _openSettings() async {
    try {
      await AppDependencyScope.of(
        context,
      ).accountComplianceRepository.openPermissionSettings();
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        showAccountComplianceRetrySnackBar(
          context,
          message: _messageFor(error),
          onRetry: _openSettings,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AccountComplianceSnapshot? snapshot = _snapshot;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('系统权限中心')),
      body: snapshot == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : AccountComplianceError(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: <Widget>[
                const AccountStatusHero(
                  icon: Icons.shield_outlined,
                  title: '按需开启系统权限',
                  description: '你可以随时查看当前授权状态。被拒绝的权限不会被伪装为已允许。',
                  tone: AccountOxygenColors.cyan,
                  badge: '隐私保护',
                ),
                const SizedBox(height: 16),
                AccountNoticeStrip(
                  icon: Icons.info_outline_rounded,
                  text:
                      snapshot.permissions.every(
                        (PermissionSetting item) =>
                            item.managedByPlatform == null,
                      )
                      ? '当前版本原生权限适配器尚未接入，状态显示为“适配器未接入”。不会把未知状态伪装成尚未请求，也不会发起授权请求。'
                      : '权限只在具体功能需要时请求。Live 模式必须由原生系统适配器返回真实状态。',
                  tone: AccountOxygenColors.violet,
                ),
                const SizedBox(height: 18),
                const AccountSectionLabel(text: '权限状态'),
                AccountSheet(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  child: Column(
                    children: <Widget>[
                      for (
                        int index = 0;
                        index < snapshot.permissions.length;
                        index += 1
                      ) ...<Widget>[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 3,
                          ),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _permissionTone(
                                snapshot.permissions[index].kind,
                              ).withValues(alpha: 0.09),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _permissionIcon(snapshot.permissions[index].kind),
                              color: _permissionTone(
                                snapshot.permissions[index].kind,
                              ),
                              size: 20,
                            ),
                          ),
                          title: Text(snapshot.permissions[index].title),
                          subtitle: Text(snapshot.permissions[index].purpose),
                          trailing:
                              snapshot.permissions[index].state ==
                                  PermissionState.permanentlyDenied
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    AccountStatusPill(
                                      label: _permissionStateLabel(
                                        snapshot.permissions[index].state,
                                      ),
                                      color: _permissionStateTone(
                                        snapshot.permissions[index].state,
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        minimumSize: Size.zero,
                                        padding: EdgeInsets.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed:
                                          snapshot
                                                  .permissions[index]
                                                  .managedByPlatform ==
                                              true
                                          ? _openSettings
                                          : null,
                                      child: const Text('打开设置'),
                                    ),
                                  ],
                                )
                              : AccountStatusPill(
                                  label: _permissionStateLabel(
                                    snapshot.permissions[index].state,
                                  ),
                                  color: _permissionStateTone(
                                    snapshot.permissions[index].state,
                                  ),
                                ),
                          onTap:
                              snapshot.permissions[index].state ==
                                      PermissionState.granted ||
                                  snapshot
                                          .permissions[index]
                                          .managedByPlatform !=
                                      true
                              ? null
                              : () => _request(snapshot.permissions[index]),
                        ),
                        if (index != snapshot.permissions.length - 1)
                          const Padding(
                            padding: EdgeInsets.only(left: 54),
                            child: Divider(
                              height: 1,
                              color: AccountOxygenColors.line,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class RealNamePage extends StatefulWidget {
  const RealNamePage({
    required this.account,
    required this.currentVersion,
    required this.platformType,
    super.key,
  });

  final String account;
  final int currentVersion;
  final int platformType;

  @override
  State<RealNamePage> createState() => _RealNamePageState();
}

class _RealNamePageState extends State<RealNamePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  VerificationState? _state;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state == null && _error == null) {
      _load();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _error = null);
    }
    try {
      final AccountComplianceSnapshot snapshot =
          await AppDependencyScope.of(
            context,
          ).accountComplianceRepository.fetchSnapshot(
            account: widget.account,
            currentVersion: widget.currentVersion,
            platformType: widget.platformType,
          );
      if (mounted) {
        setState(() {
          _state = snapshot.verificationState;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await AppDependencyScope.of(
        context,
      ).accountComplianceRepository.submitRealName(
        realName: _nameController.text.trim(),
        idNumber: _idController.text.trim(),
      );
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        showAccountComplianceRetrySnackBar(
          context,
          message: _messageFor(error),
          onRetry: _submit,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AccountComplianceRepository repository = AppDependencyScope.of(
      context,
    ).accountComplianceRepository;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('实名认证')),
      body: _state == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : AccountComplianceError(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: <Widget>[
                AccountStatusHero(
                  icon: Icons.badge_outlined,
                  title: _verificationLabel(_state!),
                  description: repository.supportsRealNameSubmission
                      ? '认证信息只用于法定实名和资金安全校验。'
                      : '认证服务正在接入。Live 模式不会把本地填写冒充为认证成功。',
                  tone: _state == VerificationState.verified
                      ? AppColors.success
                      : AccountOxygenColors.violet,
                  badge: repository.supportsRealNameSubmission
                      ? '安全提交'
                      : '服务未接入',
                ),
                if (_state == VerificationState.unverified &&
                    repository.supportsRealNameSubmission) ...<Widget>[
                  const SizedBox(height: 20),
                  const AccountSectionLabel(text: '填写认证信息'),
                  AccountSheet(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: <Widget>[
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: '真实姓名',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (String? value) =>
                                value == null || value.trim().length < 2
                                ? '请输入真实姓名'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _idController,
                            maxLength: 18,
                            decoration: const InputDecoration(
                              labelText: '身份证号',
                              prefixIcon: Icon(Icons.credit_card_rounded),
                            ),
                            validator: (String? value) =>
                                value == null || value.trim().length != 18
                                ? '请输入 18 位身份证号'
                                : null,
                          ),
                          const SizedBox(height: 2),
                          AccountPrimaryAction(
                            label: '提交认证',
                            busy: _busy,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const AccountNoticeStrip(
                    icon: Icons.lock_outline_rounded,
                    text: '页面不会展示完整证件号码，审核结果以服务端返回为准。',
                    tone: AccountOxygenColors.cyan,
                  ),
                ],
              ],
            ),
    );
  }
}

class DeviceSessionsPage extends StatefulWidget {
  const DeviceSessionsPage({
    required this.account,
    required this.currentVersion,
    required this.platformType,
    super.key,
  });

  final String account;
  final int currentVersion;
  final int platformType;

  @override
  State<DeviceSessionsPage> createState() => _DeviceSessionsPageState();
}

class _DeviceSessionsPageState extends State<DeviceSessionsPage> {
  AccountComplianceSnapshot? _snapshot;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _error = null);
    }
    try {
      final AccountComplianceSnapshot value =
          await AppDependencyScope.of(
            context,
          ).accountComplianceRepository.fetchSnapshot(
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

  Future<void> _revoke(DeviceSession session) async {
    try {
      await AppDependencyScope.of(
        context,
      ).accountComplianceRepository.revokeDeviceSession(session.id);
      if (mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        showAccountComplianceRetrySnackBar(
          context,
          message: _messageFor(error),
          onRetry: () => _revoke(session),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AccountComplianceSnapshot? snapshot = _snapshot;
    final bool supported = AppDependencyScope.of(
      context,
    ).accountComplianceRepository.supportsDeviceSessionManagement;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('登录设备与会话')),
      body: snapshot == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : AccountComplianceError(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: <Widget>[
                AccountStatusHero(
                  icon: Icons.devices_other_rounded,
                  title: '${snapshot.sessions.length} 个登录会话',
                  description: '仅保留你认识的设备；移除后该设备需要重新验证身份。',
                  tone: const Color(0xFF5D84E8),
                  badge: '会话安全',
                ),
                const SizedBox(height: 14),
                if (!supported)
                  const AccountNoticeStrip(
                    icon: Icons.info_outline_rounded,
                    text: '当前后端尚未提供用户侧会话撤销接口，只展示已知当前会话。',
                    tone: AppColors.warning,
                  ),
                const SizedBox(height: 18),
                const AccountSectionLabel(text: '已登录设备'),
                AccountSheet(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  child: Column(
                    children: <Widget>[
                      for (
                        int index = 0;
                        index < snapshot.sessions.length;
                        index += 1
                      )
                        AccountSettingRow(
                          icon: snapshot.sessions[index].isCurrent
                              ? Icons.phone_android_rounded
                              : Icons.devices_other_rounded,
                          title: snapshot.sessions[index].deviceName,
                          subtitle: snapshot.sessions[index].location,
                          tone: snapshot.sessions[index].isCurrent
                              ? AppColors.success
                              : const Color(0xFF5D84E8),
                          trailing: snapshot.sessions[index].isCurrent
                              ? const AccountStatusPill(
                                  label: '当前设备',
                                  color: AppColors.success,
                                )
                              : TextButton(
                                  onPressed: snapshot.sessions[index].canRevoke
                                      ? () => _revoke(snapshot.sessions[index])
                                      : null,
                                  child: const Text('移除'),
                                ),
                          showDivider: index != snapshot.sessions.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

IconData _permissionIcon(PermissionKind kind) => switch (kind) {
  PermissionKind.microphone => Icons.mic_none_rounded,
  PermissionKind.notifications => Icons.notifications_none_rounded,
  PermissionKind.photos => Icons.photo_library_outlined,
};

String _permissionStateLabel(PermissionState state) => switch (state) {
  PermissionState.notDetermined => '尚未请求',
  PermissionState.granted => '已允许',
  PermissionState.denied => '已拒绝',
  PermissionState.permanentlyDenied => '已永久拒绝',
  PermissionState.restricted => '受系统限制',
  PermissionState.unavailable => '适配器未接入',
};
Color _permissionTone(PermissionKind kind) => switch (kind) {
  PermissionKind.microphone => AccountOxygenColors.violet,
  PermissionKind.notifications => AccountOxygenColors.cyan,
  PermissionKind.photos => AccountOxygenColors.pink,
};

Color _permissionStateTone(PermissionState state) => switch (state) {
  PermissionState.notDetermined => AccountOxygenColors.violet,
  PermissionState.granted => AppColors.success,
  PermissionState.denied => AppColors.warning,
  PermissionState.permanentlyDenied => AppColors.error,
  PermissionState.restricted => AppColors.error,
  PermissionState.unavailable => AppColors.warning,
};

String _verificationLabel(VerificationState state) => switch (state) {
  VerificationState.unverified => '未认证',
  VerificationState.pending => '审核中',
  VerificationState.verified => '已认证',
  VerificationState.rejected => '认证未通过',
  VerificationState.unavailable => '认证服务不可用',
};

String _messageFor(Object error) =>
    error is ApiException ? error.message : '操作失败，请稍后重试';
