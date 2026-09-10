import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';
import '../domain/registration_avatar.dart';
import 'preset_avatar_view.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({required this.controller, super.key});

  final AuthController controller;

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  int? _sex;
  String? _presetId;
  String? _choiceError;

  @override
  void dispose() {
    _nicknameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthController controller = widget.controller;
    return SocialPageScaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回登录',
          onPressed: controller.busy ? null : controller.cancelRegistration,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('完善资料'),
      ),
      bottomNavigationBar: AccountBottomActionBar(
        child: AccountPrimaryAction(
          label: '完成注册',
          busy: controller.busy,
          onPressed: _submit,
        ),
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
          children: <Widget>[
            const AccountMistHero(
              eyebrow: 'NEW PROFILE',
              title: '留下你的声音名片',
              subtitle: '一个好记的昵称，能让房间里的朋友更快认识你',
              markSize: 56,
            ),
            const SizedBox(height: 20),
            AccountStatusPill(
              label: '已验证 · ${controller.pendingPhone}',
              color: AppColors.success,
            ),
            const SizedBox(height: 12),
            AccountSheet(
              padding: const EdgeInsets.fromLTRB(14, 15, 14, 17),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('选择头像', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    PresetAvatarPicker(
                      selectedId: _presetId,
                      enabled: !controller.busy,
                      onSelected: (id) => setState(() {
                        _presetId = id;
                        _choiceError = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nicknameController,
                      maxLength: 24,
                      decoration: const InputDecoration(
                        labelText: '昵称',
                        hintText: '1—24 个字符',
                        prefixIcon: Icon(Icons.face_retouching_natural_rounded),
                      ),
                      validator: (String? value) {
                        final int length = value?.trim().length ?? 0;
                        return length >= 1 && length <= 24
                            ? null
                            : '请填写 1—24 个字符的昵称';
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '性别',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AccountOxygenColors.ink,
                      ),
                    ),
                    const SizedBox(height: 9),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        segments: const <ButtonSegment<int>>[
                          ButtonSegment<int>(value: 0, label: Text('不公开')),
                          ButtonSegment<int>(
                            value: 1,
                            icon: Icon(Icons.male_rounded, size: 17),
                            label: Text('男'),
                          ),
                          ButtonSegment<int>(
                            value: 2,
                            icon: Icon(Icons.female_rounded, size: 17),
                            label: Text('女'),
                          ),
                        ],
                        emptySelectionAllowed: true,
                        selected: <int>{if (_sex != null) _sex!},
                        onSelectionChanged: controller.busy
                            ? null
                            : (Set<int> values) => setState(() {
                                _sex = values.isEmpty ? null : values.first;
                                _choiceError = null;
                              }),
                      ),
                    ),
                    const SizedBox(height: 13),
                    TextFormField(
                      controller: _inviteCodeController,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: '邀请码（选填）',
                        prefixIcon: const Icon(
                          Icons.confirmation_number_outlined,
                        ),
                        suffixIcon: _inviteCodeController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '移除邀请码',
                                onPressed: controller.busy
                                    ? null
                                    : () =>
                                          setState(_inviteCodeController.clear),
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    if (_choiceError != null)
                      Text(
                        _choiceError!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                  ],
                ),
              ),
            ),
            if (controller.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                controller.errorMessage!,
                style: const TextStyle(color: AppColors.error),
              ),
            ],
            const SizedBox(height: 14),
            const AccountNoticeStrip(
              icon: Icons.visibility_outlined,
              text: '昵称会展示在个人主页、房间座位和消息会话中，之后可在个人资料中修改。',
              tone: AccountOxygenColors.cyan,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_sex == null || _presetId == null) {
      setState(() => _choiceError = '请选择头像和性别');
      return;
    }
    await widget.controller.completeRegistration(
      RegistrationProfile(
        nickname: _nicknameController.text,
        sex: _sex!,
        avatar: RegistrationAvatarChoice.preset(_presetId!),
        inviteCode: _inviteCodeController.text.trim(),
      ),
    );
  }
}
