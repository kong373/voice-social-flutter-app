import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';
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
    final String? developmentCode = controller.developmentSmsCode;
    return SocialPageScaffold(
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(22, 36, 22, 26),
          children: <Widget>[
            const AccountMistHero(
              eyebrow: 'VOICE SOCIAL',
              title: '听见同频的人',
              subtitle: '登录后继续你的房间、好友和消息旅程',
              markSize: 68,
            ),
            const SizedBox(height: 30),
            Text(
              '手机号登录',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: AccountOxygenColors.ink),
            ),
            const SizedBox(height: 12),
            AccountSheet(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      autofillHints: const <String>[
                        AutofillHints.telephoneNumber,
                      ],
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: const InputDecoration(
                        labelText: '手机号码',
                        hintText: '请输入手机号',
                        prefixText: '+86  ',
                        prefixIcon: Icon(Icons.phone_iphone_rounded),
                      ),
                      validator: (String? value) {
                        final String phone = value?.trim() ?? '';
                        return RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)
                            ? null
                            : '请输入正确的手机号码';
                      },
                    ),
                    const SizedBox(height: 12),
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
                        hintText: '6 位验证码',
                        prefixIcon: const Icon(Icons.sms_outlined),
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
                    const SizedBox(height: 18),
                    AccountPrimaryAction(
                      label: '登录 / 注册',
                      busy: controller.busy,
                      onPressed: _signIn,
                    ),
                  ],
                ),
              ),
            ),
            if (developmentCode != null) ...<Widget>[
              const SizedBox(height: 12),
              _DevelopmentCodeNotice(code: developmentCode),
            ],
            if (controller.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              _ErrorNotice(message: controller.errorMessage!),
            ],
            const SizedBox(height: 14),
            Text(
              '未注册手机号会在验证后进入资料完善。实时语音、即时消息与支付渠道仍会在厂商适配器接入前保持不可用。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AccountOxygenColors.muted,
                height: 1.5,
              ),
            ),
            if (widget.showLiveReadiness &&
                widget.liveReadinessService != null) ...<Widget>[
              const SizedBox(height: 12),
              TextButton.icon(
                key: const Key('live-backend-readiness-entry'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => LiveBackendReadinessPage(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入正确的手机号码')));
      return;
    }
    FocusScope.of(context).unfocus();
    final bool sent = await widget.controller.sendSmsCode(phone);
    if (!mounted || !sent) {
      return;
    }
    final SmsChallenge? challenge = widget.controller.lastSmsChallenge;
    final String? developmentCode = challenge?.developmentCode;
    if (developmentCode != null) {
      _codeController.text = developmentCode;
      _codeController.selection = TextSelection.collapsed(
        offset: developmentCode.length,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          developmentCode == null ? '验证码挑战已创建，请查收短信' : '开发环境验证码已安全回读并填入',
        ),
      ),
    );
    _startCountdown(challenge?.retryAfter ?? 60);
  }

  void _startCountdown(int seconds) {
    setState(() => _secondsRemaining = seconds < 1 ? 1 : seconds);
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

class _DevelopmentCodeNotice extends StatelessWidget {
  const _DevelopmentCodeNotice({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.science_outlined, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text('仅开发环境可见：验证码 $code')),
        ],
      ),
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
