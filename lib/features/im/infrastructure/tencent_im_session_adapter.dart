import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimSDKListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:voice_social_app/features/im/domain/im_session_adapter.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/im/domain/im_room_events.dart';
import 'package:voice_social_app/features/im/domain/im_session_events.dart';

/// Small seam around the official SDK so lifecycle tests never need to call a
/// native Tencent service.  Production uses [OfficialTencentImSdkClient].
abstract interface class TencentImSdkClient {
  Future<bool> initSdk({required int sdkAppId});

  Future<int> login({required String userId, required String userSig});

  Future<int> logout();

  Future<int> uninitSdk();
}

/// Optional live-group capability of the official Tencent client.
///
/// This is deliberately a separate seam from [TencentImSdkClient]. Existing
/// lifecycle fakes (and providers such as Alipay that share the dependency
/// graph) do not have to grow group methods just because AVChatRoom support is
/// enabled in another integration. A caller must feature-detect this
/// capability; absence is a safe HTTP-only mode.
abstract interface class TencentImSdkGroupClient {
  Future<int> joinGroup({required String groupId, required String groupType});

  Future<int> quitGroup({required String groupId});
}

/// Optional event source implemented by the official bridge and event-aware
/// fakes.  It is separate from [TencentImSdkClient] so existing lifecycle
/// fakes remain source-compatible and never need to model native callbacks.
abstract interface class TencentImSdkEventSource {
  Stream<TencentImSdkEvent> get events;
}

enum TencentImSdkEventKind {
  userSigExpired,
  networkOffline,
  networkOnline,
  customElement,
}

class TencentImSdkEvent {
  const TencentImSdkEvent({
    required this.kind,
    this.customData,
    this.trustedFirstParty = false,
    this.senderUserId,
    this.groupId,
    this.sessionId,
    this.isSelf,
  });

  const TencentImSdkEvent.userSigExpired()
    : this(kind: TencentImSdkEventKind.userSigExpired);

  const TencentImSdkEvent.networkOffline()
    : this(kind: TencentImSdkEventKind.networkOffline);

  const TencentImSdkEvent.networkOnline()
    : this(kind: TencentImSdkEventKind.networkOnline);

  const TencentImSdkEvent.customElement({
    required String data,
    required bool trustedFirstParty,
    String? senderUserId,
    String? groupId,
    String? sessionId,
    bool? isSelf,
  }) : this(
         kind: TencentImSdkEventKind.customElement,
         customData: data,
         trustedFirstParty: trustedFirstParty,
         senderUserId: senderUserId,
         groupId: groupId,
         sessionId: sessionId,
         isSelf: isSelf,
       );

  final TencentImSdkEventKind kind;

  /// Transient native custom data.  The adapter immediately parses it and
  /// never exposes or logs this value.
  final String? customData;
  final bool trustedFirstParty;

  /// Transient native metadata used only at the adapter trust boundary.
  /// These fields never reach the provider-neutral event or UI.
  final String? senderUserId;
  final String? groupId;

  /// Optional transient backend/session fence supplied by an event-aware
  /// bridge. Official Tencent message callbacks do not currently expose this
  /// field; the room coordinator still fences by its active generation and
  /// lease. It is never parsed from the custom payload.
  final String? sessionId;
  final bool? isSelf;
}

typedef TencentImHintTrustEvaluator =
    bool Function({
      required String? senderUserId,
      required String? groupId,
      required bool? isSelf,
    });

/// Adapter for the official no-UI `tencent_cloud_chat_sdk` manager.
///
/// No UI wrapper import is used.  `showImLog` is disabled and the SDK is
/// initialized with error-level logging; application diagnostics are limited
/// to fixed lifecycle markers emitted by [ImLifecycleLogger].
class OfficialTencentImSdkClient
    implements
        TencentImSdkClient,
        TencentImSdkEventSource,
        TencentImSdkGroupClient {
  OfficialTencentImSdkClient({
    V2TIMManager? manager,
    TencentImHintTrustEvaluator? trustedHintEvaluator,
  }) : _manager = manager ?? V2TIMManager(),
       _trustedHintEvaluator = trustedHintEvaluator;

  final V2TIMManager _manager;
  final TencentImHintTrustEvaluator? _trustedHintEvaluator;
  final StreamController<TencentImSdkEvent> _eventController =
      StreamController<TencentImSdkEvent>.broadcast(sync: true);

  late final V2TimSDKListener _sdkListener = V2TimSDKListener(
    onConnecting: _emitNetworkOffline,
    onConnectSuccess: _emitNetworkOnline,
    onConnectFailed: (int _, String __) => _emitNetworkOffline(),
    onKickedOffline: _emitNetworkOffline,
    onUserSigExpired: _emitUserSigExpired,
  );

  late final V2TimAdvancedMsgListener _advancedMessageListener =
      V2TimAdvancedMsgListener(onRecvNewMessage: _onMessage);

  @override
  Stream<TencentImSdkEvent> get events => _eventController.stream;

  @override
  Future<bool> initSdk({required int sdkAppId}) async {
    final V2TimValueCallback<bool> result = await _manager.initSDK(
      sdkAppID: sdkAppId,
      loglevel: LogLevelEnum.V2TIM_LOG_ERROR,
      showImLog: false,
      listener: _sdkListener,
    );
    final bool initialized = result.code == 0 && result.data == true;
    if (initialized) {
      await _manager.v2TIMMessageManager.addAdvancedMsgListener(
        listener: _advancedMessageListener,
      );
    }
    return initialized;
  }

  @override
  Future<int> login({required String userId, required String userSig}) async {
    final V2TimCallback result = await _manager.login(
      userID: userId,
      userSig: userSig,
    );
    return result.code;
  }

  @override
  Future<int> logout() async {
    final V2TimCallback result = await _manager.logout();
    return result.code;
  }

  @override
  Future<int> uninitSdk() async {
    Object? firstError;
    try {
      await _manager.v2TIMMessageManager.removeAdvancedMsgListener(
        listener: _advancedMessageListener,
      );
    } on Object catch (error) {
      firstError = error;
    }
    try {
      final V2TimCallback result = await _manager.unInitSDK();
      if (firstError != null) {
        throw firstError;
      }
      return result.code;
    } on Object {
      if (firstError != null) {
        throw firstError;
      }
      rethrow;
    }
  }

  @override
  Future<int> joinGroup({
    required String groupId,
    required String groupType,
  }) async {
    final V2TimCallback result = await _manager.joinGroup(
      groupID: groupId,
      message: '',
      // The native bridge derives the type from the server-created group;
      // passing it also keeps the web bridge explicit for AVChatRoom.
      groupType: groupType,
    );
    return result.code;
  }

  @override
  Future<int> quitGroup({required String groupId}) async {
    final V2TimCallback result = await _manager.quitGroup(groupID: groupId);
    return result.code;
  }

  Future<void> dispose() async {
    if (!_eventController.isClosed) {
      await _eventController.close();
    }
  }

  void _emitUserSigExpired() {
    _emit(const TencentImSdkEvent.userSigExpired());
  }

  void _emitNetworkOffline() {
    _emit(const TencentImSdkEvent.networkOffline());
  }

  void _emitNetworkOnline() {
    _emit(const TencentImSdkEvent.networkOnline());
  }

  void _onMessage(V2TimMessage message) {
    final V2TimCustomElem? customElement = message.customElem;
    final String? customData = customElement?.data;
    if (customData == null || customData.isEmpty) {
      return;
    }
    final String? groupId = message.groupID;
    final TencentImHintTrustEvaluator? evaluator = _trustedHintEvaluator;
    final bool trusted =
        evaluator?.call(
          senderUserId: message.sender,
          groupId: groupId,
          isSelf: message.isSelf,
        ) ??
        false;
    _emit(
      TencentImSdkEvent.customElement(
        data: customData,
        trustedFirstParty: trusted,
        senderUserId: message.sender,
        groupId: groupId,
        isSelf: message.isSelf,
      ),
    );
  }

  void _emit(TencentImSdkEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }
}

/// Provider-neutral Tencent IM lifecycle implementation.
class TencentImSessionAdapter
    implements ImSessionAdapter, ImRoomGroupCapability {
  TencentImSessionAdapter({
    TencentImSdkClient? sdkClient,
    // `sdk` is a descriptive compatibility alias used by lightweight tests.
    TencentImSdkClient? sdk,
    DateTime Function()? now,
    this.operationTimeout = const Duration(seconds: 15),
    ImLifecycleLogger? logger,
  }) : assert(operationTimeout > Duration.zero),
       _sdkClient = sdkClient ?? sdk ?? OfficialTencentImSdkClient(),
       _now = now ?? DateTime.now,
       _logger = logger ?? _defaultLogger {
    final TencentImSdkEventSource? source =
        _sdkClient is TencentImSdkEventSource
        ? _sdkClient as TencentImSdkEventSource
        : null;
    if (source != null) {
      _sdkEventSubscription = source.events.listen(_handleSdkEvent);
    }
  }

  final TencentImSdkClient _sdkClient;
  final DateTime Function() _now;
  final Duration operationTimeout;
  final ImLifecycleLogger _logger;
  final StreamController<ImSessionState> _stateController =
      StreamController<ImSessionState>.broadcast(sync: true);
  final StreamController<ImSessionEvent> _eventController =
      StreamController<ImSessionEvent>.broadcast(sync: true);
  final StreamController<ImRoomRefreshEvent> _roomEventController =
      StreamController<ImRoomRefreshEvent>.broadcast(sync: true);
  StreamSubscription<TencentImSdkEvent>? _sdkEventSubscription;

  Future<void> _serialTail = Future<void>.value();
  Future<void>? _initializeFlight;
  Future<void>? _loginFlight;
  Future<void>? _renewFlight;
  Future<void>? _logoutFlight;
  Future<void>? _uninitializeFlight;
  String? _loginFlightUserId;
  String? _renewFlightUserId;
  ImSessionState _state = const ImSessionState.idle();
  ImSessionCredentials? _credentials;
  int? _sdkAppId;
  bool _initialized = false;
  bool _loggedIn = false;
  bool _disposed = false;
  String? _activeGroupId;

  @override
  ImSessionStatus get status => state.status;

  @override
  ImSessionState get state {
    final ImSessionCredentials? credentials = _credentials;
    if (_state.status == ImSessionStatus.ready &&
        (credentials == null || credentials.isExpired(_now()))) {
      return ImSessionState(
        status: ImSessionStatus.expired,
        activeUserId: credentials?.userId,
        expiresAt: credentials?.expiresAt,
        failure: ImSessionFailure.invalidCredentials,
      );
    }
    return _state;
  }

  @override
  Stream<ImSessionState> get states => _stateController.stream;

  @override
  Stream<ImSessionEvent> get events => _eventController.stream;

  @override
  ImSessionCredentials? get credentials => _credentials;

  @override
  String? get activeUserId => _credentials?.userId;

  @override
  bool get supportsAvChatRoom => _sdkClient is TencentImSdkGroupClient;

  @override
  Stream<ImRoomRefreshEvent> get roomEvents => _roomEventController.stream;

  /// Checks the complete first-party trust boundary for a refresh hint.
  ///
  /// The sender is compared to the public system account delivered in the
  /// active server credential.  Current-user/self-authored messages are never
  /// trusted as refresh commands, and a group message is outside the C2C
  /// contract.  The provider callback supplies only transient metadata; the
  /// raw custom element is parsed separately after this check.
  bool isTrustedHintSender({
    required String? senderUserId,
    required String? groupId,
    required bool? isSelf,
  }) {
    final ImSessionCredentials? credentials = _credentials;
    return credentials != null &&
        groupId == null &&
        isSelf == false &&
        senderUserId != null &&
        senderUserId == credentials.systemAccount;
  }

  /// Trust evaluator used by the official SDK event bridge for both C2C and
  /// AVChatRoom messages. Keeping the C2C method above strict and public makes
  /// it difficult for a caller to accidentally authorize a group message in a
  /// private conversation.
  bool isTrustedProviderHint({
    required String? senderUserId,
    required String? groupId,
    required bool? isSelf,
  }) {
    return isTrustedHintSender(
          senderUserId: senderUserId,
          groupId: groupId,
          isSelf: isSelf,
        ) ||
        isTrustedRoomHintSender(
          senderUserId: senderUserId,
          groupId: groupId,
          isSelf: isSelf,
        );
  }

  /// Checks the AVChatRoom trust boundary against the group currently joined
  /// by this adapter. It deliberately uses the same active credential's
  /// public [ImSessionCredentials.systemAccount] as C2C; no sender supplied by
  /// the custom payload is trusted.
  bool isTrustedRoomHintSender({
    required String? senderUserId,
    required String? groupId,
    required bool? isSelf,
  }) {
    final ImSessionCredentials? credentials = _credentials;
    final String? activeGroupId = _activeGroupId;
    final String? normalizedGroupId = groupId?.trim();
    return credentials != null &&
        activeGroupId != null &&
        normalizedGroupId != null &&
        normalizedGroupId.isNotEmpty &&
        normalizedGroupId == activeGroupId &&
        isSelf == false &&
        senderUserId != null &&
        senderUserId == credentials.systemAccount;
  }

  @override
  bool get isReady => state.isReady && _loggedIn;

  @override
  Future<void> initialize(ImSessionCredentials credentials) {
    _ensureNotDisposed();
    _validateCredentials(credentials);
    final Future<void>? active = _initializeFlight;
    if (active != null) {
      return active;
    }
    final Future<void> operation = _serialize(
      () => _initializeInternal(credentials),
    );
    _initializeFlight = operation;
    _clearFlightWhenDone(operation, () {
      if (identical(_initializeFlight, operation)) {
        _initializeFlight = null;
      }
    });
    return operation;
  }

  @override
  Future<void> login(ImSessionCredentials credentials) {
    _ensureNotDisposed();
    _validateCredentials(credentials);
    final Future<void>? active = _loginFlight;
    if (active != null && _loginFlightUserId == credentials.userId) {
      return active;
    }
    final Future<void> operation = _serialize(
      () => _loginInternal(credentials),
    );
    _loginFlight = operation;
    _loginFlightUserId = credentials.userId;
    _clearFlightWhenDone(operation, () {
      if (identical(_loginFlight, operation)) {
        _loginFlight = null;
        _loginFlightUserId = null;
      }
    });
    return operation;
  }

  @override
  Future<void> renew(ImSessionCredentials credentials) {
    _ensureNotDisposed();
    _validateCredentials(credentials);
    final Future<void>? active = _renewFlight;
    if (active != null && _renewFlightUserId == credentials.userId) {
      return active;
    }
    final Future<void> operation = _serialize(
      () => _renewInternal(credentials),
    );
    _renewFlight = operation;
    _renewFlightUserId = credentials.userId;
    _clearFlightWhenDone(operation, () {
      if (identical(_renewFlight, operation)) {
        _renewFlight = null;
        _renewFlightUserId = null;
      }
    });
    return operation;
  }

  @override
  Future<void> logout() {
    _ensureNotDisposed();
    final Future<void>? active = _logoutFlight;
    if (active != null) {
      return active;
    }
    final Future<void> operation = _serialize(_logoutInternal);
    _logoutFlight = operation;
    _clearFlightWhenDone(operation, () {
      if (identical(_logoutFlight, operation)) {
        _logoutFlight = null;
      }
    });
    return operation;
  }

  @override
  Future<void> uninitialize() {
    _ensureNotDisposed();
    final Future<void>? active = _uninitializeFlight;
    if (active != null) {
      return active;
    }
    final Future<void> operation = _serialize(_uninitializeInternal);
    _uninitializeFlight = operation;
    _clearFlightWhenDone(operation, () {
      if (identical(_uninitializeFlight, operation)) {
        _uninitializeFlight = null;
      }
    });
    return operation;
  }

  /// Joins only a server-authorized group. The room coordinator is expected
  /// to validate the HTTP lease and READY status before calling this method;
  /// this method still fail-closes when the account is not ready, the group
  /// capability is absent, or the identifier is malformed.
  @override
  Future<bool> joinGroup({required String groupId, required String groupType}) {
    _ensureNotDisposed();
    final String normalizedGroupId = groupId.trim();
    final String normalizedGroupType = groupType.trim();
    if (!supportsAvChatRoom ||
        !isReady ||
        !_isSafeAvChatRoomGroupId(normalizedGroupId) ||
        normalizedGroupType != 'AVChatRoom') {
      return Future<bool>.value(false);
    }
    if (_activeGroupId == normalizedGroupId) {
      return Future<bool>.value(true);
    }
    final TencentImSdkGroupClient groupClient =
        _sdkClient as TencentImSdkGroupClient;
    return _serialize<bool>(() async {
      if (!isReady || _disposed) {
        return false;
      }
      final int code = await groupClient
          .joinGroup(groupId: normalizedGroupId, groupType: normalizedGroupType)
          .timeout(operationTimeout);
      // Tencent's official enum defines 10010 as GROUP_NOT_FOUND. The only
      // accepted idempotent join result is 10013 (already a member).
      if (code != 0 && code != 10013) {
        return false;
      }
      _activeGroupId = normalizedGroupId;
      return true;
    });
  }

  /// Leaves a currently joined AVChatRoom with a bounded provider call. A
  /// The native result is accepted only when it is an explicit success (0).
  /// The local group fence is cleared in all paths so a late callback cannot
  /// refresh a previous room.
  @override
  Future<bool> quitGroup({required String groupId}) {
    _ensureNotDisposed();
    final String normalizedGroupId = groupId.trim();
    if (!supportsAvChatRoom || !_isSafeAvChatRoomGroupId(normalizedGroupId)) {
      if (_activeGroupId == normalizedGroupId) {
        _activeGroupId = null;
      }
      return Future<bool>.value(false);
    }
    final TencentImSdkGroupClient groupClient =
        _sdkClient as TencentImSdkGroupClient;
    return _serialize<bool>(() async {
      if (_activeGroupId != normalizedGroupId) {
        return true;
      }
      try {
        final int code = await groupClient
            .quitGroup(groupId: normalizedGroupId)
            .timeout(operationTimeout);
        return code == 0;
      } on Object {
        return false;
      } finally {
        if (_activeGroupId == normalizedGroupId) {
          _activeGroupId = null;
        }
      }
    });
  }

  /// Releases the in-memory credential and closes the state stream.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    try {
      await uninitialize();
    } finally {
      _disposed = true;
      _clearCredentialState();
      await _sdkEventSubscription?.cancel();
      _sdkEventSubscription = null;
      await _stateController.close();
      await _eventController.close();
      await _roomEventController.close();
    }
  }

  void _handleSdkEvent(TencentImSdkEvent event) {
    if (_disposed) {
      return;
    }
    switch (event.kind) {
      case TencentImSdkEventKind.userSigExpired:
        if (_credentials != null) {
          _setState(
            ImSessionState(
              status: ImSessionStatus.expired,
              activeUserId: _credentials?.userId,
              expiresAt: _credentials?.expiresAt,
              failure: ImSessionFailure.invalidCredentials,
            ),
          );
          _logger(ImLifecycleMarker.expired);
        }
        _emitEvent(const ImSessionEvent.userSigExpired());
        break;
      case TencentImSdkEventKind.networkOffline:
        if (_loggedIn) {
          _setState(
            ImSessionState(
              status: ImSessionStatus.offline,
              activeUserId: _credentials?.userId,
              expiresAt: _credentials?.expiresAt,
            ),
          );
        }
        _emitEvent(const ImSessionEvent.networkOffline());
        break;
      case TencentImSdkEventKind.networkOnline:
        if (_loggedIn && _credentials != null) {
          _setState(
            ImSessionState(
              status: ImSessionStatus.reconnecting,
              activeUserId: _credentials?.userId,
              expiresAt: _credentials?.expiresAt,
            ),
          );
        }
        _emitEvent(const ImSessionEvent.networkOnline());
        break;
      case TencentImSdkEventKind.customElement:
        final String? customData = event.customData;
        if (customData == null) {
          return;
        }
        final String? normalizedGroupId = event.groupId?.trim();
        if (normalizedGroupId != null && normalizedGroupId.isNotEmpty) {
          final ImRefreshHint? roomHint = ImRefreshHint.tryParse(
            customData,
            trustedSource:
                event.trustedFirstParty &&
                isTrustedRoomHintSender(
                  senderUserId: event.senderUserId,
                  groupId: normalizedGroupId,
                  isSelf: event.isSelf,
                ),
          );
          if (roomHint != null && !_roomEventController.isClosed) {
            _roomEventController.add(
              ImRoomRefreshEvent(
                groupId: normalizedGroupId,
                sessionId: event.sessionId,
                hint: roomHint,
              ),
            );
          }
          // Group custom data never becomes a private refresh event.
          return;
        }
        final ImRefreshHint? hint = ImRefreshHint.tryParse(
          customData,
          trustedSource:
              event.trustedFirstParty &&
              isTrustedHintSender(
                senderUserId: event.senderUserId,
                groupId: event.groupId,
                isSelf: event.isSelf,
              ),
        );
        if (hint != null) {
          _emitEvent(ImSessionEvent.refresh(hint));
        }
        break;
    }
  }

  void _emitEvent(ImSessionEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  Future<void> _initializeInternal(ImSessionCredentials credentials) async {
    if (_initialized && _sdkAppId == credentials.sdkAppId) {
      return;
    }
    if (_initialized || _loggedIn) {
      await _shutdownNative();
    }
    _setState(
      ImSessionState(
        status: ImSessionStatus.initializing,
        activeUserId: _credentials?.userId,
      ),
    );
    _logger(ImLifecycleMarker.initializeStarted);
    try {
      final bool initialized = await _sdkClient
          .initSdk(sdkAppId: credentials.sdkAppId)
          .timeout(operationTimeout);
      if (!initialized) {
        throw const _TencentImSdkFailure(
          operation: ImSessionFailure.initialize,
        );
      }
      _initialized = true;
      _sdkAppId = credentials.sdkAppId;
      _setState(const ImSessionState.idle());
      _logger(ImLifecycleMarker.initializeSucceeded);
    } catch (error) {
      _initialized = false;
      _sdkAppId = null;
      _clearCredentialState();
      _setState(const ImSessionState(status: ImSessionStatus.error));
      _logger(ImLifecycleMarker.initializeFailed);
      throw _asSessionException(error, ImSessionFailure.initialize);
    }
  }

  Future<void> _loginInternal(ImSessionCredentials credentials) async {
    if (_loggedIn &&
        _sdkAppId == credentials.sdkAppId &&
        _credentials?.userId == credentials.userId &&
        _credentials?.userSig == credentials.userSig &&
        _credentials?.expiresAt == credentials.expiresAt &&
        _credentials?.ttlSeconds == credentials.ttlSeconds &&
        _credentials?.systemAccount == credentials.systemAccount &&
        _state.status == ImSessionStatus.ready &&
        !(_credentials?.isExpired(_now()) ?? true)) {
      return;
    }
    if (_loggedIn) {
      await _logoutNative();
    }
    await _initializeInternal(credentials);
    await _loginNative(credentials, operation: ImSessionFailure.login);
  }

  Future<void> _renewInternal(ImSessionCredentials credentials) async {
    final ImSessionCredentials? active = _credentials;
    if (_loggedIn &&
        active != null &&
        (active.userId != credentials.userId ||
            active.sdkAppId != credentials.sdkAppId)) {
      _setState(
        const ImSessionState(
          status: ImSessionStatus.error,
          failure: ImSessionFailure.identityMismatch,
        ),
      );
      throw const ImSessionException(
        failure: ImSessionFailure.identityMismatch,
        message: 'IM 会话用户不匹配',
      );
    }
    if (_loggedIn &&
        active != null &&
        active.userSig == credentials.userSig &&
        active.expiresAt == credentials.expiresAt &&
        active.ttlSeconds == credentials.ttlSeconds &&
        active.systemAccount == credentials.systemAccount &&
        _state.status == ImSessionStatus.ready &&
        !active.isExpired(_now())) {
      return;
    }
    _setState(
      ImSessionState(
        status: ImSessionStatus.renewing,
        activeUserId: active?.userId,
        expiresAt: credentials.expiresAt,
      ),
    );
    _logger(ImLifecycleMarker.renewStarted);
    try {
      if (_loggedIn) {
        await _logoutNative();
      }
      await _initializeInternal(credentials);
      await _loginNative(credentials, operation: ImSessionFailure.renew);
      _logger(ImLifecycleMarker.renewSucceeded);
    } catch (error) {
      _clearCredentialState();
      _setState(
        const ImSessionState(
          status: ImSessionStatus.error,
          failure: ImSessionFailure.renew,
        ),
      );
      _logger(ImLifecycleMarker.renewFailed);
      if (error is ImSessionException &&
          error.failure == ImSessionFailure.identityMismatch) {
        rethrow;
      }
      throw _asSessionException(error, ImSessionFailure.renew);
    }
  }

  Future<void> _loginNative(
    ImSessionCredentials credentials, {
    required ImSessionFailure operation,
  }) async {
    _setState(
      ImSessionState(
        status: ImSessionStatus.loggingIn,
        activeUserId: credentials.userId,
        expiresAt: credentials.expiresAt,
      ),
    );
    _logger(ImLifecycleMarker.loginStarted);
    try {
      final int code = await _sdkClient
          .login(userId: credentials.userId, userSig: credentials.userSig)
          .timeout(operationTimeout);
      if (code != 0) {
        throw _TencentImSdkFailure(operation: operation, providerCode: code);
      }
      _loggedIn = true;
      _credentials = credentials;
      _setState(
        ImSessionState(
          status: ImSessionStatus.ready,
          activeUserId: credentials.userId,
          expiresAt: credentials.expiresAt,
        ),
      );
      _logger(ImLifecycleMarker.loginSucceeded);
    } catch (error) {
      _loggedIn = false;
      _clearCredentialState();
      _setState(
        ImSessionState(status: ImSessionStatus.error, failure: operation),
      );
      _logger(ImLifecycleMarker.loginFailed);
      throw _asSessionException(error, operation);
    }
  }

  Future<void> _logoutInternal() async {
    _setState(
      ImSessionState(
        status: ImSessionStatus.loggingOut,
        activeUserId: _credentials?.userId,
      ),
    );
    _logger(ImLifecycleMarker.logoutStarted);
    try {
      await _quitActiveGroup();
      if (_loggedIn) {
        await _logoutNative();
      }
      _clearCredentialState();
      _setState(const ImSessionState.idle());
      _logger(ImLifecycleMarker.logoutSucceeded);
    } catch (error) {
      // Local memory is cleared even when the native call fails.  The caller
      // may uninitialize and retry, but stale UserSig is never retained.
      _loggedIn = false;
      _clearCredentialState();
      _setState(
        const ImSessionState(
          status: ImSessionStatus.error,
          failure: ImSessionFailure.logout,
        ),
      );
      _logger(ImLifecycleMarker.logoutFailed);
      throw _asSessionException(error, ImSessionFailure.logout);
    }
  }

  Future<void> _uninitializeInternal() async {
    _setState(
      ImSessionState(
        status: ImSessionStatus.loggingOut,
        activeUserId: _credentials?.userId,
      ),
    );
    _logger(ImLifecycleMarker.uninitializeStarted);
    Object? firstError;
    try {
      await _quitActiveGroup();
    } on Object catch (error) {
      firstError = error;
    }
    if (_loggedIn) {
      try {
        await _logoutNative();
      } catch (error) {
        firstError = error;
      }
    }
    if (_initialized) {
      try {
        final int code = await _sdkClient.uninitSdk().timeout(operationTimeout);
        if (code != 0 && firstError == null) {
          firstError = _TencentImSdkFailure(
            operation: ImSessionFailure.uninitialize,
            providerCode: code,
          );
        }
      } catch (error) {
        firstError ??= error;
      }
    }
    _initialized = false;
    _loggedIn = false;
    _sdkAppId = null;
    _clearCredentialState();
    if (firstError != null) {
      _setState(
        const ImSessionState(
          status: ImSessionStatus.error,
          failure: ImSessionFailure.uninitialize,
        ),
      );
      _logger(ImLifecycleMarker.uninitializeFailed);
      throw _asSessionException(firstError, ImSessionFailure.uninitialize);
    }
    _setState(const ImSessionState.idle());
    _logger(ImLifecycleMarker.uninitializeSucceeded);
  }

  Future<void> _logoutNative() async {
    await _quitActiveGroup();
    final int code = await _sdkClient.logout().timeout(operationTimeout);
    if (code != 0) {
      throw _TencentImSdkFailure(
        operation: ImSessionFailure.logout,
        providerCode: code,
      );
    }
    _loggedIn = false;
    _clearCredentialState();
  }

  Future<void> _shutdownNative() async {
    await _quitActiveGroup();
    if (_loggedIn) {
      try {
        await _logoutNative();
      } catch (_) {
        _loggedIn = false;
        _clearCredentialState();
      }
    }
    if (_initialized) {
      try {
        await _sdkClient.uninitSdk().timeout(operationTimeout);
      } catch (_) {
        // A fresh init is still attempted below; no credential is retained.
      }
    }
    _initialized = false;
    _sdkAppId = null;
    _clearCredentialState();
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final Future<void> previous = _serialTail;
    final Future<T> operation = previous.then<T>((_) => action());
    _serialTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  void _clearFlightWhenDone(Future<void> operation, void Function() clear) {
    operation.then<void>(
      (_) => clear(),
      onError: (Object _, StackTrace __) {
        clear();
      },
    );
  }

  void _validateCredentials(ImSessionCredentials credentials) {
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
      throw ImSessionException(
        failure: ImSessionFailure.invalidCredentials,
        message: 'IM 凭证无效',
      );
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
      _logger(ImLifecycleMarker.expired);
      throw const ImSessionException(
        failure: ImSessionFailure.invalidCredentials,
        message: 'IM 凭证已过期',
      );
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const ImSessionException(
        failure: ImSessionFailure.disposed,
        message: 'IM 适配器已释放',
      );
    }
  }

  void _clearCredentialState() {
    _credentials = null;
  }

  Future<void> _quitActiveGroup() async {
    final String? activeGroupId = _activeGroupId;
    if (activeGroupId == null || !supportsAvChatRoom) {
      _activeGroupId = null;
      return;
    }
    final TencentImSdkGroupClient groupClient =
        _sdkClient as TencentImSdkGroupClient;
    // Logout and re-initialization are already serialized by the lifecycle
    // queue. Call the provider directly here rather than queueing
    // [quitGroup] behind the current lifecycle operation (which would
    // deadlock). Ignore a provider failure after the bounded attempt, but
    // always clear the local fence.
    try {
      await groupClient
          .quitGroup(groupId: activeGroupId)
          .timeout(operationTimeout);
    } on Object {
      // The native session is still logged out below; a stale local group
      // fence must never survive that transition.
    } finally {
      if (_activeGroupId == activeGroupId) {
        _activeGroupId = null;
      }
    }
  }

  static bool _isSafeAvChatRoomGroupId(String value) {
    if (value.length < 1 || value.length > 48 || value.startsWith('@TGS#')) {
      return false;
    }
    for (final int codeUnit in value.codeUnits) {
      final bool printableAscii = codeUnit >= 0x21 && codeUnit <= 0x7e;
      if (!printableAscii) {
        return false;
      }
    }
    return true;
  }

  void _setState(ImSessionState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  static ImSessionException _asSessionException(
    Object error,
    ImSessionFailure fallback,
  ) {
    if (error is ImSessionException) {
      return error;
    }
    if (error is _TencentImSdkFailure) {
      return ImSessionException(
        failure: error.operation,
        message: _messageFor(error.operation),
        providerCode: error.providerCode,
      );
    }
    return ImSessionException(
      failure: fallback,
      message: _messageFor(fallback),
    );
  }

  static String _messageFor(ImSessionFailure failure) => switch (failure) {
    ImSessionFailure.blocked => '腾讯 IM 适配器未启用',
    ImSessionFailure.invalidCredentials => 'IM 凭证无效',
    ImSessionFailure.identityMismatch => 'IM 会话用户不匹配',
    ImSessionFailure.initialize => '腾讯 IM 初始化失败',
    ImSessionFailure.login => '腾讯 IM 登录失败',
    ImSessionFailure.renew => '腾讯 IM 凭证续期失败',
    ImSessionFailure.logout => '腾讯 IM 登出失败',
    ImSessionFailure.uninitialize => '腾讯 IM 反初始化失败',
    ImSessionFailure.provider => '腾讯 IM 服务不可用',
    ImSessionFailure.disposed => 'IM 适配器已释放',
  };

  static void _defaultLogger(ImLifecycleMarker marker) {
    // Fixed marker only: never concatenate user id, UserSig, app id, or SDK
    // exception text into this line.
    debugPrint('im.lifecycle.${marker.name}');
  }
}

class _TencentImSdkFailure implements Exception {
  const _TencentImSdkFailure({required this.operation, this.providerCode});

  final ImSessionFailure operation;
  final int? providerCode;
}
