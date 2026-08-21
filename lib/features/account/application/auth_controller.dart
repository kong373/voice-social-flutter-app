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

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required AuthSessionManager sessionManager,
    required DeviceIdentityProvider deviceIdentityProvider,
  }) : _repository = repository,
       _sessionManager = sessionManager,
       _deviceIdentityProvider = deviceIdentityProvider;

  final AuthRepository _repository;
  final AuthSessionManager _sessionManager;
  final DeviceIdentityProvider _deviceIdentityProvider;

  AuthFlowStage _stage = AuthFlowStage.initializing;
  bool _busy = false;
  bool _sendingCode = false;
  String? _errorMessage;
  String? _pendingPhone;
  String? _pendingSmsCode;
  SmsChallenge? _lastSmsChallenge;
  Future<bool>? _refreshInFlight;

  AuthFlowStage get stage => _stage;
  bool get busy => _busy;
  bool get sendingCode => _sendingCode;
  String? get errorMessage => _errorMessage;
  AuthSession? get session => _sessionManager.session;
  String get pendingPhone => _pendingPhone ?? '';
  SmsChallenge? get lastSmsChallenge => _lastSmsChallenge;
  String? get developmentSmsCode => _lastSmsChallenge?.developmentCode;

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
      await _sessionManager.clear();
      _errorMessage = '本地登录信息损坏，请重新登录';
      _stage = AuthFlowStage.signedOut;
    } catch (error) {
      // A secure-storage failure makes the local session state unverifiable.
      // It is safer to clear it than to continue with unknown credentials.
      await _sessionManager.clear();
      _errorMessage = _messageFor(error, fallback: '登录状态无法恢复，请重新登录');
      _stage = AuthFlowStage.signedOut;
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
      final ClientDevice device = await _deviceIdentityProvider.load();
      _lastSmsChallenge = await _repository.sendSmsCode(
        phone: phone.trim(),
        device: device,
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
    notifyListeners();
    try {
      final ClientDevice device = await _deviceIdentityProvider.load();
      final AuthOutcome outcome = await _repository.signInWithSms(
        phone: phone.trim(),
        smsCode: smsCode.trim(),
        device: device,
      );
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
      await _sessionManager.save(authenticatedSession);
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
      await _sessionManager.save(authenticatedSession);
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
    final AuthSession? current = _sessionManager.session;
    if (current == null || !current.canRefresh) {
      await _sessionManager.clear();
      _stage = AuthFlowStage.signedOut;
      _errorMessage = '刷新会话已失效，请重新登录';
      notifyListeners();
      return false;
    }

    _busy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final AuthSession refreshed = await _repository.refreshSession(current);
      await _sessionManager.save(refreshed);
      _stage = AuthFlowStage.signedIn;
      return true;
    } catch (error) {
      if (_isCredentialFailure(error)) {
        await _sessionManager.clear();
        _stage = AuthFlowStage.signedOut;
      } else {
        // Preserve a still-valid refresh token through transient network/server
        // failures. The user can retry instead of being forced to request a new
        // SMS code merely because the backend was temporarily unreachable.
        _stage = current.isAccessExpired
            ? AuthFlowStage.recoveryRequired
            : AuthFlowStage.signedIn;
      }
      _setError(error);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> retrySessionRecovery() => refreshSession();

  Future<void> discardSessionAndSignOut() async {
    await _sessionManager.clear();
    _stage = AuthFlowStage.signedOut;
    _errorMessage = null;
    notifyListeners();
  }

  void cancelRegistration() {
    _pendingPhone = null;
    _pendingSmsCode = null;
    _clearPendingChallenge();
    _stage = AuthFlowStage.signedOut;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_busy) {
      return;
    }
    _busy = true;
    _errorMessage = null;
    notifyListeners();
    final AuthSession? current = _sessionManager.session;
    try {
      if (current != null) {
        try {
          await _repository.logout(current);
        } catch (_) {
          // Local credential deletion is mandatory even when the server cannot
          // be reached. Server-side refresh tokens remain bounded and rotated.
        }
      }
      await _sessionManager.clear();
      _clearPendingChallenge();
      _stage = AuthFlowStage.signedOut;
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

  static bool _isCredentialFailure(Object error) =>
      error is ApiException &&
      (error.isAuthenticationFailure || error.kind == ApiFailureKind.forbidden);

  static String _messageFor(Object error, {required String fallback}) =>
      error is ApiException ? error.message : fallback;
}
