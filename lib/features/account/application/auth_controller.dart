import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/data/device_identity_provider.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/auth_repository.dart';

enum AuthFlowStage {
  initializing,
  consentRequired,
  signedOut,
  registrationRequired,
  recoveryRequired,
  signedIn,
}

enum ServerLogoutOutcome { notAttempted, succeeded, failed }

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required AuthSessionManager sessionManager,
    required DeviceIdentityProvider deviceIdentityProvider,
    bool allowsDevelopmentTools = false,
  }) : _repository = repository,
       _sessionManager = sessionManager,
       _deviceIdentityProvider = deviceIdentityProvider,
       _allowsDevelopmentTools = allowsDevelopmentTools;

  final AuthRepository _repository;
  final AuthSessionManager _sessionManager;
  final DeviceIdentityProvider _deviceIdentityProvider;
  final bool _allowsDevelopmentTools;

  AuthFlowStage _stage = AuthFlowStage.initializing;
  bool _busy = false;
  bool _sendingCode = false;
  String? _errorMessage;
  String? _pendingPhone;
  String? _pendingSmsCode;
  SmsChallenge? _lastSmsChallenge;
  Future<bool>? _refreshInFlight;
  Future<void>? _signOutInFlight;
  int _sessionGeneration = 0;
  bool _signOutRecovery = false;
  ServerLogoutOutcome _lastServerLogoutOutcome =
      ServerLogoutOutcome.notAttempted;

  AuthFlowStage get stage => _stage;
  bool get busy => _busy;
  bool get sendingCode => _sendingCode;
  String? get errorMessage => _errorMessage;
  AuthSession? get session => _sessionManager.session;
  String get pendingPhone => _pendingPhone ?? '';
  SmsChallenge? get lastSmsChallenge => _lastSmsChallenge;
  ServerLogoutOutcome get lastServerLogoutOutcome => _lastServerLogoutOutcome;

  /// Development OTPs are intentionally exposed only to local/development
  /// builds.  The controller is the final presentation-layer guard even when
  /// a test repository or a malformed live response supplies a code.
  String? get developmentSmsCode =>
      _allowsDevelopmentTools ? _lastSmsChallenge?.developmentCode : null;

  Future<void> initialize() async {
    _stage = AuthFlowStage.initializing;
    _errorMessage = null;
    notifyListeners();
    try {
      final bool accepted = await _sessionManager.hasAcceptedConsent();
      if (!accepted) {
        _stage = AuthFlowStage.consentRequired;
        notifyListeners();
        return;
      }
      final AuthSession? restored = await _sessionManager.restore();
      if (restored == null) {
        _stage = AuthFlowStage.signedOut;
      } else if (restored.shouldRefreshAccess) {
        await refreshSession();
      } else {
        _stage = AuthFlowStage.signedIn;
      }
    } on FormatException {
      _sessionGeneration += 1;
      try {
        await _sessionManager.clear();
        _errorMessage = '本地登录信息损坏，请重新登录';
        _stage = AuthFlowStage.signedOut;
        _signOutRecovery = false;
      } catch (clearError) {
        _errorMessage = _messageFor(
          clearError,
          fallback: '本地会话清理失败，请重试或退出应用后重新登录',
        );
        _stage = AuthFlowStage.recoveryRequired;
        _signOutRecovery = true;
      }
    } catch (error) {
      // A secure-storage failure makes the local session state unverifiable.
      // It is safer to clear it than to continue with unknown credentials.
      _sessionGeneration += 1;
      try {
        await _sessionManager.clear();
        _errorMessage = _messageFor(error, fallback: '登录状态无法恢复，请重新登录');
        _stage = AuthFlowStage.signedOut;
        _signOutRecovery = false;
      } catch (clearError) {
        _errorMessage = _messageFor(
          clearError,
          fallback: '本地会话清理失败，请重试或退出应用后重新登录',
        );
        _stage = AuthFlowStage.recoveryRequired;
        _signOutRecovery = true;
      }
    }
    notifyListeners();
  }

  Future<void> acceptConsent() async {
    await _sessionManager.acceptConsent();
    _stage = AuthFlowStage.signedOut;
    notifyListeners();
  }

  Future<bool> sendSmsCode(String phone) async {
    if (_sendingCode) {
      return false;
    }
    _sendingCode = true;
    _errorMessage = null;
    _lastSmsChallenge = null;
    notifyListeners();
    try {
      final int operationGeneration = _sessionGeneration;
      final ClientDevice device = await _deviceIdentityProvider.load();
      final SmsChallenge challenge = await _repository.sendSmsCode(
        phone: phone.trim(),
        device: device,
      );
      if (operationGeneration != _sessionGeneration) {
        return false;
      }
      _lastSmsChallenge = SmsChallenge(
        challengeId: challenge.challengeId,
        expiresAt: challenge.expiresAt,
        retryAfter: challenge.retryAfter,
        developmentCode: _allowsDevelopmentTools
            ? challenge.developmentCode
            : null,
      );
      return true;
    } catch (error) {
      _setError(error);
      return false;
    } finally {
      _sendingCode = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithSms({
    required String phone,
    required String smsCode,
  }) async {
    if (_busy) {
      return false;
    }
    _busy = true;
    _errorMessage = null;
    final int operationGeneration = _sessionGeneration;
    notifyListeners();
    try {
      final ClientDevice device = await _deviceIdentityProvider.load();
      final AuthOutcome outcome = await _repository.signInWithSms(
        phone: phone.trim(),
        smsCode: smsCode.trim(),
        device: device,
      );
      if (operationGeneration != _sessionGeneration) {
        return false;
      }
      if (outcome.type == AuthOutcomeType.registrationRequired) {
        _pendingPhone = phone.trim();
        _pendingSmsCode = smsCode.trim();
        _stage = AuthFlowStage.registrationRequired;
        return true;
      }
      final AuthSession? authenticatedSession = outcome.session;
      if (authenticatedSession == null) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '登录成功但未返回会话',
        );
      }
      if (!await _saveSessionIfCurrent(
        authenticatedSession,
        operationGeneration,
      )) {
        return false;
      }
      _clearPendingChallenge();
      _stage = AuthFlowStage.signedIn;
      return true;
    } catch (error) {
      _setError(error);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> completeRegistration(RegistrationProfile profile) async {
    final String phone = _pendingPhone ?? '';
    final String smsCode = _pendingSmsCode ?? '';
    if (_busy || phone.isEmpty || smsCode.isEmpty) {
      return false;
    }
    _busy = true;
    _errorMessage = null;
    final int operationGeneration = _sessionGeneration;
    notifyListeners();
    try {
      final ClientDevice device = await _deviceIdentityProvider.load();
      final AuthSession authenticatedSession = await _repository
          .registerWithSms(
            phone: phone,
            smsCode: smsCode,
            device: device,
            profile: profile,
          );
      if (!await _saveSessionIfCurrent(
        authenticatedSession,
        operationGeneration,
      )) {
        return false;
      }
      _pendingPhone = null;
      _pendingSmsCode = null;
      _clearPendingChallenge();
      _stage = AuthFlowStage.signedIn;
      return true;
    } catch (error) {
      _setError(error);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Rotates the refresh token once for every concurrent wave of 401s.
  Future<bool> refreshSession() {
    final Future<bool>? active = _refreshInFlight;
    if (active != null) {
      return active;
    }
    final Future<bool> future = _performRefresh();
    _refreshInFlight = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_refreshInFlight, future)) {
          _refreshInFlight = null;
        }
      }),
    );
    return future;
  }

  Future<bool> _performRefresh() async {
    final int operationGeneration = _sessionGeneration;
    final AuthSession? current = _sessionManager.session;
    if (current == null || !current.canRefresh) {
      _sessionGeneration += 1;
      try {
        await _sessionManager.clear();
        _stage = AuthFlowStage.signedOut;
        _errorMessage = '刷新会话已失效，请重新登录';
        _signOutRecovery = false;
      } catch (clearError) {
        _stage = AuthFlowStage.recoveryRequired;
        _errorMessage = _messageFor(
          clearError,
          fallback: '本地会话清理失败，请重试或退出应用后重新登录',
        );
        _signOutRecovery = true;
      }
      notifyListeners();
      return false;
    }

    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final AuthSession refreshed = await _repository.refreshSession(current);
      if (!_isCurrentSession(current, operationGeneration) ||
          !await _saveSessionIfCurrent(
            refreshed,
            operationGeneration,
            expectedCurrent: current,
          )) {
        return false;
      }
      _stage = AuthFlowStage.signedIn;
      return true;
    } catch (error) {
      if (!_isCurrentSession(current, operationGeneration)) {
        return false;
      }
      final bool refreshOutcomeAmbiguous = _isRefreshOutcomeAmbiguous(error);
      if (_isCredentialFailure(error) || refreshOutcomeAmbiguous) {
        // The backend rotates refresh tokens exactly once and deliberately
        // revokes the whole family when an already-used token is replayed. A
        // timeout, lost response, malformed success response, or server error
        // may therefore mean the old local token has already been consumed.
        // Never offer a retry with that uncertain credential: erase it and
        // require a fresh login instead of risking family-wide revocation.
        _sessionGeneration += 1;
        bool clearFailed = false;
        try {
          await _sessionManager.clear();
          _stage = AuthFlowStage.signedOut;
          _signOutRecovery = false;
        } catch (clearError) {
          _stage = AuthFlowStage.recoveryRequired;
          _signOutRecovery = true;
          clearFailed = true;
          _errorMessage = _messageFor(
            clearError,
            fallback: '本地会话清理失败，请重试或退出应用后重新登录',
          );
        }
        if (clearFailed) {
          return false;
        }
      } else {
        // Configuration/validation and other definitive pre-commit failures
        // leave the one-time refresh credential safe to use after the local
        // issue has been corrected.
        _stage = current.isAccessExpired
            ? AuthFlowStage.recoveryRequired
            : AuthFlowStage.signedIn;
      }
      _errorMessage = refreshOutcomeAmbiguous
          ? '刷新结果无法确认，为保护账号已清除本地会话，请重新登录'
          : _messageFor(error, fallback: '操作失败，请稍后重试');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> retrySessionRecovery() async {
    if (_signOutRecovery) {
      await signOut();
      return _stage == AuthFlowStage.signedOut;
    }
    return refreshSession();
  }

  Future<void> discardSessionAndSignOut() async {
    _sessionGeneration += 1;
    try {
      await _sessionManager.clear();
      _stage = AuthFlowStage.signedOut;
      _errorMessage = null;
      _signOutRecovery = false;
    } catch (error) {
      _stage = AuthFlowStage.recoveryRequired;
      _errorMessage = _messageFor(error, fallback: '退出登录未完成，本地会话仍可能存在，请重试');
      _signOutRecovery = true;
    }
    notifyListeners();
  }

  void cancelRegistration() {
    _sessionGeneration += 1;
    _pendingPhone = null;
    _pendingSmsCode = null;
    _clearPendingChallenge();
    _stage = AuthFlowStage.signedOut;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> signOut() {
    final Future<void>? active = _signOutInFlight;
    if (active != null) {
      return active;
    }
    final Future<void> future = _performSignOut();
    _signOutInFlight = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_signOutInFlight, future)) {
            _signOutInFlight = null;
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_signOutInFlight, future)) {
            _signOutInFlight = null;
          }
        },
      ),
    );
    return future;
  }

  Future<void> _performSignOut() async {
    _sessionGeneration += 1;
    _busy = true;
    _errorMessage = null;
    _lastServerLogoutOutcome = ServerLogoutOutcome.notAttempted;
    notifyListeners();
    final AuthSession? current = _sessionManager.session;
    try {
      if (current != null) {
        try {
          await _repository.logout(current);
          _lastServerLogoutOutcome = ServerLogoutOutcome.succeeded;
        } catch (_) {
          // Local credential deletion is mandatory even when the server cannot
          // be reached. Keep the backend outcome visible after local cleanup;
          // otherwise the UI and acceptance evidence would report a logout
          // success that the server never confirmed.
          _lastServerLogoutOutcome = ServerLogoutOutcome.failed;
        }
      }
      try {
        await _sessionManager.clear();
        _clearPendingChallenge();
        _stage = AuthFlowStage.signedOut;
        _errorMessage = _lastServerLogoutOutcome == ServerLogoutOutcome.failed
            ? '本机登录信息已清除，但服务端会话注销未确认；请重新登录后在设备管理中检查会话'
            : null;
        _signOutRecovery = false;
      } catch (error) {
        _stage = AuthFlowStage.recoveryRequired;
        _errorMessage = _messageFor(error, fallback: '退出登录未完成，本地会话仍可能存在，请重试');
        _signOutRecovery = true;
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  void _clearPendingChallenge() {
    _lastSmsChallenge = null;
  }

  void _setError(Object error) {
    _errorMessage = _messageFor(error, fallback: '操作失败，请稍后重试');
  }

  bool _isCurrentSession(AuthSession session, int generation) =>
      generation == _sessionGeneration &&
      identical(_sessionManager.session, session);

  Future<bool> _saveSessionIfCurrent(
    AuthSession session,
    int generation, {
    AuthSession? expectedCurrent,
  }) async {
    if (generation != _sessionGeneration ||
        (expectedCurrent != null &&
            !identical(_sessionManager.session, expectedCurrent))) {
      return false;
    }
    await _sessionManager.save(session);
    if (generation != _sessionGeneration) {
      if (identical(_sessionManager.session, session)) {
        await _sessionManager.clear();
      }
      return false;
    }
    _sessionGeneration += 1;
    return true;
  }

  static bool _isCredentialFailure(Object error) =>
      error is ApiException &&
      (error.isAuthenticationFailure ||
          error.kind == ApiFailureKind.forbidden ||
          error.kind == ApiFailureKind.conflict);

  static bool _isRefreshOutcomeAmbiguous(Object error) {
    if (error is! ApiException) {
      return true;
    }
    return switch (error.kind) {
      ApiFailureKind.network ||
      ApiFailureKind.timeout ||
      ApiFailureKind.protocol ||
      ApiFailureKind.server => true,
      ApiFailureKind.configuration ||
      ApiFailureKind.unauthorized ||
      ApiFailureKind.forbidden ||
      ApiFailureKind.validation ||
      ApiFailureKind.conflict ||
      ApiFailureKind.business => false,
    };
  }

  static String _messageFor(Object error, {required String fallback}) =>
      error is ApiException ? error.message : fallback;
}
