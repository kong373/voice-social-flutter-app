import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';

class AuthSessionManager {
  AuthSessionManager(this._store);

  static const String _sessionKey = 'auth.session.v1';
  static const String _consentKey = 'compliance.consent.v1';
  static const String _installIdKey = 'device.install-id.v1';

  final KeyValueStore _store;
  AuthSession? _session;

  AuthSession? get session => _session;

  String? get authorizationHeader => _session?.authorizationHeader;

  Future<AuthSession?> restore() async {
    final String? encoded = await _store.read(_sessionKey);
    if (encoded == null || encoded.isEmpty) {
      _session = null;
      return null;
    }
    final AuthSession? restored = AuthSession.decode(encoded);
    if (restored == null || restored.isExpired) {
      await clear();
      return null;
    }
    _session = restored;
    return restored;
  }

  Future<void> save(AuthSession session) async {
    _session = session;
    await _store.write(_sessionKey, session.encode());
  }

  Future<void> clear() async {
    _session = null;
    await _store.delete(_sessionKey);
  }

  Future<bool> hasAcceptedConsent() async =>
      await _store.read(_consentKey) == 'accepted';

  Future<void> acceptConsent() => _store.write(_consentKey, 'accepted');

  Future<String?> readInstallId() => _store.read(_installIdKey);

  Future<void> saveInstallId(String installId) =>
      _store.write(_installIdKey, installId);
}
