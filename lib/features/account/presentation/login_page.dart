import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/presentation/live_backend_readiness_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.controller,
    this.liveReadinessService,
    this.showLiveReadiness = false,
    super.key,
  });

  final AuthController controller;
  final LiveBackendReadinessService? liveReadinessService;
  final bool showLiveReadiness;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  Timer? _timer;
  int _secondsRemaining = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthController controller = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 54, 24, 28),
          children: <Widget>[
            Text(
              '手机号登录',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              '登录后可以进入语音房、申请上麦、发送消息和建立社交关系。',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 34),
            Form(
              key: _formKey,
              child: Column(
                children: <Widget>[
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    autofillHints: const <String>[AutofillHints.telephoneNumber],
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    decoration: const InputDecoration(
                      labelText: '手机号码',
                      prefixText: '+86  ',
                    ),
                    validator: (String? value) {
                      final String phone = value?.trim() ?? '';
                      return RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)
                          ? null
                          : '请输入正确的手机号码';
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    autofillHints: const <String>[AutofillHints.oneTimeCode],
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: '短信验证码',
                      suffixIcon: TextButton(
                        onPressed:
                            controller.sendingCode || _secondsRemaining > 0
                                ? null
                                : _sendCode,
                        child: Text(
                          _secondsRemaining > 0
                              ? '${_secondsRemaining}s'
                              : controller.sendingCode
                                  ? '发送中'
                                  : '获取验证码',
                        ),
                      ),
                    ),
                    validator: (String? value) =>
                        (value?.trim().length ?? 0) == 6
                            ? null
                            : '请输入 6 位验证码',
                  ),
                ],
              ),
            ),
            if (controller.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              _ErrorNotice(message: controller.errorMessage!),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: controller.busy ? null : _signIn,
                child: controller.busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录 / 注册'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '未注册手机号将在验证通过后进入资料完善流程。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.showLiveReadiness &&
                widget.liveReadinessService != null) ...<Widget>[
              const SizedBox(height: 12),
              TextButton.icon(
                key: const Key('live-backend-readiness-entry'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        LiveBackendReadinessPage(
                      service: widget.liveReadinessService!,
                    ),
                  ),
                ),
                icon: const Icon(Icons.cloud_sync_outlined),
                label: const Text('开发环境联调诊断'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sendCode() async {
    final String phone = _phoneController.text.trim();
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入正确的手机号码')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final bool sent = await widget.controller.sendSmsCode(phone);
    if (!mounted || !sent) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('验证码已发送')),
    );
    setState(() => _secondsRemaining = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining -= 1);
      }
    });
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.signInWithSms(
      phone: _phoneController.text,
      smsCode: _codeController.text,
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
