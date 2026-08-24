import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/account/domain/auth_refresh_recovery.dart';

class AuthSessionManager {
  AuthSessionManager(this._store);

  static const String _sessionKey = 'auth.session.v2';
  static const String _legacySessionKey = 'auth.session.v1';
  static const String _consentKey = 'compliance.consent.v1';
  static const String _installIdKey = 'device.install-id.v1';
  static const String pendingRefreshStorageKey = 'auth.refresh.pending.v1';
  static const Duration refreshRecoveryWindow = Duration(seconds: 30);

  final KeyValueStore _store;
  AuthSession? _session;

  AuthSession? get session => _session;

  String? get authorizationHeader => _session?.authorizationHeader;

  Future<AuthSession?> restore() async {
    String? encoded = await _store.read(_sessionKey);
    encoded ??= await _store.read(_legacySessionKey);
    if (encoded == null || encoded.isEmpty) {
      _session = null;
      await _clearPendingRefreshIfPresent();
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
    // The new session is durable before the pending request is cleared. If a
    // process dies between these two writes, the old pending record cannot be
    // reused against the new refresh-token fingerprint on the next launch.
    await clearPendingRefresh();
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
    Object? firstError;
    StackTrace? firstStack;
    Future<void> erase(String key) async {
      try {
        await _eraseCredentialKey(key);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }

    await erase(_sessionKey);
    await erase(_legacySessionKey);
    await erase(pendingRefreshStorageKey);
    _session = null;
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack ?? StackTrace.current);
    }
  }

  /// Returns the pending refresh request for diagnostics/tests without
  /// exposing its source record or any credential material.
  Future<PendingAuthRefresh?> readPendingRefresh() async {
    final String? encoded = await _store.read(pendingRefreshStorageKey);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    return PendingAuthRefresh.decode(encoded);
  }

  /// Persists a request id before any network request is made. A valid record
  /// is reused after a process restart; an invalid record is erased and the
  /// caller is stopped before it can accidentally send a new id.
  Future<PendingAuthRefresh> prepareRefreshRequest({
    required AuthSession session,
    required String clientId,
    required String Function() requestIdFactory,
    DateTime? now,
  }) async {
    final DateTime current = (now ?? DateTime.now()).toUtc();
    final String fingerprint = authRefreshSessionFingerprint(
      session: session,
      clientId: clientId,
    );
    final AuthSession? currentSession = _session;
    if (currentSession != null &&
        authRefreshSessionFingerprint(
              session: currentSession,
              clientId: clientId,
            ) !=
            fingerprint) {
      await _clearPendingRefreshIfPresent();
      throw const AuthRefreshRecoveryException(
        AuthRefreshRecoveryFailure.sessionChanged,
      );
    }
    final String? encoded = await _store.read(pendingRefreshStorageKey);
    if (encoded != null && encoded.isNotEmpty) {
      final PendingAuthRefresh? pending = PendingAuthRefresh.decode(encoded);
      if (pending == null) {
        await clearPendingRefresh();
        throw const AuthRefreshRecoveryException(
          AuthRefreshRecoveryFailure.malformed,
        );
      }
      final Duration pendingLifetime = pending.expiresAt.difference(
        pending.createdAt,
      );
      if (pendingLifetime > refreshRecoveryWindow ||
          pending.createdAt.isAfter(current.add(const Duration(minutes: 5)))) {
        await clearPendingRefresh();
        throw const AuthRefreshRecoveryException(
          AuthRefreshRecoveryFailure.malformed,
        );
      }
      if (!pending.expiresAt.isAfter(current)) {
        await clearPendingRefresh();
        throw const AuthRefreshRecoveryException(
          AuthRefreshRecoveryFailure.expired,
        );
      }
      if (pending.sessionFingerprint != fingerprint) {
        await clearPendingRefresh();
        throw const AuthRefreshRecoveryException(
          AuthRefreshRecoveryFailure.sessionChanged,
        );
      }
      return pending;
    }

    final String requestId = requestIdFactory().trim();
    if (!PendingAuthRefresh.isValidRequestId(requestId)) {
      throw StateError('刷新请求幂等 ID 格式无效');
    }
    final PendingAuthRefresh pending = PendingAuthRefresh(
      requestId: requestId,
      sessionFingerprint: fingerprint,
      createdAt: current,
      expiresAt: current.add(refreshRecoveryWindow),
    );
    // Pending metadata is intentionally a separate secure-storage value and
    // contains only an opaque request id, a one-way fingerprint and bounds.
    await _store.write(pendingRefreshStorageKey, pending.encode());
    return pending;
  }

  /// Clears the pending record using an empty tombstone before deletion. The
  /// tombstone keeps a failed platform delete from resurrecting an old id.
  Future<void> clearPendingRefresh() =>
      _eraseCredentialKey(pendingRefreshStorageKey);

  Future<void> _clearPendingRefreshIfPresent() async {
    final String? encoded = await _store.read(pendingRefreshStorageKey);
    if (encoded != null && encoded.isNotEmpty) {
      await clearPendingRefresh();
    }
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
