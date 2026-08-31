import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/im/domain/im_authoritative_refresh_bus.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/im/domain/im_session_adapter.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/im_session_events.dart';
import 'package:voice_social_app/features/im/domain/im_session_repository.dart';

/// Coordinates first-party authentication with the provider session.
///
/// A Tencent IM failure is deliberately surfaced through [status] and
/// [lastFailure], but [ensureAuthenticated] does not alter the first-party
/// AuthSession.  AuthController catches the error at the integration boundary
/// so HTTP auth remains usable while realtime stays fail-closed.
class ImSessionCoordinator extends ChangeNotifier {
  ImSessionCoordinator({
    required ImSessionAdapter adapter,
    required ImSessionCredentialRepository credentialsRepository,
    ImAuthoritativeRefreshBus? authoritativeRefreshBus,
    DateTime Function()? now,
  }) : _adapter = adapter,
       _credentialsRepository = credentialsRepository,
       _authoritativeRefreshBus = authoritativeRefreshBus,
       _now = now ?? DateTime.now {
    _adapterSubscription = _adapter.states.listen((ImSessionState _) {
      if (!_disposed) {
        notifyListeners();
      }
    });
    _adapterEventSubscription = _adapter.events.listen((ImSessionEvent event) {
      unawaited(handleProviderEvent(event).catchError((Object _) {}));
    });
  }

  final ImSessionAdapter _adapter;
  final ImSessionCredentialRepository _credentialsRepository;
  final ImAuthoritativeRefreshBus? _authoritativeRefreshBus;
  final DateTime Function() _now;
  late final StreamSubscription<ImSessionState> _adapterSubscription;
  late final StreamSubscription<ImSessionEvent> _adapterEventSubscription;

  Future<void>? _ensureFlight;
  String? _ensureFlightUserId;
  Timer? _renewalTimer;
  AuthSession? _activeAuthSession;
  ImSessionException? _lastFailure;
  int _generation = 0;
  bool _providerOffline = false;
  bool _disposed = false;

  ImSessionAdapter get adapter => _adapter;

  ImSessionStatus get status => _adapter.status;

  ImSessionState get state => _adapter.state;

  Stream<ImSessionState> get states => _adapter.states;

  ImSessionCredentials? get credentials => _adapter.credentials;

  ImSessionException? get lastFailure => _lastFailure;

  AuthSession? get activeAuthSession => _activeAuthSession;

  bool get realtimeReady =>
      !_disposed &&
      _lastFailure == null &&
      _activeAuthSession != null &&
      !_providerOffline &&
      _adapter.isReady &&
      !(_adapter.credentials?.isWithinRenewalWindow(_now()) ?? true) &&
      _adapter.activeUserId == _expectedUserId(_activeAuthSession);

  /// Fetches a fresh server credential and connects IM for a restored or newly
  /// authenticated first-party session.
  Future<void> ensureAuthenticated(AuthSession session) {
    _ensureNotDisposed();
    final String userId = ImSessionCredentials.userIdForPlatformUserId(
      session.userId,
    );
    if (_ensureFlight != null && _ensureFlightUserId == userId) {
      _activeAuthSession ??= session;
      return _ensureFlight!;
    }
    if (realtimeReady &&
        _activeAuthSession?.userId == session.userId &&
        !(_adapter.credentials?.isExpired(_now()) ?? true)) {
      return Future<void>.value();
    }

    final int generation = ++_generation;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    _activeAuthSession = session;
    _providerOffline = false;
    _lastFailure = null;
    notifyListeners();
    final Future<void> operation = _runEnsure(
      session: session,
      generation: generation,
    );
    _ensureFlight = operation;
    _ensureFlightUserId = userId;
    operation.then<void>(
      (_) {
        if (identical(_ensureFlight, operation)) {
          _ensureFlight = null;
          _ensureFlightUserId = null;
        }
        if (!_disposed) {
          notifyListeners();
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_ensureFlight, operation)) {
          _ensureFlight = null;
          _ensureFlightUserId = null;
        }
        if (!_disposed) {
          notifyListeners();
        }
      },
    );
    return operation;
  }

  /// Restore is an explicit alias used by app bootstrap code.
  Future<void> restore(AuthSession session) => ensureAuthenticated(session);

  /// Fetches and applies a new server-issued UserSig for the current account.
  Future<void> renew(AuthSession session) => ensureAuthenticated(session);

  Future<void> refresh(AuthSession session) => renew(session);

  /// Handles native provider callbacks without allowing callback payloads to
  /// choose an account or carry a credential.  Expiry and reconnect always
  /// fetch a fresh server credential through the same fenced single-flight
  /// path used by restore/login.
  Future<void> handleProviderEvent(ImSessionEvent event) async {
    _ensureNotDisposed();
    switch (event.kind) {
      case ImSessionEventKind.userSigExpired:
        final AuthSession? session = _activeAuthSession;
        if (session == null) {
          return;
        }
        await ensureAuthenticated(session);
        return;
      case ImSessionEventKind.networkOffline:
        _providerOffline = true;
        if (!_disposed) {
          notifyListeners();
        }
        return;
      case ImSessionEventKind.networkOnline:
        _providerOffline = false;
        final AuthSession? session = _activeAuthSession;
        if (session == null) {
          if (!_disposed) {
            notifyListeners();
          }
          return;
        }
        await ensureAuthenticated(session);
        return;
      case ImSessionEventKind.refreshHint:
        final ImRefreshHint? hint = event.refreshHint;
        final ImAuthoritativeRefreshBus? bus = _authoritativeRefreshBus;
        if (hint != null && bus != null) {
          final AuthSession? session = _activeAuthSession;
          if (session == null) {
            return;
          }
          final int generation = _generation;
          await bus.publish(
            hint,
            isCurrent: () => _isCurrent(session, generation),
          );
        }
        return;
    }
  }

  /// Invalidates all pending coordinator work and clears the provider session.
  /// Both logout and uninitialization are attempted so a native failure cannot
  /// leave an SDK instance or UserSig available to the next account.
  Future<void> logout() async {
    _ensureNotDisposed();
    ++_generation;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    _activeAuthSession = null;
    _providerOffline = false;
    _lastFailure = null;
    notifyListeners();
    Object? firstError;
    try {
      await _adapter.logout();
    } catch (error) {
      firstError = error;
    }
    try {
      await _adapter.uninitialize();
    } catch (error) {
      firstError ??= error;
    }
    if (firstError != null) {
      final ImSessionException failure = _asSessionException(
        firstError,
        ImSessionFailure.logout,
      );
      _lastFailure = failure;
      if (!_disposed) {
        notifyListeners();
      }
      throw failure;
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Compatibility name for callers that model native SDK teardown.
  Future<void> signOut() => logout();

  Future<void> close() async {
    if (_disposed) {
      return;
    }
    try {
      await logout();
    } finally {
      _disposed = true;
      await _adapterSubscription.cancel();
      await _adapterEventSubscription.cancel();
      super.dispose();
    }
  }

  @override
  void dispose() {
    // The app owns the adapter for the process lifetime; asynchronous native
    // teardown is available through [close].  Never start an unawaited logout
    // from ChangeNotifier.dispose.
    _disposed = true;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    unawaited(_adapterSubscription.cancel());
    unawaited(_adapterEventSubscription.cancel());
    super.dispose();
  }

  Future<void> _runEnsure({
    required AuthSession session,
    required int generation,
  }) async {
    try {
      if (_adapter.status == ImSessionStatus.blocked) {
        throw const ImSessionException(
          failure: ImSessionFailure.blocked,
          message: '腾讯 IM 适配器未启用',
        );
      }
      final String expectedUserId = _expectedUserIdOrThrow(session);
      if (_adapter.activeUserId != null &&
          _adapter.activeUserId != expectedUserId) {
        // Erase the previous principal before asking the backend for a new
        // credential.  If the request fails, the old account must not remain
        // usable in memory while first-party auth has already switched.
        await _adapter.logout();
        await _adapter.uninitialize();
        if (!_isCurrent(session, generation)) {
          return;
        }
      }
      final ImSessionCredentials credentials = await _credentialsRepository
          .fetch();
      if (!_isCurrent(session, generation)) {
        return;
      }
      if (!ImSessionCredentials.isCanonicalUserId(credentials.userId)) {
        throw const ImCredentialException(ImCredentialFailure.invalidValue);
      }
      if (credentials.userId != expectedUserId) {
        throw const ImCredentialException(ImCredentialFailure.userMismatch);
      }
      final ImSessionCredentials? active = _adapter.credentials;
      if (_adapter.isReady &&
          active != null &&
          active.userId == credentials.userId &&
          active.sdkAppId == credentials.sdkAppId &&
          active.userSig == credentials.userSig &&
          !active.isExpired(_now()) &&
          !active.isWithinRenewalWindow(_now())) {
        _scheduleRenewal(session, generation, active);
        return;
      }
      if (_adapter.isReady && active?.userId == credentials.userId) {
        await _adapter.renew(credentials);
      } else {
        await _adapter.initialize(credentials);
        if (!_isCurrent(session, generation)) {
          return;
        }
        await _adapter.login(credentials);
      }
      if (!_isCurrent(session, generation)) {
        // A logout/account switch raced the native call.  Do not expose a
        // stale ready state to a later realtime gateway.
        return;
      }
      _scheduleRenewal(session, generation, credentials);
    } catch (error) {
      if (_isCurrent(session, generation)) {
        final ImSessionException failure = _asSessionException(
          error,
          ImSessionFailure.provider,
        );
        _lastFailure = failure;
        notifyListeners();
        throw failure;
      }
      return;
    }
  }

  bool _isCurrent(AuthSession session, int generation) =>
      !_disposed &&
      generation == _generation &&
      _activeAuthSession?.userId == session.userId;

  /// Refreshes before the provider token reaches its final five-minute
  /// window.  If a response is already inside that window, the caller must
  /// explicitly retry rather than creating a zero-delay refresh loop.
  void _scheduleRenewal(
    AuthSession session,
    int generation,
    ImSessionCredentials credentials,
  ) {
    _renewalTimer?.cancel();
    _renewalTimer = null;
    if (_disposed || credentials.isWithinRenewalWindow(_now())) {
      return;
    }
    final Duration delay =
        credentials.expiresAt.difference(_now().toUtc()) -
        ImSessionCredentials.renewalThreshold;
    if (delay <= Duration.zero) {
      return;
    }
    _renewalTimer = Timer(delay, () {
      _renewalTimer = null;
      if (!_isCurrent(session, generation)) {
        return;
      }
      final Future<void> refresh = ensureAuthenticated(session);
      unawaited(refresh.catchError((Object _) {}));
    });
  }

  static String? _expectedUserId(AuthSession? session) {
    if (session == null) {
      return null;
    }
    try {
      return ImSessionCredentials.userIdForPlatformUserId(session.userId);
    } on ArgumentError {
      return null;
    }
  }

  static String _expectedUserIdOrThrow(AuthSession session) {
    final String? expected = _expectedUserId(session);
    if (expected == null) {
      throw const ImSessionException(
        failure: ImSessionFailure.invalidCredentials,
        message: '第一方登录会话用户无效',
      );
    }
    return expected;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const ImSessionException(
        failure: ImSessionFailure.disposed,
        message: 'IM 会话协调器已释放',
      );
    }
  }

  static ImSessionException _asSessionException(
    Object error,
    ImSessionFailure fallback,
  ) {
    if (error is ImSessionException) {
      return error;
    }
    if (error is ImCredentialException) {
      final ImSessionFailure failure =
          error.failure == ImCredentialFailure.userMismatch
          ? ImSessionFailure.identityMismatch
          : ImSessionFailure.invalidCredentials;
      return ImSessionException(failure: failure, message: error.message);
    }
    return ImSessionException(failure: fallback, message: '腾讯 IM 会话不可用');
  }
}

// Retain a reference to the adapter state in this file so future workers can
// observe an event even when an adapter uses a custom state stream.  Reading it
// is intentionally side-effect free.
ImSessionState imSessionStateOf(ImSessionCoordinator coordinator) =>
    coordinator.state;
