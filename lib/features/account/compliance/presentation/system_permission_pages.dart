import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

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

class _SystemPermissionCenterPageState
    extends State<SystemPermissionCenterPage> {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
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
                : _PageError(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.all(18),
              children: <Widget>[
                const _Info(text: '权限只在具体功能需要时请求。Live 模式必须由原生系统适配器返回真实状态。'),
                const SizedBox(height: 10),
                for (final PermissionSetting item
                    in snapshot.permissions) ...<Widget>[
                  const SizedBox(height: 10),
                  SocialCard(
                    padding: EdgeInsets.zero,
                    radius: 19,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      leading: Icon(_permissionIcon(item.kind)),
                      title: Text(item.title),
                      subtitle: Text(item.purpose),
                      trailing: Text(_permissionStateLabel(item.state)),
                      onTap: item.state == PermissionState.granted
                          ? null
                          : () => _request(item),
                    ),
                  ),
                ],
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
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state == null) {
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
    final AccountComplianceSnapshot snapshot =
        await AppDependencyScope.of(
          context,
        ).accountComplianceRepository.fetchSnapshot(
          account: widget.account,
          currentVersion: widget.currentVersion,
          platformType: widget.platformType,
        );
    if (mounted) {
      setState(() => _state = snapshot.verificationState);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
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
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                _Header(
                  icon: Icons.badge_outlined,
                  title: _verificationLabel(_state!),
                  description: repository.supportsRealNameSubmission
                      ? '认证信息只用于法定实名和资金安全校验。'
                      : '认证服务正在接入。Live 模式不会把本地填写冒充为认证成功。',
                ),
                if (_state == VerificationState.unverified &&
                    repository.supportsRealNameSubmission) ...<Widget>[
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: <Widget>[
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: '真实姓名'),
                          validator: (String? value) =>
                              value == null || value.trim().length < 2
                              ? '请输入真实姓名'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _idController,
                          maxLength: 18,
                          decoration: const InputDecoration(labelText: '身份证号'),
                          validator: (String? value) =>
                              value == null || value.trim().length != 18
                              ? '请输入 18 位身份证号'
                              : null,
                        ),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(_busy ? '提交中…' : '提交认证'),
                        ),
                      ],
                    ),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final AccountComplianceSnapshot value = await AppDependencyScope.of(context)
        .accountComplianceRepository
        .fetchSnapshot(
          account: widget.account,
          currentVersion: widget.currentVersion,
          platformType: widget.platformType,
        );
    if (mounted) {
      setState(() => _snapshot = value);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
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
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: <Widget>[
                if (!supported)
                  const _Info(text: '当前后端尚未提供用户侧会话撤销接口，只展示已知当前会话。'),
                for (final DeviceSession session
                    in snapshot.sessions) ...<Widget>[
                  const SizedBox(height: 10),
                  SocialCard(
                    padding: EdgeInsets.zero,
                    radius: 19,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      leading: Icon(
                        session.isCurrent
                            ? Icons.phone_android_rounded
                            : Icons.devices_other_rounded,
                      ),
                      title: Text(session.deviceName),
                      subtitle: Text(session.location),
                      trailing: session.isCurrent
                          ? const Text('当前设备')
                          : TextButton(
                              onPressed: session.canRevoke
                                  ? () => _revoke(session)
                                  : null,
                              child: const Text('移除'),
                            ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SocialPageIntro(icon: icon, title: title, description: description);
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _PageError extends StatelessWidget {
  const _PageError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.tonal(onPressed: onRetry, child: Text(message)),
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
  PermissionState.restricted => '受系统限制',
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
