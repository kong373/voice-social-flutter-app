import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
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
    return const Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF21183F), AppColors.background],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 18),
              Text('正在恢复登录状态…'),
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 48,
                    color: AppColors.warning,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '暂时无法恢复登录',
                    style: Theme.of(context).textTheme.headlineSmall,
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
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('retry-session-recovery'),
                      onPressed: busy ? null : () => onRetry(),
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('重新连接'),
                    ),
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
    );
  }
}
