import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';
import 'package:voice_social_app/features/account/presentation/consent_page.dart';
import 'package:voice_social_app/features/account/presentation/login_page.dart';
import 'package:voice_social_app/features/account/presentation/registration_page.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

class AppGate extends StatefulWidget {
  const AppGate({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  late final AuthController _controller;
  late final LiveBackendReadinessService _liveReadinessService;

  @override
  void initState() {
    super.initState();
    _controller = widget.dependencies.authController
      ..addListener(_handleAuthChanged);
    _liveReadinessService = LiveBackendReadinessService(
      environment: widget.dependencies.environment,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.initialize();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_controller.stage) {
      AuthFlowStage.initializing => const SessionRestorePage(),
      AuthFlowStage.consentRequired => ConsentPage(
        onAccept: _controller.acceptConsent,
      ),
      AuthFlowStage.signedOut => LoginPage(
        controller: _controller,
        showLiveReadiness: widget.dependencies.environment.isLive,
        liveReadinessService: _liveReadinessService,
      ),
      AuthFlowStage.registrationRequired => RegistrationPage(
        controller: _controller,
      ),
      AuthFlowStage.recoveryRequired => SessionRecoveryPage(
        busy: _controller.busy,
        message: _controller.errorMessage,
        onRetry: _controller.retrySessionRecovery,
        onSignOut: _controller.discardSessionAndSignOut,
      ),
      AuthFlowStage.signedIn => MainShell(
        dependencies: widget.dependencies,
        onSignOut: _controller.signOut,
      ),
    };
  }
}

class SessionRestorePage extends StatelessWidget {
  const SessionRestorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 52, 30, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const AccountBrandMark(size: 76),
              const SizedBox(height: 22),
              Text(
                '正在回到声音世界',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AccountOxygenColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '正在安全恢复你的登录状态与房间会话',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AccountOxygenColors.muted,
                ),
              ),
              const SizedBox(height: 26),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: const SizedBox(
                  width: 112,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Color(0xFFE7E7F2),
                    color: AccountOxygenColors.violet,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionRecoveryPage extends StatelessWidget {
  const SessionRecoveryPage({
    required this.busy,
    required this.onRetry,
    required this.onSignOut,
    this.message,
    super.key,
  });

  final bool busy;
  final String? message;
  final Future<bool> Function() onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
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
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF2E4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_off_rounded,
                        size: 29,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      '暂时无法恢复登录',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AccountOxygenColors.ink,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message ?? '网络或服务暂时不可用，你的本地会话仍被安全保留。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    AccountPrimaryAction(
                      key: const Key('retry-session-recovery'),
                      label: '重新连接',
                      busy: busy,
                      icon: Icons.refresh_rounded,
                      onPressed: () => onRetry(),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        key: const Key('discard-session-and-sign-out'),
                        onPressed: busy ? null : onSignOut,
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
