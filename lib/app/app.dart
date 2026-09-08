import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_gate.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_console_host.dart';
import 'package:voice_social_app/debug/qa_console/qa_gate.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';

const bool _videoRuntimeDemoRequested = bool.fromEnvironment(
  'ENABLE_VIDEO_RUNTIME_DEMO',
  defaultValue: false,
);

bool shouldUseVideoRuntimeDemo({
  required bool isLive,
  bool requested = _videoRuntimeDemoRequested,
  bool isDebug = kDebugMode,
}) => isDebug && requested && !isLive;

bool get videoRuntimeDemoEnabled => shouldUseVideoRuntimeDemo(isLive: false);

class VoiceSocialApp extends StatefulWidget {
  const VoiceSocialApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<VoiceSocialApp> createState() => _VoiceSocialAppState();
}

/// Owns the Navigator lifetime separately from token lifetime.
class AuthNavigationBoundary extends StatefulWidget {
  const AuthNavigationBoundary({
    required this.controller,
    required this.builder,
    this.navigationRevision = 0,
    super.key,
  });

  final AuthController controller;
  final Widget Function(GlobalKey<NavigatorState>) builder;
  final int navigationRevision;

  @override
  State<AuthNavigationBoundary> createState() => _AuthNavigationBoundaryState();
}

class _AuthNavigationBoundaryState extends State<AuthNavigationBoundary> {
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  int? _signedInUserId;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    _signedInUserId = controller.stage == AuthFlowStage.signedIn
        ? controller.session?.userId
        : null;
    controller.addListener(_handleAuthChanged);
  }

  void _handleAuthChanged() {
    final controller = widget.controller;
    final int? userId = controller.stage == AuthFlowStage.signedIn
        ? controller.session?.userId
        : null;
    if (_signedInUserId != null && userId != _signedInUserId) {
      // Replace the whole route owner at the next build, including root
      // dialogs. Do not pop during notifications or a Navigator transition.
      // Old mounted checks then fence async route continuations, while token
      // rotation for the same principal preserves the current route tree.
      setState(() => _navigatorKey = GlobalKey<NavigatorState>());
    }
    _signedInUserId = userId;
  }

  @override
  void didUpdateWidget(AuthNavigationBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationRevision != widget.navigationRevision) {
      _navigatorKey = GlobalKey<NavigatorState>();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleAuthChanged);
      widget.controller.addListener(_handleAuthChanged);
      _handleAuthChanged();
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(_navigatorKey);

  @override
  void dispose() {
    widget.controller.removeListener(_handleAuthChanged);
    super.dispose();
  }
}

class _VoiceSocialAppState extends State<VoiceSocialApp> {
  final GlobalKey _appGateKey = GlobalKey();
  int _navigationRevision = 0;

  void _discardProtectedRoutes() {
    if (mounted) setState(() => _navigationRevision += 1);
  }

  @override
  Widget build(BuildContext context) {
    return AppDependencyScope(
      dependencies: widget.dependencies,
      child: AuthNavigationBoundary(
        controller: widget.dependencies.authController,
        navigationRevision: _navigationRevision,
        builder: (navigatorKey) => MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Voice Social App',
          theme: AppTheme.dark(),
          home:
              shouldUseQaConsole(isLive: widget.dependencies.environment.isLive)
              ? const QaConsoleHost()
              : shouldUseVideoRuntimeDemo(
                  isLive: widget.dependencies.environment.isLive,
                )
              ? MainShell(
                  dependencies: widget.dependencies,
                  onSignOut: () async {},
                )
              : AppGate(
                  key: _appGateKey,
                  dependencies: widget.dependencies,
                  onAccessBlocked: _discardProtectedRoutes,
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.dependencies.dispose();
    super.dispose();
  }
}

class BootstrapFailureApp extends StatelessWidget {
  const BootstrapFailureApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.settings_suggest_outlined,
                  size: 42,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 20),
                Text(
                  '运行配置不完整',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message),
                const SizedBox(height: 12),
                Text(
                  '请补齐安全的 dart-define 参数后重新启动。生产密钥不得写入仓库。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
