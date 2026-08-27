import 'dart:async';

import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/im_session_events.dart';

/// Provider-neutral lifecycle exposed to the future realtime gateway.
enum ImSessionStatus {
  /// No provider is enabled for this build.  Realtime operations must fail
  /// closed while this state is active.
  blocked,
  idle,
  initializing,
  loggingIn,
  ready,
  renewing,
  loggingOut,
  expired,
  offline,
  reconnecting,
  error,
}

enum ImSessionFailure {
  blocked,
  invalidCredentials,
  identityMismatch,
  initialize,
  login,
  renew,
  logout,
  uninitialize,
  provider,
  disposed,
}

/// Safe provider-neutral failure.  Provider descriptions are intentionally not
/// retained because an SDK may echo request material in its error string.
class ImSessionException implements Exception {
  const ImSessionException({
    required this.failure,
    required this.message,
    this.providerCode,
  });

  final ImSessionFailure failure;
  final String message;
  final int? providerCode;

  @override
  String toString() =>
      'ImSessionException(${failure.name}, providerCode=$providerCode): '
      '$message';
}

/// A state snapshot suitable for exposing to a realtime transport.
class ImSessionState {
  const ImSessionState({
    required this.status,
    this.activeUserId,
    this.expiresAt,
    this.failure,
  });

  const ImSessionState.blocked() : this(status: ImSessionStatus.blocked);

  const ImSessionState.idle() : this(status: ImSessionStatus.idle);

  final ImSessionStatus status;
  final String? activeUserId;
  final DateTime? expiresAt;
  final ImSessionFailure? failure;

  bool get isReady => status == ImSessionStatus.ready;

  /// Realtime code should use this gate instead of inferring readiness from
  /// whether an SDK object was constructed.
  bool get realtimeAllowed => isReady && activeUserId != null;
}

typedef ImLifecycleLogger = void Function(ImLifecycleMarker marker);

/// Fixed, redacted lifecycle markers.  Callers must not add identity, app id,
/// token, or SDK error text to a log line.
enum ImLifecycleMarker {
  initializeStarted,
  initializeSucceeded,
  initializeFailed,
  loginStarted,
  loginSucceeded,
  loginFailed,
  renewStarted,
  renewSucceeded,
  renewFailed,
  logoutStarted,
  logoutSucceeded,
  logoutFailed,
  uninitializeStarted,
  uninitializeSucceeded,
  uninitializeFailed,
  blocked,
  expired,
}

/// Provider-neutral IM lifecycle boundary.
///
/// Implementations must keep UserSig and other credential material in memory
/// only.  No method accepts a client uid independent of the server-issued
/// credential, which prevents callers from constructing a mismatched login.
abstract interface class ImSessionAdapter {
  ImSessionStatus get status;

  ImSessionState get state;

  Stream<ImSessionState> get states;

  /// Provider callbacks are reduced to lifecycle/network events and
  /// allow-listed first-party refresh metadata.  Raw SDK messages never cross
  /// this interface.
  Stream<ImSessionEvent> get events;

  ImSessionCredentials? get credentials;

  String? get activeUserId;

  bool get isReady;

  Future<void> initialize(ImSessionCredentials credentials);

  Future<void> login(ImSessionCredentials credentials);

  Future<void> renew(ImSessionCredentials credentials);

  Future<void> logout();

  Future<void> uninitialize();
}

/// Naming aliases matching the official SDK terminology and keeping the
/// provider-neutral port usable by future workers.
extension ImSessionAdapterSdkNames on ImSessionAdapter {
  Future<void> initSDK(ImSessionCredentials credentials) =>
      initialize(credentials);

  Future<void> refresh(ImSessionCredentials credentials) => renew(credentials);

  Future<void> unInitSDK() => uninitialize();
}

/// Explicit fail-closed adapter used for live builds until the feature is
/// opted in.  It performs no SDK calls and never reports realtime readiness.
class BlockedImSessionAdapter implements ImSessionAdapter {
  const BlockedImSessionAdapter();

  @override
  ImSessionStatus get status => ImSessionStatus.blocked;

  @override
  ImSessionState get state => const ImSessionState.blocked();

  @override
  Stream<ImSessionState> get states => const Stream<ImSessionState>.empty();

  @override
  Stream<ImSessionEvent> get events => const Stream<ImSessionEvent>.empty();

  @override
  ImSessionCredentials? get credentials => null;

  @override
  String? get activeUserId => null;

  @override
  bool get isReady => false;

  @override
  Future<void> initialize(ImSessionCredentials credentials) =>
      Future<void>.error(_blockedError());

  @override
  Future<void> login(ImSessionCredentials credentials) =>
      Future<void>.error(_blockedError());

  @override
  Future<void> renew(ImSessionCredentials credentials) =>
      Future<void>.error(_blockedError());

  @override
  Future<void> logout() async {}

  @override
  Future<void> uninitialize() async {}

  static ImSessionException _blockedError() => const ImSessionException(
    failure: ImSessionFailure.blocked,
    message: '腾讯 IM 适配器未启用',
  );
}

/// In-memory deterministic adapter for mock mode and unit tests.
///
/// This class does not load a native SDK and never performs network calls.  It
/// intentionally models the same identity/expiry rules as a production
/// adapter, allowing lifecycle races to be tested without vendor access.
class FakeImSessionAdapter implements ImSessionAdapter {
  FakeImSessionAdapter({
    DateTime Function()? now,
    this.failInitialize = false,
    this.failLogin = false,
    this.failRenew = false,
    this.failLogout = false,
    this.failUninitialize = false,
    ImLifecycleLogger? logger,
  }) : _now = now ?? DateTime.now,
       _logger = logger;

  final DateTime Function() _now;
  final ImLifecycleLogger? _logger;
  final bool failInitialize;
  final bool failLogin;
  final bool failRenew;
  final bool failLogout;
  final bool failUninitialize;
  final StreamController<ImSessionState> _stateController =
      StreamController<ImSessionState>.broadcast(sync: true);
  final StreamController<ImSessionEvent> _eventController =
      StreamController<ImSessionEvent>.broadcast(sync: true);

  ImSessionState _state = const ImSessionState.idle();
  ImSessionCredentials? _credentials;
  int initializeCalls = 0;
  int loginCalls = 0;
  int renewCalls = 0;
  int logoutCalls = 0;
  int uninitializeCalls = 0;

  @override
  ImSessionStatus get status => _state.status;

  @override
  ImSessionState get state => _state;

  @override
  Stream<ImSessionState> get states => _stateController.stream;

  @override
  Stream<ImSessionEvent> get events => _eventController.stream;

  @override
  ImSessionCredentials? get credentials => _credentials;

  @override
  String? get activeUserId => _credentials?.userId;

  @override
  bool get isReady =>
      _state.isReady && !(_credentials?.isExpired(_now()) ?? true);

  @override
  Future<void> initialize(ImSessionCredentials credentials) async {
    initializeCalls += 1;
    _validate(credentials, ImSessionFailure.initialize);
    if (_state.status == ImSessionStatus.ready &&
        _credentials?.sdkAppId == credentials.sdkAppId) {
      return;
    }
    _setState(
      ImSessionState(
        status: ImSessionStatus.initializing,
        activeUserId: _credentials?.userId,
      ),
    );
    _logger?.call(ImLifecycleMarker.initializeStarted);
    if (failInitialize) {
      _fail(ImSessionFailure.initialize, '腾讯 IM 初始化失败');
    }
    _setState(const ImSessionState.idle());
    _logger?.call(ImLifecycleMarker.initializeSucceeded);
  }

  @override
  Future<void> login(ImSessionCredentials credentials) async {
    loginCalls += 1;
    _validate(credentials, ImSessionFailure.login);
    if (isReady &&
        _credentials?.sdkAppId == credentials.sdkAppId &&
        _credentials?.userId == credentials.userId &&
        _credentials?.userSig == credentials.userSig &&
        _credentials?.expiresAt == credentials.expiresAt &&
        _credentials?.ttlSeconds == credentials.ttlSeconds &&
        _credentials?.systemAccount == credentials.systemAccount) {
      return;
    }
    if (failLogin) {
      _fail(ImSessionFailure.login, '腾讯 IM 登录失败');
    }
    _setState(
      ImSessionState(
        status: ImSessionStatus.ready,
        activeUserId: credentials.userId,
        expiresAt: credentials.expiresAt,
      ),
    );
    _credentials = credentials;
    _logger?.call(ImLifecycleMarker.loginSucceeded);
  }

  @override
  Future<void> renew(ImSessionCredentials credentials) async {
    renewCalls += 1;
    _validate(credentials, ImSessionFailure.renew);
    if (isReady &&
        _credentials?.sdkAppId == credentials.sdkAppId &&
        _credentials?.userId == credentials.userId &&
        _credentials?.userSig == credentials.userSig &&
        _credentials?.expiresAt == credentials.expiresAt &&
        _credentials?.ttlSeconds == credentials.ttlSeconds &&
        _credentials?.systemAccount == credentials.systemAccount) {
      return;
    }
    if (_credentials != null &&
        (_credentials!.sdkAppId != credentials.sdkAppId ||
            _credentials!.userId != credentials.userId)) {
      _fail(ImSessionFailure.identityMismatch, 'IM 会话用户不匹配');
    }
    if (failRenew) {
      _fail(ImSessionFailure.renew, '腾讯 IM 凭证续期失败');
    }
    await login(credentials);
  }

  @override
  Future<void> logout() async {
    logoutCalls += 1;
    if (failLogout) {
      _credentials = null;
      _setState(const ImSessionState(status: ImSessionStatus.error));
      _logger?.call(ImLifecycleMarker.logoutFailed);
      throw const ImSessionException(
        failure: ImSessionFailure.logout,
        message: '腾讯 IM 登出失败',
      );
    }
    _credentials = null;
    _setState(const ImSessionState.idle());
    _logger?.call(ImLifecycleMarker.logoutSucceeded);
  }

  @override
  Future<void> uninitialize() async {
    uninitializeCalls += 1;
    if (failUninitialize) {
      _credentials = null;
      _setState(const ImSessionState(status: ImSessionStatus.error));
      _logger?.call(ImLifecycleMarker.uninitializeFailed);
      throw const ImSessionException(
        failure: ImSessionFailure.uninitialize,
        message: '腾讯 IM 反初始化失败',
      );
    }
    _credentials = null;
    _setState(const ImSessionState.idle());
    _logger?.call(ImLifecycleMarker.uninitializeSucceeded);
  }

  Future<void> dispose() async {
    if (!_stateController.isClosed) {
      await _stateController.close();
    }
    if (!_eventController.isClosed) {
      await _eventController.close();
    }
  }

  /// Test and mock seam for provider callbacks.  The production Tencent
  /// adapter emits the same event values after validating native callbacks.
  void emitEvent(ImSessionEvent event) {
    if (!_eventController.isClosed) {
      if (event.kind == ImSessionEventKind.networkOffline && isReady) {
        _setState(
          ImSessionState(
            status: ImSessionStatus.offline,
            activeUserId: _credentials?.userId,
            expiresAt: _credentials?.expiresAt,
          ),
        );
      } else if (event.kind == ImSessionEventKind.networkOnline &&
          _credentials != null &&
          _state.status == ImSessionStatus.offline) {
        _setState(
          ImSessionState(
            status: ImSessionStatus.reconnecting,
            activeUserId: _credentials?.userId,
            expiresAt: _credentials?.expiresAt,
          ),
        );
      } else if (event.kind == ImSessionEventKind.userSigExpired &&
          _credentials != null) {
        _setState(
          ImSessionState(
            status: ImSessionStatus.expired,
            activeUserId: _credentials?.userId,
            expiresAt: _credentials?.expiresAt,
            failure: ImSessionFailure.invalidCredentials,
          ),
        );
      }
      _eventController.add(event);
    }
  }

  void emitUserSigExpired() => emitEvent(const ImSessionEvent.userSigExpired());

  void emitNetworkOffline() => emitEvent(const ImSessionEvent.networkOffline());

  void emitNetworkOnline() => emitEvent(const ImSessionEvent.networkOnline());

  void emitCustomElement(Object? raw, {required bool trustedSource}) {
    final ImRefreshHint? hint = ImRefreshHint.tryParse(
      raw,
      trustedSource: trustedSource,
    );
    if (hint != null) {
      emitEvent(ImSessionEvent.refresh(hint));
    }
  }

  void _validate(ImSessionCredentials credentials, ImSessionFailure failure) {
    if (credentials.provider != ImSessionCredentials.expectedProvider ||
        credentials.imStatus != ImSessionCredentials.readyStatus ||
        credentials.sdkAppId <= 0 ||
        !ImSessionCredentials.isCanonicalUserId(credentials.userId) ||
        !ImSessionCredentials.isValidSystemAccount(credentials.systemAccount) ||
        !ImSessionCredentials.isValidUserSig(credentials.userSig) ||
        !ImSessionCredentials.isValidTtlSeconds(credentials.ttlSeconds) ||
        !ImSessionCredentials.isExpiryConsistent(
          expiresAt: credentials.expiresAt,
          ttlSeconds: credentials.ttlSeconds,
          now: _now(),
        )) {
      _fail(failure, 'IM 凭证无效');
    }
    if (credentials.isExpired(_now())) {
      _setState(
        ImSessionState(
          status: ImSessionStatus.expired,
          activeUserId: credentials.userId,
          expiresAt: credentials.expiresAt,
          failure: ImSessionFailure.invalidCredentials,
        ),
      );
      _logger?.call(ImLifecycleMarker.expired);
      throw const ImSessionException(
        failure: ImSessionFailure.invalidCredentials,
        message: 'IM 凭证已过期',
      );
    }
  }

  Never _fail(ImSessionFailure failure, String message) {
    _setState(ImSessionState(status: ImSessionStatus.error, failure: failure));
    throw ImSessionException(failure: failure, message: message);
  }

  void _setState(ImSessionState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }
}
