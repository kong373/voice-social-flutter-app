import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_compliance_error.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';

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
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restriction == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _error = null);
    }
    try {
      final scope = AppDependencyScope.of(context);
      final AccountComplianceSnapshot value = await scope
          .accountComplianceRepository
          .fetchSnapshot(
            account: widget.account,
            expectedUserId: scope.sessionManager.session?.userId,
            currentVersion: widget.currentVersion,
            platformType: widget.platformType,
          );
      if (mounted) {
        setState(() {
          _restriction = value.restriction;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AccountRestriction? restriction = _restriction;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('账号状态')),
      body: restriction == null
          ? _error == null
                ? const AccountCompactProgress(label: '正在检查账号状态')
                : AccountComplianceError(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: <Widget>[
                AccountStatusHero(
                  icon: restriction.isRestricted
                      ? Icons.block_rounded
                      : Icons.verified_user_outlined,
                  title: restriction.isRestricted ? '账号存在限制' : '账号状态正常',
                  description: restriction.isRestricted
                      ? restriction.reason
                      : '当前没有检测到账号、设备或公屏处罚。',
                  tone: restriction.isRestricted
                      ? AppColors.warning
                      : AppColors.success,
                  badge: restriction.isRestricted ? '需要处理' : '状态良好',
                ),
                const SizedBox(height: 16),
                AccountSheet(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  child: Column(
                    children: <Widget>[
                      AccountSettingRow(
                        icon: Icons.person_outline_rounded,
                        title: '账号权限',
                        trailingLabel: restriction.isRestricted ? '受限' : '正常',
                        tone: restriction.isRestricted
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                      AccountSettingRow(
                        icon: Icons.phone_android_rounded,
                        title: '设备状态',
                        trailingLabel: restriction.isRestricted ? '需核验' : '正常',
                        tone: const Color(0xFF5D84E8),
                      ),
                      AccountSettingRow(
                        icon: Icons.forum_outlined,
                        title: '公屏互动',
                        trailingLabel: restriction.isRestricted
                            ? '以处罚为准'
                            : '正常',
                        tone: AccountOxygenColors.cyan,
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const AccountNoticeStrip(
                  icon: Icons.sync_rounded,
                  text: '账号限制以服务端状态为准，本页不会通过本地开关绕过处罚。',
                  tone: AccountOxygenColors.violet,
                ),
              ],
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
  String? _error;
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
    if (mounted) {
      setState(() {
        _appeal = null;
        _error = null;
      });
    }
    try {
      final AppealCase value = await AppDependencyScope.of(context)
          .accountComplianceRepository
          .queryAppeal(account: widget.account, reasonType: _reasonType);
      if (mounted) {
        setState(() {
          _appeal = value;
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
    final AppealCase? appeal = _appeal;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('处罚申诉')),
      body: appeal == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : AccountComplianceError(message: _error!, onRetry: _query)
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: <Widget>[
                AccountStatusHero(
                  icon: Icons.fact_check_outlined,
                  title: _appealStateLabel(appeal.state),
                  description: appeal.processText,
                  tone: appeal.state == AppealState.approved
                      ? AppColors.success
                      : appeal.state == AppealState.rejected
                      ? AppColors.error
                      : AccountOxygenColors.violet,
                  badge: appeal.state == AppealState.none ? '可提交' : '平台进度',
                ),
                const SizedBox(height: 18),
                const AccountSectionLabel(text: '申诉类型与说明'),
                AccountSheet(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const <ButtonSegment<String>>[
                            ButtonSegment<String>(
                              value: '1',
                              label: Text('账号安全'),
                            ),
                            ButtonSegment<String>(
                              value: '3',
                              label: Text('内容处罚'),
                            ),
                          ],
                          selected: <String>{_reasonType},
                          onSelectionChanged: (Set<String> value) {
                            setState(() => _reasonType = value.first);
                            _query();
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '处罚原因：${appeal.reason.isEmpty ? '待平台返回' : appeal.reason}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (appeal.state == AppealState.none) ...<Widget>[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _explanationController,
                          minLines: 5,
                          maxLines: 8,
                          maxLength: 500,
                          decoration: const InputDecoration(
                            labelText: '申诉说明',
                            alignLabelWithHint: true,
                          ),
                        ),
                        AccountPrimaryAction(
                          label: '提交申诉',
                          busy: _busy,
                          onPressed: _submit,
                        ),
                      ],
                    ],
                  ),
                ),
                if (appeal.resultText.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  AccountNoticeStrip(
                    icon: Icons.schedule_rounded,
                    text: appeal.resultText,
                    tone: AccountOxygenColors.cyan,
                  ),
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
  String? _error;
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
    if (mounted) {
      setState(() => _error = null);
    }
    try {
      final CancellationEligibility value = await AppDependencyScope.of(
        context,
      ).accountComplianceRepository.queryCancellationEligibility();
      if (mounted) {
        setState(() {
          _eligibility = value;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  Future<void> _sendCode() async {
    try {
      final bool sent = await AppDependencyScope.of(
        context,
      ).authController.sendSmsCode(widget.account);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(sent ? '验证码已发送' : '验证码发送失败')));
      }
    } catch (error) {
      if (mounted) {
        showAccountComplianceRetrySnackBar(
          context,
          message: _messageFor(error),
          onRetry: _sendCode,
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
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

  Future<void> _cancelDeletion() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final CancellationEligibility value = await AppDependencyScope.of(
        context,
      ).accountComplianceRepository.cancelDeletion();
      if (mounted) {
        setState(() => _eligibility = value);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('注销申请已撤销')));
      }
    } catch (error) {
      if (mounted) {
        showAccountComplianceRetrySnackBar(
          context,
          message: _messageFor(error),
          onRetry: _cancelDeletion,
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
    final CancellationEligibility? eligibility = _eligibility;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('账号注销')),
      body: eligibility == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : AccountComplianceError(message: _error!, onRetry: _load)
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: <Widget>[
                AccountStatusHero(
                  icon: Icons.person_remove_alt_1_outlined,
                  title: eligibility.canCancel
                      ? '注销冷静期中'
                      : eligibility.allowed
                      ? '可以申请注销'
                      : '暂不能申请注销',
                  description: eligibility.message,
                  tone: eligibility.canCancel
                      ? AppColors.warning
                      : eligibility.allowed
                      ? AppColors.warning
                      : AccountOxygenColors.violet,
                  badge: eligibility.canCancel
                      ? '可撤销'
                      : eligibility.allowed
                      ? '高风险操作'
                      : '条件未满足',
                ),
                const SizedBox(height: 14),
                const AccountNoticeStrip(
                  icon: Icons.warning_amber_rounded,
                  text: '注销会影响资料、关系与账号访问，请先确认钱包和其他未完成事项。',
                  tone: AppColors.warning,
                ),
                if (eligibility.canCancel) ...<Widget>[
                  const SizedBox(height: 18),
                  const AccountSectionLabel(text: '注销冷静期'),
                  AccountSheet(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                    child: Column(
                      children: <Widget>[
                        AccountNoticeStrip(
                          icon: Icons.schedule_rounded,
                          text: eligibility.coolingEndsAt.isEmpty
                              ? '服务端确认账号正在注销冷静期内，可撤销本次注销申请。'
                              : '服务端确认账号正在注销冷静期内，预计截止 ${eligibility.coolingEndsAt}。',
                          tone: AppColors.warning,
                        ),
                        const SizedBox(height: 14),
                        AccountPrimaryAction(
                          label: '撤销注销',
                          icon: Icons.undo_rounded,
                          busy: _busy,
                          onPressed: _cancelDeletion,
                        ),
                      ],
                    ),
                  ),
                ],
                if (eligibility.allowed && !eligibility.canCancel) ...<Widget>[
                  const SizedBox(height: 18),
                  AccountSectionLabel(
                    text: eligibility.requiresSmsCode ? '验证当前手机号' : '确认注销申请',
                  ),
                  AccountSheet(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                    child: Column(
                      children: <Widget>[
                        if (eligibility.requiresSmsCode)
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            decoration: InputDecoration(
                              labelText: '短信验证码',
                              prefixIcon: const Icon(Icons.sms_outlined),
                              suffixIcon: TextButton(
                                onPressed: _sendCode,
                                child: const Text('获取'),
                              ),
                            ),
                          )
                        else
                          const AccountNoticeStrip(
                            icon: Icons.verified_user_outlined,
                            text: '当前第一方流程采用服务端明确确认并进入 7 天冷静期，不伪造短信验证。',
                            tone: AccountOxygenColors.violet,
                          ),
                        const SizedBox(height: 14),
                        AccountPrimaryAction(
                          label: '申请注销',
                          busy: _busy,
                          onPressed: _submit,
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
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_info == null && _error == null) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _error = null);
    }
    try {
      final VersionUpdateInfo value = await AppDependencyScope.of(context)
          .accountComplianceRepository
          .checkVersion(
            currentVersion: widget.currentVersion,
            platformType: widget.platformType,
          );
      if (mounted) {
        setState(() {
          _info = value;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VersionUpdateInfo? info = _info;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('版本升级')),
      body: info == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : AccountComplianceError(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: <Widget>[
                AccountStatusHero(
                  icon: Icons.system_update_alt_rounded,
                  title: info.hasUpdate
                      ? '发现新版本 ${info.versionName}'
                      : '当前已是最新版本',
                  description: info.releaseNotes.isEmpty
                      ? '暂无版本说明。'
                      : info.releaseNotes,
                  tone: info.hasUpdate
                      ? AccountOxygenColors.violet
                      : AppColors.success,
                  badge: info.hasUpdate ? '可升级' : '最新版本',
                ),
                const SizedBox(height: 18),
                const AccountSectionLabel(text: '版本信息'),
                AccountSheet(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  child: Column(
                    children: <Widget>[
                      AccountSettingRow(
                        icon: Icons.apps_rounded,
                        title: '当前内部版本',
                        trailingLabel: '${widget.currentVersion}',
                        tone: const Color(0xFF5D84E8),
                      ),
                      AccountSettingRow(
                        icon: Icons.system_update_rounded,
                        title: '更新状态',
                        trailingLabel: info.hasUpdate ? '发现更新' : '无需更新',
                        tone: info.hasUpdate
                            ? AccountOxygenColors.violet
                            : AppColors.success,
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
                if (info.hasUpdate) ...<Widget>[
                  const SizedBox(height: 12),
                  AccountNoticeStrip(
                    icon: Icons.info_outline_rounded,
                    text: info.packageUrl.isEmpty
                        ? '安装渠道尚未配置，当前不会伪造下载或升级成功。'
                        : '服务端已返回升级地址，正式渠道适配后执行升级。',
                    tone: AppColors.warning,
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
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _error == null) {
      _load();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _error = null);
    }
    try {
      final scope = AppDependencyScope.of(context);
      final AccountComplianceSnapshot value = await scope
          .accountComplianceRepository
          .fetchSnapshot(
            account: widget.account,
            expectedUserId: scope.sessionManager.session?.userId,
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
        showAccountComplianceRetrySnackBar(
          context,
          message: _messageFor(error),
          onRetry: _toggle,
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
    final AccountComplianceSnapshot? snapshot = _snapshot;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('青少年模式')),
      body: snapshot == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : AccountComplianceError(message: _error!, onRetry: _load)
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: <Widget>[
                AccountStatusHero(
                  icon: Icons.child_care_rounded,
                  title: snapshot.youthModeEnabled ? '青少年模式已开启' : '青少年模式未开启',
                  description: '只限制创建新的充值订单，不影响进房、消息和社交。',
                  tone: snapshot.youthModeEnabled
                      ? AppColors.success
                      : const Color(0xFF5D84E8),
                  badge: snapshot.youthModeEnabled ? '保护中' : '未开启',
                ),
                const SizedBox(height: 14),
                const AccountNoticeStrip(
                  icon: Icons.info_outline_rounded,
                  text: '钱包查询、订单查询、退款、进房、消息和其他正常社交能力不被禁用。',
                  tone: AccountOxygenColors.cyan,
                ),
                const SizedBox(height: 18),
                AccountSheet(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    children: <Widget>[
                      TextField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          labelText: snapshot.youthModeEnabled
                              ? '关闭密码'
                              : '设置 4 位密码',
                          prefixIcon: const Icon(Icons.password_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AccountPrimaryAction(
                        label: snapshot.youthModeEnabled
                            ? '关闭青少年模式'
                            : '开启青少年模式',
                        busy: _busy,
                        onPressed: _toggle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
