import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

class AuthSessionManager {
  AuthSessionManager(this._store);

  static const String _sessionKey = 'auth.session.v2';
  static const String _legacySessionKey = 'auth.session.v1';
  static const String _consentKey = 'compliance.consent.v1';
  static const String _installIdKey = 'device.install-id.v1';

  final KeyValueStore _store;
  AuthSession? _session;

  AuthSession? get session => _session;

  String? get authorizationHeader => _session?.authorizationHeader;

  Future<AuthSession?> restore() async {
    String? encoded = await _store.read(_sessionKey);
    encoded ??= await _store.read(_legacySessionKey);
    if (encoded == null || encoded.isEmpty) {
      _session = null;
      return null;
    }
    final AuthSession? restored = AuthSession.decode(encoded);
    if (restored == null ||
        (restored.isAccessExpired && !restored.canRefresh)) {
      await clear();
      return null;
    }
    _session = restored;
    if (await _store.read(_sessionKey) == null) {
      await _store.write(_sessionKey, restored.encode());
      await _store.delete(_legacySessionKey);
    }
    return restored;
  }

  Future<void> save(AuthSession session) async {
    _session = session;
    await _store.write(_sessionKey, session.encode());
    await _store.delete(_legacySessionKey);
  }

  Future<void> clear() async {
    _session = null;
    await _store.delete(_sessionKey);
    await _store.delete(_legacySessionKey);
  }

  Future<bool> hasAcceptedConsent() async =>
      await _store.read(_consentKey) == 'accepted';

  Future<void> acceptConsent() => _store.write(_consentKey, 'accepted');

  Future<String?> readInstallId() => _store.read(_installIdKey);

  Future<void> saveInstallId(String installId) =>
      _store.write(_installIdKey, installId);
}
