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
  signedIn,
}

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required AuthSessionManager sessionManager,
    required DeviceIdentityProvider deviceIdentityProvider,
  })  : _repository = repository,
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

  AuthFlowStage get stage => _stage;
  bool get busy => _busy;
  bool get sendingCode => _sendingCode;
  String? get errorMessage => _errorMessage;
  AuthSession? get session => _sessionManager.session;
  String get pendingPhone => _pendingPhone ?? '';

  Future<void> initialize() async {
    _stage = AuthFlowStage.initializing;
    notifyListeners();
    try {
      final bool accepted = await _sessionManager.hasAcceptedConsent();
      if (!accepted) {
        _stage = AuthFlowStage.consentRequired;
        notifyListeners();
        return;
      }
      final AuthSession? restored = await _sessionManager.restore();
      _stage = restored == null
          ? AuthFlowStage.signedOut
          : AuthFlowStage.signedIn;
    } catch (error) {
      _errorMessage = '无法恢复登录状态，请重新登录';
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
    notifyListeners();
    try {
      await _repository.sendSmsCode(phone.trim());
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
      final AuthSession? session = outcome.session;
      if (session == null) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '登录成功但未返回会话',
        );
      }
      await _sessionManager.save(session);
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
      final AuthSession session = await _repository.registerWithSms(
        phone: phone,
        smsCode: smsCode,
        device: device,
        profile: profile,
      );
      await _sessionManager.save(session);
      _pendingPhone = null;
      _pendingSmsCode = null;
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

  void cancelRegistration() {
    _pendingPhone = null;
    _pendingSmsCode = null;
    _stage = AuthFlowStage.signedOut;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_busy) {
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      await _sessionManager.clear();
      _stage = AuthFlowStage.signedOut;
      _errorMessage = null;
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

  void _setError(Object error) {
    _errorMessage = error is ApiException
        ? error.message
        : '操作失败，请稍后重试';
  }
}
