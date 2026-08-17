import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _controller = widget.dependencies.authController
      ..addListener(_handleAuthChanged);
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
      AuthFlowStage.initializing => const _SessionRestorePage(),
      AuthFlowStage.consentRequired => ConsentPage(
          onAccept: _controller.acceptConsent,
        ),
      AuthFlowStage.signedOut => LoginPage(controller: _controller),
      AuthFlowStage.registrationRequired => RegistrationPage(
          controller: _controller,
        ),
      AuthFlowStage.signedIn => MainShell(
          dependencies: widget.dependencies,
          onSignOut: _controller.signOut,
        ),
    };
  }
}

class _SessionRestorePage extends StatelessWidget {
  const _SessionRestorePage();

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
