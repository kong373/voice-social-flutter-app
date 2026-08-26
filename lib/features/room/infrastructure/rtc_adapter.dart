import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

abstract interface class RtcAdapter {
  Future<void> join(RtcCredentials credentials);

  Future<void> reconnect(RtcCredentials credentials);

  Future<void> setLocalAudioEnabled(bool enabled);

  Future<void> leave();
}

typedef RtcCredentialsProvider = Future<RtcCredentials> Function(String roomId);
typedef AgoraRtcEngineFactory = RtcEngine Function();

/// Provider-neutral lifecycle events emitted by [AgoraRtcAdapter].
enum RtcAdapterEventType {
  initialized,
  joined,
  rejoined,
  left,
  remoteUserJoined,
  remoteUserLeft,
  remoteUserMuted,
  connectionChanged,
  tokenRenewed,
  error,
}

class RtcAdapterEvent {
  const RtcAdapterEvent({
    required this.type,
    this.uid,
    this.providerCode,
    this.message,
  });

  final RtcAdapterEventType type;
  final int? uid;
  final int? providerCode;
  final String? message;
}

enum RtcAdapterFailure {
  invalidCredentials,
  notInitialized,
  initialize,
  join,
  leave,
  mute,
  permission,
  renewToken,
  disposed,
  provider,
}

/// Safe, provider-neutral error returned by the adapter.
///
/// The provider SDK's free-form message is deliberately not retained. Some
/// SDK errors can echo request material; callers only need the stable failure
/// class and numeric provider code for diagnostics and recovery UI.
class RtcAdapterException implements Exception {
  const RtcAdapterException({
    required this.failure,
    required this.message,
    this.providerCode,
  });

  final RtcAdapterFailure failure;
  final String message;
  final int? providerCode;

  @override
  String toString() =>
      'RtcAdapterException(${failure.name}, providerCode=$providerCode): '
      '$message';
}

/// Agora RTC audio-only transport.
///
/// The adapter is intentionally inert until [join] receives a complete,
/// server-issued [RtcCredentials] value. It never reads a provider signing
/// secret. Tests and host integrations can inject an engine and a token
/// provider; the default factory is the official Agora engine factory.
class AgoraRtcAdapter implements RtcAdapter {
  static const Duration _defaultJoinTimeout = Duration(seconds: 15);
  static const Duration _defaultLeaveTimeout = Duration(seconds: 10);
  static const Duration _defaultRenewTimeout = Duration(seconds: 10);

  AgoraRtcAdapter({
    RtcEngine? engine,
    AgoraRtcEngineFactory? engineFactory,
    RtcCredentialsProvider? credentialsProvider,
    NativePermissionAdapter? microphonePermissionAdapter,
    DateTime Function()? now,
    Duration joinTimeout = _defaultJoinTimeout,
    Duration leaveTimeout = _defaultLeaveTimeout,
    Duration renewTimeout = _defaultRenewTimeout,
  }) : _engine = engine,
       _injectedEngine = engine,
       _engineInjected = engine != null,
       _engineFactory = engineFactory ?? createAgoraRtcEngine,
       _credentialsProvider = credentialsProvider,
       _microphonePermissionAdapter = microphonePermissionAdapter,
       _now = now ?? DateTime.now,
       _joinTimeout = joinTimeout,
       _leaveTimeout = leaveTimeout,
       _renewTimeout = renewTimeout;

  final AgoraRtcEngineFactory _engineFactory;
  final RtcCredentialsProvider? _credentialsProvider;
  final NativePermissionAdapter? _microphonePermissionAdapter;
  final DateTime Function() _now;
  final Duration _joinTimeout;
  final Duration _leaveTimeout;
  final Duration _renewTimeout;
  final bool _engineInjected;
  RtcEngine? _injectedEngine;
  RtcEngine? _engine;
  RtcEngineEventHandler? _eventHandler;
  RtcCredentials? _credentials;
  RtcCredentials? _joiningCredentials;
  RtcCredentials? _renewingCredentials;
  Future<void>? _renewalInFlight;
  Future<void>? _initializeInFlight;
  Future<void>? _joinInFlight;
  Future<void>? _leaveInFlight;
  Future<void>? _reconnectInFlight;
  _RtcSessionIdentity? _joinInFlightIdentity;
  _RtcSessionIdentity? _reconnectInFlightIdentity;
  Completer<void>? _joinCompletion;
  Completer<void>? _joinCancellation;
  Completer<void>? _initializeCancellation;
  Completer<void>? _leaveCompletion;
  Completer<void>? _renewCompletion;
  Completer<void>? _renewCancellation;
  StreamController<RtcAdapterEvent>? _events;
  bool _handlerRegistered = false;
  bool _initialized = false;
  bool _joined = false;
  bool _joining = false;
  bool _localAudioEnabled = false;
  bool _disposed = false;
  bool _disposing = false;
  bool _joinEventReported = false;
  bool _channelOperationPending = false;
  int _engineGeneration = 0;
  int _callbackGeneration = 0;
  int _lifecycleGeneration = 0;
  int? _joinLogicalGeneration;
  int? _activeSessionGeneration;
  int? _leavingSessionGeneration;
  int? _leavingEngineGeneration;
  int? _leavingCallbackGeneration;
  String? _activeChannelId;
  int? _activeUid;
  int? _callbackSessionGeneration;
  String? _leavingChannelId;
  int? _leavingUid;

  Stream<RtcAdapterEvent> get events =>
      (_events ??= StreamController<RtcAdapterEvent>.broadcast(
        sync: true,
      )).stream;

  RtcCredentials? get credentials => _credentials;
  bool get initialized => _initialized;
  bool get joined => _joined;
  bool get localAudioEnabled => _localAudioEnabled;

  /// Initializes the native engine for [credentials.appId]. Calls are
  /// serialized so a reconnect, a foreground refresh, and a first join cannot
  /// create competing native engines.
  Future<void> initialize(RtcCredentials credentials) async {
    _ensureNotDisposed();
    final Future<void>? joining = _joinInFlight;
    if (joining != null) {
      await joining;
    }
    await _initializeWithFlight(credentials);
  }

  Future<void> _initializeWithFlight(RtcCredentials credentials) async {
    _validateCredentials(credentials);
    while (true) {
      _ensureNotDisposed();
      final RtcCredentials? activeCredentials = _credentials;
      if (_joined) {
        if (activeCredentials == null ||
            !_sameSessionIdentity(activeCredentials, credentials)) {
          throw _sessionIdentityConflict(RtcAdapterFailure.initialize);
        }
        // An initialized/joined SDK already owns this session. A new token is
        // applied only by renewToken/reconnect, never by initialize.
        return;
      }
      if (_initialized &&
          activeCredentials?.appId.trim() == credentials.appId.trim()) {
        _credentials = credentials;
        return;
      }
      final Future<void>? inFlight = _initializeInFlight;
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      final Future<void> operation = _initializeInternal(credentials);
      _initializeInFlight = operation;
      operation.then<void>(
        (_) {
          if (identical(_initializeInFlight, operation)) {
            _initializeInFlight = null;
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_initializeInFlight, operation)) {
            _initializeInFlight = null;
          }
        },
      );
      await operation;
      return;
    }
  }

  Future<void> _initializeInternal(RtcCredentials credentials) async {
    if (_joined) {
      final RtcCredentials? activeCredentials = _credentials;
      if (activeCredentials == null ||
          !_sameSessionIdentity(activeCredentials, credentials)) {
        throw _sessionIdentityConflict(RtcAdapterFailure.initialize);
      }
      return;
    }
    final Future<void>? leaving = _leaveInFlight;
    if (leaving != null) {
      await leaving;
    }
    _ensureNotDisposed();

    final RtcEngine? existing = _engine;
    final bool useInjectedEngine =
        !_initialized &&
        existing != null &&
        _engineInjected &&
        identical(existing, _injectedEngine);
    if (existing != null && !useInjectedEngine) {
      _engine = null;
      _initialized = false;
      _credentials = null;
      ++_engineGeneration;
      await _releaseEngine(existing);
    }

    RtcEngine? createdEngine;
    final int engineGeneration = ++_engineGeneration;
    final Completer<void> initializationCancellation = Completer<void>();
    _initializeCancellation = initializationCancellation;
    final Future<void> cancelled = initializationCancellation.future.then<void>(
      (_) => throw const _RtcOperationCancelled(),
    );
    try {
      createdEngine = useInjectedEngine ? existing : _engineFactory();
      if (useInjectedEngine) {
        _injectedEngine = null;
      }
      await Future.any<void>(<Future<void>>[
        createdEngine.initialize(
          RtcEngineContext(
            appId: credentials.appId,
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          ),
        ),
        cancelled,
      ]);
      _ensureNotDisposed();
      await Future.any<void>(<Future<void>>[
        createdEngine.enableAudio(),
        cancelled,
      ]);
      _ensureNotDisposed();
      _engine = createdEngine;
      _initialized = true;
      _credentials = credentials;
      _installEventHandler(createdEngine, engineGeneration);
      _emit(const RtcAdapterEvent(type: RtcAdapterEventType.initialized));
    } on AgoraRtcException catch (error) {
      if (createdEngine != null) {
        await _releaseEngine(createdEngine);
      }
      if (identical(_engine, createdEngine)) {
        _engine = null;
      }
      _initialized = false;
      _credentials = null;
      throw _providerException(
        RtcAdapterFailure.initialize,
        error.code,
        fallback: 'Agora RTC 初始化失败',
      );
    } on RtcAdapterException {
      if (createdEngine != null) {
        await _releaseEngine(createdEngine);
      }
      if (identical(_engine, createdEngine)) {
        _engine = null;
      }
      _initialized = false;
      _credentials = null;
      rethrow;
    } catch (_) {
      if (createdEngine != null) {
        await _releaseEngine(createdEngine);
      }
      if (identical(_engine, createdEngine)) {
        _engine = null;
      }
      _initialized = false;
      _credentials = null;
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.initialize,
        message: 'Agora RTC 初始化失败',
      );
    } finally {
      if (identical(_initializeCancellation, initializationCancellation)) {
        _initializeCancellation = null;
      }
    }
  }

  @override
  Future<void> join(RtcCredentials credentials) {
    _ensureNotDisposed();
    final _RtcSessionIdentity requestedIdentity =
        _RtcSessionIdentity.fromCredentials(credentials);
    final Future<void>? inFlight = _joinInFlight;
    if (inFlight != null) {
      if (_joinInFlightIdentity == requestedIdentity) {
        return inFlight;
      }
      return Future<void>.error(
        _sessionIdentityConflict(RtcAdapterFailure.join),
      );
    }
    final RtcCredentials? activeCredentials = _credentials;
    if (_joined &&
        (activeCredentials == null ||
            !_sameSessionIdentity(activeCredentials, credentials))) {
      return Future<void>.error(
        _sessionIdentityConflict(RtcAdapterFailure.join),
      );
    }
    _joinInFlightIdentity = requestedIdentity;
    final Future<void> operation = _joinInternal(credentials);
    _joinInFlight = operation;
    operation.then<void>(
      (_) {
        if (identical(_joinInFlight, operation)) {
          _joinInFlight = null;
        }
        if (identical(_joinInFlightIdentity, requestedIdentity)) {
          _joinInFlightIdentity = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_joinInFlight, operation)) {
          _joinInFlight = null;
        }
        if (identical(_joinInFlightIdentity, requestedIdentity)) {
          _joinInFlightIdentity = null;
        }
      },
    );
    return operation;
  }

  Future<void> _joinInternal(RtcCredentials credentials) async {
    _validateCredentials(credentials);
    if (_joined) {
      final RtcCredentials? activeCredentials = _credentials;
      if (activeCredentials == null ||
          !_sameSessionIdentity(activeCredentials, credentials)) {
        throw _sessionIdentityConflict(RtcAdapterFailure.join);
      }
      // Calling join twice for the same session is idempotent. In particular,
      // do not replace the active token with one that was never applied to the
      // native channel; use renewToken or reconnect for that operation.
      return;
    }
    final Future<void>? leaving = _leaveInFlight;
    if (leaving != null) {
      await leaving;
    }
    await _initializeWithFlight(credentials);
    _ensureNotDisposed();
    final RtcEngine engine = _requireEngine();
    if (_joined) {
      if (_credentials == null ||
          !_sameSessionIdentity(_credentials!, credentials)) {
        throw _sessionIdentityConflict(RtcAdapterFailure.join);
      }
      return;
    }
    final ClientRoleType role = _roleFor(credentials.role);
    final int lifecycleGeneration = _lifecycleGeneration;
    final int engineGeneration = _engineGeneration;
    _installEventHandler(
      engine,
      engineGeneration,
      sessionGeneration: lifecycleGeneration,
    );
    final int callbackGeneration = _callbackGeneration;
    final Completer<void> joinCompletion = Completer<void>();
    final Completer<void> joinCancellation = Completer<void>();
    _joinCompletion = joinCompletion;
    _joinCancellation = joinCancellation;
    _joiningCredentials = credentials;
    _joinLogicalGeneration = lifecycleGeneration;
    _channelOperationPending = true;
    _activeChannelId = credentials.channelId;
    _activeUid = credentials.uid;
    _joinEventReported = false;
    _joining = true;
    try {
      final Future<void> nativeJoin = engine.joinChannel(
        token: credentials.token,
        channelId: credentials.channelId,
        uid: credentials.uid,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: role,
          // Entering a room must never open the microphone implicitly. A
          // later explicit setLocalAudioEnabled(true) performs the OS
          // permission check and enables publication.
          publishMicrophoneTrack: false,
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
        ),
      );
      final Future<void> cancelled = joinCancellation.future.then<void>(
        (_) => throw const _RtcOperationCancelled(),
      );
      // The SDK Future only acknowledges invocation. Treat its error as a
      // failure signal, but wait for onJoinChannelSuccess before declaring the
      // channel joined. This also allows the callback to win when invocation
      // completion is delayed by a native bridge.
      unawaited(
        nativeJoin.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!joinCompletion.isCompleted) {
              joinCompletion.completeError(error, stack);
            }
          },
        ),
      );
      try {
        await Future.any<void>(<Future<void>>[
          joinCompletion.future,
          cancelled,
        ]).timeout(_joinTimeout);
      } on TimeoutException {
        throw const RtcAdapterException(
          failure: RtcAdapterFailure.join,
          message: 'Agora RTC 加入频道超时',
        );
      }
      if (!_isJoinGenerationActive(lifecycleGeneration, callbackGeneration)) {
        return;
      }
      _credentials = credentials;
      _joined = true;
      _activeSessionGeneration = lifecycleGeneration;
      _localAudioEnabled = false;
      _emitJoinedEvent();
    } on AgoraRtcException catch (error) {
      if (!_isJoinGenerationActive(lifecycleGeneration, callbackGeneration)) {
        return;
      }
      await _abortFailedJoin(engine, engineGeneration, callbackGeneration);
      throw _providerException(
        RtcAdapterFailure.join,
        error.code,
        fallback: 'Agora RTC 加入频道失败',
      );
    } on RtcAdapterException {
      if (!_isJoinGenerationActive(lifecycleGeneration, callbackGeneration)) {
        return;
      }
      await _abortFailedJoin(engine, engineGeneration, callbackGeneration);
      rethrow;
    } catch (_) {
      if (!_isJoinGenerationActive(lifecycleGeneration, callbackGeneration)) {
        return;
      }
      await _abortFailedJoin(engine, engineGeneration, callbackGeneration);
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.join,
        message: 'Agora RTC 加入频道失败',
      );
    } finally {
      if (identical(_joinCompletion, joinCompletion)) {
        _joinCompletion = null;
      }
      if (identical(_joinCancellation, joinCancellation)) {
        _joinCancellation = null;
      }
      _joiningCredentials = null;
      _joinLogicalGeneration = null;
      _joining = false;
    }
  }

  @override
  Future<void> reconnect(RtcCredentials credentials) {
    _ensureNotDisposed();
    _validateCredentials(credentials);
    final _RtcSessionIdentity requestedIdentity =
        _RtcSessionIdentity.fromCredentials(credentials);
    final Future<void>? inFlight = _reconnectInFlight;
    if (inFlight != null) {
      if (_reconnectInFlightIdentity == requestedIdentity) {
        return inFlight;
      }
      return Future<void>.error(
        _sessionIdentityConflict(RtcAdapterFailure.join),
      );
    }
    _reconnectInFlightIdentity = requestedIdentity;
    final Future<void> operation = _reconnectInternal(credentials);
    _reconnectInFlight = operation;
    operation.then<void>(
      (_) {
        if (identical(_reconnectInFlight, operation)) {
          _reconnectInFlight = null;
        }
        if (identical(_reconnectInFlightIdentity, requestedIdentity)) {
          _reconnectInFlightIdentity = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_reconnectInFlight, operation)) {
          _reconnectInFlight = null;
        }
        if (identical(_reconnectInFlightIdentity, requestedIdentity)) {
          _reconnectInFlightIdentity = null;
        }
      },
    );
    return operation;
  }

  Future<void> _reconnectInternal(RtcCredentials credentials) async {
    final bool wasAudioEnabled = _localAudioEnabled;
    try {
      await leave();
      await join(credentials);
      final ClientRoleType role = _roleFor(credentials.role);
      await setLocalAudioEnabled(
        wasAudioEnabled && role == ClientRoleType.clientRoleBroadcaster,
      );
    } catch (_) {
      try {
        await leave();
      } catch (_) {
        // Preserve the original reconnect failure.
      }
      rethrow;
    }
    _emit(const RtcAdapterEvent(type: RtcAdapterEventType.rejoined));
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    _ensureNotDisposed();
    if (!_joined) {
      return;
    }
    final RtcEngine engine = _requireEngine();
    final RtcCredentials current = _credentials!;
    final ClientRoleType role = _roleFor(current.role);
    final int lifecycleGeneration = _lifecycleGeneration;
    if (enabled && role != ClientRoleType.clientRoleBroadcaster) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.mute,
        message: '当前 RTC 角色不能发布麦克风',
      );
    }
    if (enabled && !await _hasMicrophonePermission()) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.permission,
        message: '麦克风权限未授予',
      );
    }
    if (_disposed ||
        _disposing ||
        !_joined ||
        lifecycleGeneration != _lifecycleGeneration) {
      return;
    }
    bool mediaOptionsUpdated = false;
    try {
      await engine.updateChannelMediaOptions(
        ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: role,
          publishMicrophoneTrack: enabled,
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
        ),
      );
      mediaOptionsUpdated = true;
      await engine.muteLocalAudioStream(!enabled);
      if (!_disposed &&
          !_disposing &&
          _joined &&
          lifecycleGeneration == _lifecycleGeneration) {
        _localAudioEnabled = enabled;
      }
    } on AgoraRtcException catch (error) {
      await _rollbackAudioPublication(
        engine,
        role: role,
        enabled: enabled,
        mediaOptionsUpdated: mediaOptionsUpdated,
      );
      throw _providerException(
        RtcAdapterFailure.mute,
        error.code,
        fallback: 'Agora RTC 麦克风状态切换失败',
      );
    } catch (_) {
      await _rollbackAudioPublication(
        engine,
        role: role,
        enabled: enabled,
        mediaOptionsUpdated: mediaOptionsUpdated,
      );
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.mute,
        message: 'Agora RTC 麦克风状态切换失败',
      );
    }
  }

  @override
  Future<void> leave() {
    if (_disposed || _disposing) {
      return Future<void>.value();
    }
    final Future<void>? inFlight = _leaveInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final Future<void> operation = _leaveInternal(emitEvent: true);
    _leaveInFlight = operation;
    operation.then<void>(
      (_) {
        if (identical(_leaveInFlight, operation)) {
          _leaveInFlight = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_leaveInFlight, operation)) {
          _leaveInFlight = null;
        }
      },
    );
    return operation;
  }

  Future<void> _leaveInternal({required bool emitEvent}) async {
    ++_lifecycleGeneration;
    _cancelJoinWait();
    _cancelRenewalWait();
    final Future<void>? joining = _joinInFlight;
    if (joining != null) {
      try {
        await joining;
      } catch (_) {
        // The leave operation owns cancellation and still tears down native
        // state below.
      }
    }

    final RtcEngine? engine = _engine;
    final bool hadPendingChannel = _channelOperationPending || _joined;
    final bool wasJoined = _joined;
    _joined = false;
    _localAudioEnabled = false;
    _joinEventReported = false;
    if (!hadPendingChannel || engine == null) {
      _channelOperationPending = false;
      _activeSessionGeneration = null;
      return;
    }

    final int engineGeneration = _engineGeneration;
    final int callbackGeneration = _callbackGeneration;
    final String? channelId = _activeChannelId;
    final int? uid = _activeUid;
    final Completer<void> completion = Completer<void>();
    _leaveCompletion = completion;
    _leavingEngineGeneration = engineGeneration;
    _leavingCallbackGeneration = callbackGeneration;
    _leavingSessionGeneration = _activeSessionGeneration;
    _leavingChannelId = channelId;
    _leavingUid = uid;
    Object? failure;
    try {
      await engine.leaveChannel();
      try {
        await completion.future.timeout(_leaveTimeout);
      } on TimeoutException {
        failure = const RtcAdapterException(
          failure: RtcAdapterFailure.leave,
          message: 'Agora RTC 离开频道超时',
        );
      }
    } on AgoraRtcException catch (error) {
      failure = _providerException(
        RtcAdapterFailure.leave,
        error.code,
        fallback: 'Agora RTC 离开频道失败',
      );
    } catch (_) {
      failure = const RtcAdapterException(
        failure: RtcAdapterFailure.leave,
        message: 'Agora RTC 离开频道失败',
      );
    } finally {
      _finalizeChannelState();
    }
    if (failure != null) {
      throw failure;
    }
    if (emitEvent && wasJoined) {
      _emit(const RtcAdapterEvent(type: RtcAdapterEventType.left));
    }
  }

  /// Fetches and applies a fresh token. Concurrent expiry callbacks share one
  /// request and one SDK renewal call.
  Future<void> renewToken() {
    if (_disposed || _disposing || !_joined) {
      return Future<void>.value();
    }
    final Future<void>? current = _renewalInFlight;
    if (current != null) {
      return current;
    }
    final RtcCredentials currentCredentials = _credentials!;
    final int generation = _lifecycleGeneration;
    final Future<void> request = _renewToken(
      currentCredentials,
      generation: generation,
    );
    _renewalInFlight = request;
    request.then<void>(
      (_) {
        if (identical(_renewalInFlight, request)) {
          _renewalInFlight = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_renewalInFlight, request)) {
          _renewalInFlight = null;
        }
      },
    );
    return request;
  }

  /// Releases the native engine and prevents callbacks from starting work.
  Future<void> release() async {
    if (_disposed || _disposing) {
      return;
    }
    _disposing = true;
    ++_lifecycleGeneration;
    _cancelInitializeWait();
    _cancelJoinWait();
    _cancelRenewalWait();

    final Future<void>? initializing = _initializeInFlight;
    if (initializing != null) {
      try {
        await initializing;
      } catch (_) {
        // Initialization owns its partially-created engine cleanup.
      }
    }
    final Future<void>? joining = _joinInFlight;
    if (joining != null) {
      try {
        await joining;
      } catch (_) {
        // Release continues through native teardown.
      }
    }
    final Future<void>? leaving = _leaveInFlight;
    if (leaving != null) {
      try {
        await leaving;
      } catch (_) {
        // Release continues through native teardown.
      }
    }

    if (_channelOperationPending && _engine != null) {
      try {
        await _leaveInternal(emitEvent: false);
      } catch (_) {
        // Continue to release native resources even if the channel is already
        // gone or the provider reports a leave timeout during teardown.
      }
    }

    final RtcEngine? engine = _engine;
    ++_engineGeneration;
    _disposed = true;
    _joined = false;
    _joining = false;
    _localAudioEnabled = false;
    _engine = null;
    _initialized = false;
    _credentials = null;
    if (engine != null) {
      await _releaseEngine(engine);
    }
    final StreamController<RtcAdapterEvent>? events = _events;
    _events = null;
    if (events != null && !events.isClosed) {
      await events.close();
    }
  }

  Future<void> dispose() => release();

  Future<void> _renewToken(
    RtcCredentials current, {
    required int generation,
  }) async {
    final RtcCredentialsProvider? provider = _credentialsProvider;
    if (provider == null) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.renewToken,
        message: 'RTC 凭证刷新能力尚未配置',
      );
    }
    final RtcCredentials next;
    try {
      next = await provider(current.channelId);
    } catch (_) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.renewToken,
        message: 'RTC 凭证刷新请求失败',
      );
    }
    try {
      _validateCredentials(next);
    } on RtcAdapterException catch (error) {
      throw RtcAdapterException(
        failure: RtcAdapterFailure.renewToken,
        message: error.message,
        providerCode: error.providerCode,
      );
    }
    if (_disposed ||
        _disposing ||
        !_joined ||
        generation != _lifecycleGeneration) {
      return;
    }
    if (next.appId != current.appId ||
        next.channelId != current.channelId ||
        next.uid != current.uid ||
        _roleFor(next.role) != _roleFor(current.role)) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.renewToken,
        message: 'RTC 刷新凭证与当前频道不一致',
      );
    }
    final RtcEngine engine = _requireEngine();
    final Completer<void> completion = Completer<void>();
    final Completer<void> cancellation = Completer<void>();
    _renewCompletion = completion;
    _renewCancellation = cancellation;
    _renewingCredentials = next;
    final Future<void> cancelled = cancellation.future.then<void>(
      (_) => throw const _RtcOperationCancelled(),
    );
    try {
      final Future<void> nativeRenew = engine.renewToken(next.token);
      // A successful native Future means only that the request was accepted;
      // onRenewTokenResult remains the source of truth for the new token.
      unawaited(
        nativeRenew.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!completion.isCompleted) {
              completion.completeError(error, stack);
            }
          },
        ),
      );
      try {
        await Future.any<void>(<Future<void>>[
          completion.future,
          cancelled,
        ]).timeout(_renewTimeout);
      } on _RtcOperationCancelled {
        return;
      } on TimeoutException {
        throw const RtcAdapterException(
          failure: RtcAdapterFailure.renewToken,
          message: 'Agora RTC 凭证刷新超时',
        );
      }
      if (!_disposed &&
          !_disposing &&
          _joined &&
          generation == _lifecycleGeneration) {
        _credentials = next;
        _emit(const RtcAdapterEvent(type: RtcAdapterEventType.tokenRenewed));
      }
    } on AgoraRtcException catch (error) {
      throw _providerException(
        RtcAdapterFailure.renewToken,
        error.code,
        fallback: 'Agora RTC 凭证刷新失败',
      );
    } on RtcAdapterException {
      rethrow;
    } catch (_) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.renewToken,
        message: 'Agora RTC 凭证刷新失败',
      );
    } finally {
      if (identical(_renewCompletion, completion)) {
        _renewCompletion = null;
      }
      if (identical(_renewCancellation, cancellation)) {
        _renewCancellation = null;
      }
      _renewingCredentials = null;
    }
  }

  void _installEventHandler(
    RtcEngine engine,
    int engineGeneration, {
    int? sessionGeneration,
  }) {
    if (_handlerRegistered && _eventHandler != null) {
      try {
        engine.unregisterEventHandler(_eventHandler!);
      } catch (_) {
        // Continue by installing a fresh generation-bound handler.
      }
      _handlerRegistered = false;
    }
    final int callbackGeneration = ++_callbackGeneration;
    _callbackSessionGeneration = sessionGeneration;
    final RtcEngineEventHandler handler = RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, _) {
        if (_matchesConnection(
              engine,
              engineGeneration,
              callbackGeneration,
              connection,
            ) &&
            _joining &&
            _joinLogicalGeneration == _lifecycleGeneration) {
          final Completer<void>? completion = _joinCompletion;
          if (completion != null && !completion.isCompleted) {
            completion.complete();
          }
        }
      },
      onRejoinChannelSuccess: (RtcConnection connection, _) {
        if (_matchesConnection(
              engine,
              engineGeneration,
              callbackGeneration,
              connection,
            ) &&
            _joined &&
            !_disposing) {
          _emit(const RtcAdapterEvent(type: RtcAdapterEventType.rejoined));
        }
      },
      onError: (ErrorCodeType error, String _) {
        if (!_matchesEngine(engine, engineGeneration, callbackGeneration)) {
          return;
        }
        if (_joining && _joinLogicalGeneration == _lifecycleGeneration) {
          final Completer<void>? completion = _joinCompletion;
          if (completion != null && !completion.isCompleted) {
            completion.completeError(
              _providerException(
                RtcAdapterFailure.join,
                error.value(),
                fallback: 'Agora RTC 加入频道失败',
              ),
            );
          }
        } else if (_joined && !_disposing) {
          _emit(
            RtcAdapterEvent(
              type: RtcAdapterEventType.error,
              providerCode: error.value(),
              message: 'Agora RTC 运行时错误',
            ),
          );
        }
      },
      onRequestToken: (RtcConnection connection) {
        if (_matchesConnection(
          engine,
          engineGeneration,
          callbackGeneration,
          connection,
        )) {
          _scheduleRenewal();
        }
      },
      onTokenPrivilegeWillExpire: (RtcConnection connection, _) {
        if (_matchesConnection(
          engine,
          engineGeneration,
          callbackGeneration,
          connection,
        )) {
          _scheduleRenewal();
        }
      },
      onUserJoined: (RtcConnection connection, int uid, __) {
        if (_matchesConnection(
              engine,
              engineGeneration,
              callbackGeneration,
              connection,
            ) &&
            !_disposing) {
          _emit(
            RtcAdapterEvent(
              type: RtcAdapterEventType.remoteUserJoined,
              uid: uid,
            ),
          );
        }
      },
      onUserOffline: (RtcConnection connection, int uid, __) {
        if (_matchesConnection(
              engine,
              engineGeneration,
              callbackGeneration,
              connection,
            ) &&
            !_disposing) {
          _emit(
            RtcAdapterEvent(type: RtcAdapterEventType.remoteUserLeft, uid: uid),
          );
        }
      },
      onUserMuteAudio: (RtcConnection connection, int uid, bool muted) {
        if (_matchesConnection(
              engine,
              engineGeneration,
              callbackGeneration,
              connection,
            ) &&
            !_disposing) {
          _emit(
            RtcAdapterEvent(
              type: RtcAdapterEventType.remoteUserMuted,
              uid: uid,
              message: muted ? 'muted' : 'unmuted',
            ),
          );
        }
      },
      onConnectionStateChanged:
          (RtcConnection connection, ConnectionStateType state, __) {
            if (!_matchesConnection(
              engine,
              engineGeneration,
              callbackGeneration,
              connection,
              allowDisposing: true,
            )) {
              return;
            }
            if (state == ConnectionStateType.connectionStateDisconnected &&
                _isExpectedLeaveCallback(
                  engineGeneration,
                  callbackGeneration,
                  connection,
                )) {
              _completeLeaveWait();
            }
            if (state == ConnectionStateType.connectionStateFailed &&
                _joining &&
                _joinLogicalGeneration == _lifecycleGeneration) {
              final Completer<void>? completion = _joinCompletion;
              if (completion != null && !completion.isCompleted) {
                completion.completeError(
                  _providerException(
                    RtcAdapterFailure.join,
                    state.value(),
                    fallback: 'Agora RTC 加入频道失败',
                  ),
                );
              }
            }
            if (!_disposing) {
              _emit(
                RtcAdapterEvent(
                  type: RtcAdapterEventType.connectionChanged,
                  message: state.name,
                ),
              );
            }
          },
      onLeaveChannel: (RtcConnection connection, _) {
        if (!_matchesConnection(
          engine,
          engineGeneration,
          callbackGeneration,
          connection,
          allowDisposing: true,
        )) {
          return;
        }
        if (_isExpectedLeaveCallback(
          engineGeneration,
          callbackGeneration,
          connection,
        )) {
          _completeLeaveWait();
        }
      },
      onRenewTokenResult:
          (RtcConnection connection, String token, RenewTokenErrorCode code) {
            if (!_matchesConnection(
              engine,
              engineGeneration,
              callbackGeneration,
              connection,
            )) {
              return;
            }
            final Completer<void>? completion = _renewCompletion;
            final RtcCredentials? renewing = _renewingCredentials;
            if (completion != null &&
                renewing != null &&
                !completion.isCompleted) {
              if (code == RenewTokenErrorCode.renewTokenSuccess &&
                  token == renewing.token) {
                completion.complete();
              } else if (code != RenewTokenErrorCode.renewTokenSuccess) {
                completion.completeError(
                  _providerException(
                    RtcAdapterFailure.renewToken,
                    code.value(),
                    fallback: 'Agora RTC 凭证刷新失败',
                  ),
                );
              }
            }
            if (!_disposing && code != RenewTokenErrorCode.renewTokenSuccess) {
              _emit(
                RtcAdapterEvent(
                  type: RtcAdapterEventType.error,
                  providerCode: code.value(),
                  message: 'Agora RTC 凭证刷新失败',
                ),
              );
            }
          },
    );
    _eventHandler = handler;
    engine.registerEventHandler(handler);
    _handlerRegistered = true;
  }

  Future<bool> _hasMicrophonePermission() async {
    final NativePermissionAdapter? adapter = _microphonePermissionAdapter;
    if (adapter == null) {
      return false;
    }
    try {
      PermissionState state = await adapter.status(PermissionKind.microphone);
      if (state == PermissionState.granted) {
        return true;
      }
      if (state == PermissionState.permanentlyDenied ||
          state == PermissionState.restricted ||
          state == PermissionState.unavailable) {
        return false;
      }
      state = await adapter.request(PermissionKind.microphone);
      return state == PermissionState.granted;
    } on Object {
      return false;
    }
  }

  Future<void> _abortFailedJoin(
    RtcEngine engine,
    int engineGeneration,
    int callbackGeneration,
  ) async {
    if (!_channelOperationPending ||
        !identical(_engine, engine) ||
        engineGeneration != _engineGeneration ||
        callbackGeneration != _callbackGeneration) {
      return;
    }
    final Completer<void> completion = Completer<void>();
    _leaveCompletion = completion;
    _leavingEngineGeneration = engineGeneration;
    _leavingCallbackGeneration = callbackGeneration;
    _leavingSessionGeneration = _joinLogicalGeneration;
    _leavingChannelId = _activeChannelId;
    _leavingUid = _activeUid;
    try {
      await engine.leaveChannel();
      try {
        await completion.future.timeout(_leaveTimeout);
      } on TimeoutException {
        // The failed join is already unusable; finalize the local state after
        // the bounded wait so the next join cannot race an old operation.
      }
    } catch (_) {
      // Failed joins are reported by the original join error. Teardown is
      // best effort and must never expose provider request material.
    } finally {
      _finalizeChannelState();
    }
  }

  void _cancelJoinWait() {
    final Completer<void>? cancellation = _joinCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    final Completer<void>? completion = _joinCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.completeError(const _RtcOperationCancelled());
    }
  }

  void _cancelInitializeWait() {
    final Completer<void>? cancellation = _initializeCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  void _cancelRenewalWait() {
    _renewalInFlight = null;
    final Completer<void>? cancellation = _renewCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    final Completer<void>? completion = _renewCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }

  bool _isJoinGenerationActive(
    int lifecycleGeneration,
    int callbackGeneration,
  ) =>
      !_disposed &&
      !_disposing &&
      _joining &&
      _joinLogicalGeneration == lifecycleGeneration &&
      lifecycleGeneration == _lifecycleGeneration &&
      callbackGeneration == _callbackGeneration;

  bool _matchesEngine(
    RtcEngine engine,
    int engineGeneration,
    int callbackGeneration, {
    bool allowDisposing = false,
  }) =>
      !_disposed &&
      (allowDisposing || !_disposing) &&
      identical(_engine, engine) &&
      engineGeneration == _engineGeneration &&
      callbackGeneration == _callbackGeneration;

  bool _matchesConnection(
    RtcEngine engine,
    int engineGeneration,
    int callbackGeneration,
    RtcConnection connection, {
    bool allowDisposing = false,
  }) {
    if (!_matchesEngine(
      engine,
      engineGeneration,
      callbackGeneration,
      allowDisposing: allowDisposing,
    )) {
      return false;
    }
    final int? callbackSessionGeneration = _callbackSessionGeneration;
    if (callbackSessionGeneration != null) {
      final bool activeSession =
          _activeSessionGeneration == callbackSessionGeneration ||
          _joinLogicalGeneration == callbackSessionGeneration;
      final bool leavingSession =
          allowDisposing &&
          _leavingSessionGeneration == callbackSessionGeneration;
      if (!activeSession && !leavingSession) {
        return false;
      }
    }
    final String? expectedChannel =
        _joiningCredentials?.channelId ??
        _activeChannelId ??
        _credentials?.channelId;
    final int? expectedUid =
        _joiningCredentials?.uid ?? _activeUid ?? _credentials?.uid;
    if (connection.channelId != null &&
        expectedChannel != null &&
        connection.channelId != expectedChannel) {
      return false;
    }
    if (connection.localUid != null &&
        expectedUid != null &&
        connection.localUid != expectedUid) {
      return false;
    }
    return true;
  }

  bool _isExpectedLeaveCallback(
    int engineGeneration,
    int callbackGeneration,
    RtcConnection connection,
  ) {
    if (_leaveCompletion == null ||
        _leavingSessionGeneration == null ||
        _leavingEngineGeneration != engineGeneration ||
        _leavingCallbackGeneration != callbackGeneration) {
      return false;
    }
    if (connection.channelId != null &&
        _leavingChannelId != null &&
        connection.channelId != _leavingChannelId) {
      return false;
    }
    if (connection.localUid != null &&
        _leavingUid != null &&
        connection.localUid != _leavingUid) {
      return false;
    }
    return true;
  }

  void _completeLeaveWait() {
    final Completer<void>? completion = _leaveCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }

  void _finalizeChannelState() {
    _channelOperationPending = false;
    _activeSessionGeneration = null;
    _activeChannelId = null;
    _activeUid = null;
    _leavingSessionGeneration = null;
    _leavingEngineGeneration = null;
    _leavingCallbackGeneration = null;
    _leavingChannelId = null;
    _leavingUid = null;
    final Completer<void>? completion = _leaveCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
    _leaveCompletion = null;
  }

  Future<void> _rollbackAudioPublication(
    RtcEngine engine, {
    required ClientRoleType role,
    required bool enabled,
    required bool mediaOptionsUpdated,
  }) async {
    if (!mediaOptionsUpdated) {
      return;
    }
    if (enabled) {
      try {
        await engine.updateChannelMediaOptions(
          ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
            clientRoleType: role,
            publishMicrophoneTrack: false,
            autoSubscribeAudio: true,
            autoSubscribeVideo: false,
          ),
        );
      } catch (_) {
        // Keep the safe state below even if the provider is already tearing
        // down the channel.
      }
      try {
        await engine.muteLocalAudioStream(true);
      } catch (_) {
        // Best effort; publication was disabled first.
      }
      _localAudioEnabled = false;
    } else {
      // The provider has accepted publish=false, so local state is safely
      // muted even when its separate mute call fails.
      _localAudioEnabled = false;
    }
  }

  void _scheduleRenewal() {
    if (_disposed || _disposing || !_joined) {
      return;
    }
    final Future<void> request = renewToken();
    unawaited(
      request.catchError((Object error, StackTrace stack) {
        if (!_disposed) {
          final RtcAdapterException safeError = error is RtcAdapterException
              ? error
              : const RtcAdapterException(
                  failure: RtcAdapterFailure.renewToken,
                  message: 'RTC 凭证刷新失败',
                );
          _emit(
            RtcAdapterEvent(
              type: RtcAdapterEventType.error,
              providerCode: safeError.providerCode,
              message: safeError.message,
            ),
          );
        }
        return;
      }),
    );
  }

  Future<void> _releaseEngine(RtcEngine engine) async {
    try {
      final RtcEngineEventHandler? handler = _eventHandler;
      if (_handlerRegistered && handler != null) {
        engine.unregisterEventHandler(handler);
      }
    } catch (_) {
      // Releasing the engine remains best effort if an older SDK build has
      // already detached its event handler.
    }
    try {
      await engine.release();
    } on Object {
      // The native engine is already unusable after release; do not leak an
      // SDK-specific error into a room leave/dispose path.
    }
    _eventHandler = null;
    _handlerRegistered = false;
    _callbackSessionGeneration = null;
  }

  RtcEngine _requireEngine() {
    if (_disposed || _disposing) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.disposed,
        message: 'RTC 适配器已释放',
      );
    }
    final RtcEngine? engine = _engine;
    if (!_initialized || engine == null) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.notInitialized,
        message: 'RTC 适配器尚未初始化',
      );
    }
    return engine;
  }

  void _ensureNotDisposed() {
    if (_disposed || _disposing) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.disposed,
        message: 'RTC 适配器已释放',
      );
    }
  }

  void _validateCredentials(RtcCredentials credentials) {
    final String provider = credentials.provider.trim().toLowerCase();
    final DateTime now = _now().toUtc();
    if (provider != 'agora' ||
        credentials.appId.trim().isEmpty ||
        credentials.token.trim().isEmpty ||
        credentials.channelId.trim().isEmpty ||
        credentials.uid <= 0 ||
        credentials.uid > rtcUidMax ||
        credentials.role.trim().isEmpty ||
        (credentials.ttlSeconds != null && credentials.ttlSeconds! <= 0) ||
        (credentials.expiresAt == null &&
            (credentials.ttlSeconds == null || credentials.ttlSeconds! <= 0)) ||
        (credentials.expiresAt != null &&
            !credentials.expiresAt!.toUtc().isAfter(now))) {
      throw const RtcAdapterException(
        failure: RtcAdapterFailure.invalidCredentials,
        message: 'RTC 凭证不完整或已过期',
      );
    }
    _roleFor(credentials.role);
  }

  static ClientRoleType _roleFor(String role) {
    final String normalized = _RtcSessionIdentity.normalizedRole(role);
    return switch (normalized) {
      'broadcaster' => ClientRoleType.clientRoleBroadcaster,
      'audience' => ClientRoleType.clientRoleAudience,
      _ => throw const RtcAdapterException(
        failure: RtcAdapterFailure.invalidCredentials,
        message: 'RTC 凭证 role 无法识别',
      ),
    };
  }

  bool _sameSessionIdentity(RtcCredentials left, RtcCredentials right) =>
      _RtcSessionIdentity.fromCredentials(left) ==
      _RtcSessionIdentity.fromCredentials(right);

  RtcAdapterException _sessionIdentityConflict(RtcAdapterFailure failure) =>
      RtcAdapterException(
        failure: failure,
        message: 'RTC 会话身份不一致，请使用 reconnect',
      );

  static RtcAdapterException _providerException(
    RtcAdapterFailure failure,
    int providerCode, {
    required String fallback,
  }) => RtcAdapterException(
    failure: failure,
    providerCode: providerCode,
    message: fallback,
  );

  void _emit(RtcAdapterEvent event) {
    final StreamController<RtcAdapterEvent>? controller = _events;
    if (!_disposed &&
        !_disposing &&
        controller != null &&
        !controller.isClosed) {
      controller.add(event);
    }
  }

  void _emitJoinedEvent() {
    if ((!_joined && !_joining) || _joinEventReported) {
      return;
    }
    _joinEventReported = true;
    _emit(const RtcAdapterEvent(type: RtcAdapterEventType.joined));
  }
}

class _RtcOperationCancelled implements Exception {
  const _RtcOperationCancelled();
}

/// The identity that owns a native RTC channel.
///
/// Token material and expiry are deliberately absent: a token refresh must be
/// allowed to preserve the same session, while a different channel, uid,
/// app, provider, or effective role must never be silently coalesced.
class _RtcSessionIdentity {
  const _RtcSessionIdentity({
    required this.provider,
    required this.appId,
    required this.channelId,
    required this.uid,
    required this.role,
  });

  factory _RtcSessionIdentity.fromCredentials(RtcCredentials credentials) =>
      _RtcSessionIdentity(
        provider: credentials.provider.trim().toLowerCase(),
        appId: credentials.appId.trim(),
        channelId: credentials.channelId.trim(),
        uid: credentials.uid,
        role: normalizedRole(credentials.role),
      );

  final String provider;
  final String appId;
  final String channelId;
  final int uid;
  final String role;

  static String normalizedRole(String role) {
    final String normalized = role.trim().toLowerCase();
    return switch (normalized) {
      'broadcaster' ||
      'publisher' ||
      'host' ||
      'speaker' ||
      'anchor' => 'broadcaster',
      'audience' || 'listener' || 'guest' || 'subscriber' => 'audience',
      _ => normalized,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is _RtcSessionIdentity &&
      provider == other.provider &&
      appId == other.appId &&
      channelId == other.channelId &&
      uid == other.uid &&
      role == other.role;

  @override
  int get hashCode => Object.hash(provider, appId, channelId, uid, role);
}

class MockRtcAdapter implements RtcAdapter {
  bool _joined = false;
  bool _audioEnabled = false;

  bool get joined => _joined;
  bool get audioEnabled => _audioEnabled;

  @override
  Future<void> join(RtcCredentials credentials) {
    _joined = true;
    return Future<void>.value();
  }

  @override
  Future<void> reconnect(RtcCredentials credentials) {
    _joined = true;
    return Future<void>.value();
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) {
    if (_joined) {
      _audioEnabled = enabled;
    }
    return Future<void>.value();
  }

  @override
  Future<void> leave() {
    _audioEnabled = false;
    _joined = false;
    return Future<void>.value();
  }
}

/// Transport used only for an authoritative HTTP room snapshot.
///
/// It lets the room controller display the read-only page without pretending
/// that an RTC engine joined. Audio enablement remains fail-closed.
class SnapshotOnlyRtcAdapter implements RtcAdapter {
  const SnapshotOnlyRtcAdapter();

  @override
  Future<void> join(RtcCredentials credentials) async {}

  @override
  Future<void> reconnect(RtcCredentials credentials) async {}

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    if (enabled) {
      throw StateError('VENDOR_BLOCKED：RTC 适配器尚未配置');
    }
  }

  @override
  Future<void> leave() async {}
}

class UnavailableRtcAdapter implements RtcAdapter {
  const UnavailableRtcAdapter();

  Never _notConfigured() => throw StateError('RTC 适配器尚未配置');

  @override
  Future<void> join(RtcCredentials credentials) async => _notConfigured();

  @override
  Future<void> reconnect(RtcCredentials credentials) async => _notConfigured();

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async => _notConfigured();

  @override
  Future<void> leave() async {}
}
