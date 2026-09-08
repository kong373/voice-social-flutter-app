import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/live_backend_readiness.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/presentation/account_oxygen_components.dart';
import 'package:voice_social_app/features/account/presentation/account_access_gate_page.dart';
import 'package:voice_social_app/features/account/presentation/consent_page.dart';
import 'package:voice_social_app/features/account/presentation/login_page.dart';
import 'package:voice_social_app/features/account/presentation/registration_page.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';
import 'package:voice_social_app/features/version/presentation/app_version_gate_page.dart';

class AppGate extends StatefulWidget {
  const AppGate({required this.dependencies, this.onAccessBlocked, super.key});

  final AppDependencies dependencies;

  /// The app owner discards its protected Navigator, not an animated pop.
  final VoidCallback? onAccessBlocked;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  late final AuthController _controller;
  late final LiveBackendReadinessService _liveReadinessService;
  Future<void>? _livePreflight;
  AccountComplianceSnapshot? _liveCompliance;
  String? _livePreflightError;
  bool _versionDeferred = false;
  AuthSession? _preflightSession;
  AuthSession? _appleIapRecoverySession;
  bool _appleRecoveryInFlight = false;
  int _appleRecoveryAttempts = 0;
  Timer? _appleRecoveryRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.dependencies.authController
      ..addListener(_handleAuthChanged);
    _liveReadinessService = LiveBackendReadinessService(
      environment: widget.dependencies.environment,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.stage == AuthFlowStage.initializing) {
        _controller.initialize();
      } else {
        // A replaced Navigator must consume the current auth result, never
        // restore credentials again or erase the session-expiry explanation.
        _handleAuthChanged();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appleRecoveryRetry?.cancel();
    _controller.removeListener(_handleAuthChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appleIapRecoverySession = null;
      _appleRecoveryAttempts = 0;
      _appleRecoveryRetry?.cancel();
      unawaited(_attemptAppleRecovery());
    }
  }

  Future<void> _attemptAppleRecovery() async {
    final AuthSession? session = _controller.session;
    if (!mounted ||
        _controller.stage != AuthFlowStage.signedIn ||
        session == null ||
        _appleRecoveryInFlight ||
        identical(_appleIapRecoverySession, session)) {
      return;
    }
    _appleRecoveryInFlight = true;
    final bool recovered = await widget.dependencies
        .recoverAppleIapAfterAuthentication();
    _appleRecoveryInFlight = false;
    if (!mounted) {
      return;
    }
    if (!identical(_controller.session, session)) {
      _appleRecoveryAttempts = 0;
      unawaited(_attemptAppleRecovery());
      return;
    }
    if (recovered) {
      _appleIapRecoverySession = session;
      _appleRecoveryAttempts = 0;
      return;
    }
    const delays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ];
    if (_appleRecoveryAttempts < delays.length) {
      _appleRecoveryRetry?.cancel();
      _appleRecoveryRetry = Timer(delays[_appleRecoveryAttempts++], () {
        unawaited(_attemptAppleRecovery());
      });
    }
  }

  void _handleAuthChanged() {
    // A rotated credential for the same identity must not dispose MainShell
    // (and its selected tab) while the next status check is in flight. Keep
    // only a previously verified snapshot; a new identity has no such grant.
    // Failure/restriction from the fresh check still replaces it below.
    if (!identical(_preflightSession, _controller.session)) {
      if (_controller.stage != AuthFlowStage.signedIn ||
          !_sameSessionIdentity(_preflightSession, _controller.session)) {
        _liveCompliance = null;
        _livePreflightError = null;
        _versionDeferred = false;
      }
      _preflightSession = null;
    }
    if (mounted) {
      setState(() {});
    }
    if (_controller.stage == AuthFlowStage.signedIn) {
      final AuthSession? session = _controller.session;
      if (session != null && !identical(_appleIapRecoverySession, session)) {
        unawaited(_attemptAppleRecovery());
      }
      _startLivePreflightIfNeeded();
    } else {
      _appleIapRecoverySession = null;
      _appleRecoveryAttempts = 0;
      _appleRecoveryRetry?.cancel();
      _resetLivePreflight();
    }
  }

  bool _sameSessionIdentity(AuthSession? previous, AuthSession? current) =>
      previous != null &&
      current != null &&
      previous.userId == current.userId &&
      previous.deviceId == current.deviceId &&
      previous.clientId == current.clientId &&
      previous.mobile == current.mobile &&
      previous.roles == current.roles;

  void _resetLivePreflight() {
    if (_controller.stage == AuthFlowStage.signedIn) {
      return;
    }
    _liveCompliance = null;
    _livePreflightError = null;
    _versionDeferred = false;
    _preflightSession = null;
  }

  void _startLivePreflightIfNeeded({bool force = false}) {
    if (!widget.dependencies.environment.isLive ||
        _controller.stage != AuthFlowStage.signedIn) {
      return;
    }
    final AuthSession? session = _controller.session;
    if (session == null) {
      return;
    }
    if (force) {
      _liveCompliance = null;
      _livePreflightError = null;
      _versionDeferred = false;
      _preflightSession = null;
    }
    if ((_livePreflight != null && identical(_preflightSession, session)) ||
        (_liveCompliance != null && identical(_preflightSession, session))) {
      return;
    }
    _preflightSession = session;
    final Future<void> request = _runLivePreflight(session);
    _livePreflight = request;
    unawaited(
      request.whenComplete(() {
        if (identical(_livePreflight, request)) {
          _livePreflight = null;
        }
        if (mounted) {
          setState(() {});
        }
      }),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _runLivePreflight(AuthSession session) async {
    try {
      final AccountComplianceSnapshot snapshot = await widget
          .dependencies
          .accountComplianceRepository
          .fetchSnapshot(
            account: session.mobile,
            expectedUserId: session.userId,
            currentVersion: widget.dependencies.environment.currentVersion,
            platformType: widget.dependencies.environment.platformType,
          );
      if (!mounted ||
          _controller.stage != AuthFlowStage.signedIn ||
          !identical(_controller.session, session)) {
        return;
      }
      setState(() {
        final VersionUpdateInfo? previousVersion = _liveCompliance?.versionInfo;
        if (previousVersion == null ||
            previousVersion.hasUpdate != snapshot.versionInfo.hasUpdate ||
            previousVersion.versionName != snapshot.versionInfo.versionName ||
            previousVersion.packageUrl != snapshot.versionInfo.packageUrl ||
            previousVersion.forceUpdate != snapshot.versionInfo.forceUpdate) {
          _versionDeferred = false;
        }
        _liveCompliance = snapshot;
        _livePreflightError = null;
      });
      _revealBlockingLiveGate(session);
    } catch (error) {
      if (!mounted ||
          _controller.stage != AuthFlowStage.signedIn ||
          !identical(_controller.session, session)) {
        return;
      }
      setState(() {
        _liveCompliance = null;
        _livePreflightError = error is ApiException
            ? error.message
            : '账号状态检查失败，请重试。';
      });
      _revealBlockingLiveGate(session);
    }
  }

  bool get _liveEntryBlocked {
    final snapshot = _liveCompliance;
    if (snapshot == null) return true;
    return snapshot.restriction.isRestricted ||
        !snapshot.accountUsable ||
        (snapshot.versionInfo.hasUpdate &&
            (snapshot.versionInfo.forceUpdate || !_versionDeferred));
  }

  void _revealBlockingLiveGate(AuthSession checkedSession) {
    if (!mounted ||
        _controller.stage != AuthFlowStage.signedIn ||
        !identical(_controller.session, checkedSession) ||
        !_liveEntryBlocked) {
      return;
    }
    // Keep this checked gate state via its stable key, but replace the route
    // owner in the same next build. Old pages/dialogs are disposed without a
    // pop-animation window in which a delayed request could push again.
    widget.onAccessBlocked?.call();
  }

  Widget _buildLiveEntryGate() {
    final AuthSession? session = _controller.session;
    if (session == null) {
      return SessionRestorePage(key: const Key('live-session-missing'));
    }
    final AccountComplianceSnapshot? snapshot = _liveCompliance;
    if (snapshot == null) {
      return AccountAccessGatePage(
        key: const Key('live-account-preflight'),
        account: session.mobile,
        errorMessage: _livePreflightError,
        loading: _livePreflight != null,
        onRetry: () => _startLivePreflightIfNeeded(force: true),
        onSignOut: _controller.signOut,
      );
    }
    if (snapshot.restriction.isRestricted || !snapshot.accountUsable) {
      return AccountAccessGatePage(
        key: const Key('live-account-restricted'),
        account: session.mobile,
        restriction: snapshot.restriction,
        accountUsable: snapshot.accountUsable,
        onRetry: () => _startLivePreflightIfNeeded(force: true),
        onSignOut: _controller.signOut,
      );
    }
    final VersionUpdateInfo versionInfo = snapshot.versionInfo;
    if (versionInfo.hasUpdate &&
        (versionInfo.forceUpdate || !_versionDeferred)) {
      return AppVersionGatePage(
        key: const Key('live-version-policy'),
        info: versionInfo,
        mandatory: versionInfo.forceUpdate,
        onRetry: () async {
          _startLivePreflightIfNeeded(force: true);
        },
        onLater: versionInfo.forceUpdate
            ? null
            : () => setState(() => _versionDeferred = true),
        onSignOut: _controller.signOut,
        openPackageUrl: widget.dependencies.externalUrlOpener.open,
      );
    }
    return MainShell(
      dependencies: widget.dependencies,
      onSignOut: _controller.signOut,
    );
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
        showLiveReadiness:
            kDebugMode &&
            widget.dependencies.environment.isLive &&
            widget
                .dependencies
                .environment
                .deploymentEnvironment
                .allowsDevelopmentTools,
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
      AuthFlowStage.signedIn =>
        widget.dependencies.environment.isLive
            ? _buildLiveEntryGate()
            : MainShell(
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
