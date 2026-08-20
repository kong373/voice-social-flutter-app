import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

class AccountRestrictionPage extends StatefulWidget {
  const AccountRestrictionPage({
    required this.account,
    required this.currentVersion,
    required this.platformType,
    super.key,
  });

  final String account;
  final int currentVersion;
  final int platformType;

  @override
  State<AccountRestrictionPage> createState() => _AccountRestrictionPageState();
}

class _AccountRestrictionPageState extends State<AccountRestrictionPage> {
  AccountRestriction? _restriction;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restriction == null) {
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
      setState(() => _restriction = value.restriction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AccountRestriction? restriction = _restriction;
    return Scaffold(
      appBar: AppBar(title: const Text('账号状态')),
      body: restriction == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(22),
              child: _Header(
                icon: restriction.isRestricted
                    ? Icons.block_rounded
                    : Icons.verified_user_outlined,
                title: restriction.isRestricted ? '账号存在限制' : '账号状态正常',
                description: restriction.isRestricted
                    ? restriction.reason
                    : '当前没有检测到账号、设备或公屏处罚。',
              ),
            ),
    );
  }
}

class AccountAppealPage extends StatefulWidget {
  const AccountAppealPage({required this.account, super.key});

  final String account;

  @override
  State<AccountAppealPage> createState() => _AccountAppealPageState();
}

class _AccountAppealPageState extends State<AccountAppealPage> {
  final TextEditingController _explanationController = TextEditingController();
  String _reasonType = '1';
  AppealCase? _appeal;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appeal == null) {
      _query();
    }
  }

  @override
  void dispose() {
    _explanationController.dispose();
    super.dispose();
  }

  Future<void> _query() async {
    final AppealCase value = await AppDependencyScope.of(context)
        .accountComplianceRepository
        .queryAppeal(account: widget.account, reasonType: _reasonType);
    if (mounted) {
      setState(() => _appeal = value);
    }
  }

  Future<void> _submit() async {
    if (_busy || _explanationController.text.trim().length < 10) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('申诉说明至少填写 10 个字')));
      return;
    }
    setState(() => _busy = true);
    try {
      final AppealCase value = await AppDependencyScope.of(context)
          .accountComplianceRepository
          .submitAppeal(
            account: widget.account,
            nickname: _appeal?.nickname ?? '当前用户',
            reason: _appeal?.reason ?? '账号处罚',
            reasonType: _reasonType,
            explanation: _explanationController.text.trim(),
          );
      if (mounted) {
        setState(() => _appeal = value);
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
    final AppealCase? appeal = _appeal;
    return Scaffold(
      appBar: AppBar(title: const Text('处罚申诉')),
      body: appeal == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                _Header(
                  icon: Icons.fact_check_outlined,
                  title: _appealStateLabel(appeal.state),
                  description: appeal.processText,
                ),
                const SizedBox(height: 18),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(value: '1', label: Text('账号安全')),
                    ButtonSegment<String>(value: '3', label: Text('内容处罚')),
                  ],
                  selected: <String>{_reasonType},
                  onSelectionChanged: (Set<String> value) {
                    setState(() => _reasonType = value.first);
                    _query();
                  },
                ),
                const SizedBox(height: 14),
                Text('处罚原因：${appeal.reason.isEmpty ? '待平台返回' : appeal.reason}'),
                if (appeal.state == AppealState.none) ...<Widget>[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _explanationController,
                    minLines: 5,
                    maxLines: 8,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: '申诉说明'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? '提交中…' : '提交申诉'),
                  ),
                ],
                if (appeal.resultText.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  _Info(text: appeal.resultText),
                ],
              ],
            ),
    );
  }
}

class AccountCancellationPage extends StatefulWidget {
  const AccountCancellationPage({
    required this.account,
    required this.currentVersion,
    required this.platformType,
    super.key,
  });

  final String account;
  final int currentVersion;
  final int platformType;

  @override
  State<AccountCancellationPage> createState() =>
      _AccountCancellationPageState();
}

class _AccountCancellationPageState extends State<AccountCancellationPage> {
  final TextEditingController _codeController = TextEditingController();
  CancellationEligibility? _eligibility;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_eligibility == null) {
      _load();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final CancellationEligibility value = await AppDependencyScope.of(
      context,
    ).accountComplianceRepository.queryCancellationEligibility();
    if (mounted) {
      setState(() => _eligibility = value);
    }
  }

  Future<void> _sendCode() async {
    final bool sent = await AppDependencyScope.of(
      context,
    ).authController.sendSmsCode(widget.account);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(sent ? '验证码已发送' : '验证码发送失败')));
    }
  }

  Future<void> _submit() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('确认申请注销？'),
        content: const Text('注销后资料、关系和资金记录将按平台规则处理。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await AppDependencyScope.of(context).accountComplianceRepository
          .requestCancellation(smsCode: _codeController.text.trim());
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
    final CancellationEligibility? eligibility = _eligibility;
    return Scaffold(
      appBar: AppBar(title: const Text('账号注销')),
      body: eligibility == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                _Header(
                  icon: Icons.person_remove_alt_1_outlined,
                  title: eligibility.allowed ? '可以申请注销' : '暂不能申请注销',
                  description: eligibility.message,
                ),
                if (eligibility.allowed &&
                    eligibility.requiresSmsCode) ...<Widget>[
                  const SizedBox(height: 18),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: '短信验证码',
                      suffixIcon: TextButton(
                        onPressed: _sendCode,
                        child: const Text('获取'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? '提交中…' : '申请注销'),
                  ),
                ],
              ],
            ),
    );
  }
}

class VersionUpgradePage extends StatefulWidget {
  const VersionUpgradePage({
    required this.currentVersion,
    required this.platformType,
    super.key,
  });

  final int currentVersion;
  final int platformType;

  @override
  State<VersionUpgradePage> createState() => _VersionUpgradePageState();
}

class _VersionUpgradePageState extends State<VersionUpgradePage> {
  VersionUpdateInfo? _info;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_info == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final VersionUpdateInfo value = await AppDependencyScope.of(context)
        .accountComplianceRepository
        .checkVersion(
          currentVersion: widget.currentVersion,
          platformType: widget.platformType,
        );
    if (mounted) {
      setState(() => _info = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final VersionUpdateInfo? info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('版本升级')),
      body: info == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(22),
              children: <Widget>[
                _Header(
                  icon: Icons.system_update_alt_rounded,
                  title: info.hasUpdate
                      ? '发现新版本 ${info.versionName}'
                      : '当前已是最新版本',
                  description: info.releaseNotes.isEmpty
                      ? '暂无版本说明。'
                      : info.releaseNotes,
                ),
                if (info.hasUpdate) ...<Widget>[
                  const SizedBox(height: 18),
                  _Info(
                    text: info.packageUrl.isEmpty
                        ? '安装渠道尚未配置，当前不会伪造下载或升级成功。'
                        : '服务端已返回升级地址，正式渠道适配后执行升级。',
                  ),
                ],
              ],
            ),
    );
  }
}

class YouthModePage extends StatefulWidget {
  const YouthModePage({
    required this.account,
    required this.currentVersion,
    required this.platformType,
    super.key,
  });

  final String account;
  final int currentVersion;
  final int platformType;

  @override
  State<YouthModePage> createState() => _YouthModePageState();
}

class _YouthModePageState extends State<YouthModePage> {
  final TextEditingController _pinController = TextEditingController();
  AccountComplianceSnapshot? _snapshot;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null) {
      _load();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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

  Future<void> _toggle() async {
    if (!RegExp(r'^\d{4}$').hasMatch(_pinController.text) || _busy) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 4 位数字密码')));
      return;
    }
    setState(() => _busy = true);
    try {
      await AppDependencyScope.of(
        context,
      ).accountComplianceRepository.setYouthMode(
        enabled: !_snapshot!.youthModeEnabled,
        pin: _pinController.text,
      );
      _pinController.clear();
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
    final AccountComplianceSnapshot? snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('青少年模式')),
      body: snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                _Header(
                  icon: Icons.child_care_rounded,
                  title: snapshot.youthModeEnabled ? '青少年模式已开启' : '青少年模式未开启',
                  description: '只限制创建新的充值订单，不影响进房、消息和社交。',
                ),
                const SizedBox(height: 14),
                const _Info(text: '钱包查询、订单查询、退款、进房、消息和其他正常社交能力不被禁用。'),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: snapshot.youthModeEnabled ? '关闭密码' : '设置 4 位密码',
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _toggle,
                  child: Text(
                    _busy
                        ? '提交中…'
                        : snapshot.youthModeEnabled
                        ? '关闭青少年模式'
                        : '开启青少年模式',
                  ),
                ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 42, color: AppColors.primary),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(description, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
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

String _appealStateLabel(AppealState state) => switch (state) {
  AppealState.none => '可提交申诉',
  AppealState.pending => '申诉审核中',
  AppealState.approved => '申诉已通过',
  AppealState.rejected => '申诉未通过',
};

String _messageFor(Object error) =>
    error is ApiException ? error.message : '操作失败，请稍后重试';
