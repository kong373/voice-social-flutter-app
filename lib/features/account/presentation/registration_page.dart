import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

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
  int _sex = 1;

  @override
  void dispose() {
    _nicknameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthController controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回登录',
          onPressed: controller.busy ? null : controller.cancelRegistration,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('完善资料'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(
              '手机号 ${controller.pendingPhone}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextFormField(
                    controller: _nicknameController,
                    maxLength: 16,
                    decoration: const InputDecoration(labelText: '昵称'),
                    validator: (String? value) {
                      final int length = value?.trim().length ?? 0;
                      return length >= 2 ? null : '昵称至少需要 2 个字';
                    },
                  ),
                  const SizedBox(height: 18),
                  Text('性别', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: const <ButtonSegment<int>>[
                      ButtonSegment<int>(value: 1, label: Text('男')),
                      ButtonSegment<int>(value: 2, label: Text('女')),
                    ],
                    selected: <int>{_sex},
                    onSelectionChanged: controller.busy
                        ? null
                        : (Set<int> values) =>
                            setState(() => _sex = values.first),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _inviteCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: '邀请码（选填）',
                    ),
                  ),
                ],
              ),
            ),
            if (controller.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                controller.errorMessage!,
                style: const TextStyle(color: AppColors.error),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: controller.busy ? null : _submit,
              child: controller.busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('完成注册'),
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
    await widget.controller.completeRegistration(
      RegistrationProfile(
        nickname: _nicknameController.text.trim(),
        sex: _sex,
        inviteCode: _inviteCodeController.text.trim(),
      ),
    );
  }
}
