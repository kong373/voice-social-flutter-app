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
      try {
        await _store.delete(_legacySessionKey);
      } catch (_) {
        // The v2 value is authoritative. A later cleanup can remove the legacy
        // duplicate without risking loss of the successfully migrated session.
      }
    }
    return restored;
  }

  Future<void> save(AuthSession session) async {
    // Do not expose the new in-memory credentials until secure persistence has
    // succeeded. This prevents a process from using a rotated refresh token
    // that would be lost on the next cold start.
    await _store.write(_sessionKey, session.encode());
    _session = session;
    try {
      await _store.delete(_legacySessionKey);
    } catch (_) {
      // The current key is present and restore always prefers it.
    }
  }

  Future<void> clear() async {
    // An empty overwrite is itself a safe tombstone if a platform delete call
    // fails. Only report success when each credential key was either overwritten
    // or deleted, so an old refresh token cannot silently reappear on relaunch.
    await _eraseCredentialKey(_sessionKey);
    await _eraseCredentialKey(_legacySessionKey);
    _session = null;
  }

  Future<void> _eraseCredentialKey(String key) async {
    Object? writeError;
    Object? deleteError;
    bool erased = false;
    try {
      await _store.write(key, '');
      erased = true;
    } catch (error) {
      writeError = error;
    }
    try {
      await _store.delete(key);
      erased = true;
    } catch (error) {
      deleteError = error;
    }
    if (!erased) {
      throw StateError(
        'Unable to erase secure credential key $key: '
        'write=$writeError delete=$deleteError',
      );
    }
  }

  Future<bool> hasAcceptedConsent() async =>
      await _store.read(_consentKey) == 'accepted';

  Future<void> acceptConsent() => _store.write(_consentKey, 'accepted');

  Future<String?> readInstallId() => _store.read(_installIdKey);

  Future<void> saveInstallId(String installId) =>
      _store.write(_installIdKey, installId);
}
