import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/infrastructure/native_permission_adapter.dart';
import 'package:voice_social_app/features/room/domain/room_background_audio.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

// Explicit unit-test doubles. They do not establish native/device support.
class FakeRoomAudioPort implements RoomBackgroundAudioPort {
  final changes = StreamController<RoomBackgroundAudioActivity>.broadcast(
    sync: true,
  );
  final starts = <({String sessionId, bool microphone})>[];
  final stops = <String>[];
  final queries = <String>[];
  final active = <String, bool>{};
  bool allowStart = true;
  bool allowMicrophone = true;
  bool queryFails = false;
  Object? stopFailure;
  Completer<bool>? pendingStart;
  Completer<bool>? pendingQuery;
  void Function(bool microphone)? onStart;

  @override
  Stream<RoomBackgroundAudioActivity> get activities => changes.stream;
  @override
  Future<bool> start({
    required String sessionId,
    required bool microphone,
  }) async {
    starts.add((sessionId: sessionId, microphone: microphone));
    onStart?.call(microphone);
    final pending = pendingStart;
    pendingStart = null;
    final ok = pending != null
        ? await pending.future
        : allowStart && (!microphone || allowMicrophone);
    if (ok) active[sessionId] = true;
    return ok;
  }

  @override
  Future<void> stop({required String sessionId}) async {
    stops.add(sessionId);
    if (stopFailure != null) throw stopFailure!;
    active.remove(sessionId);
  }

  @override
  Future<bool> isActive({required String sessionId}) async {
    queries.add(sessionId);
    if (queryFails) throw StateError('native unavailable');
    final pending = pendingQuery;
    pendingQuery = null;
    return pending != null ? await pending.future : active[sessionId] == true;
  }

  void emit(String id, bool value) {
    active[id] = value;
    changes.add(RoomBackgroundAudioActivity(sessionId: id, active: value));
  }
}

RtcCredentials backgroundCredentials({
  String channel = 'unit-room',
  String role = 'broadcaster',
}) => RtcCredentials(
  solution: RtcSolution.agora,
  provider: 'agora',
  appId: 'unit-public-app',
  token: 'synthetic-unit-token',
  channelId: channel,
  uid: 42,
  role: role,
  expiresAt: DateTime.utc(2040),
  ttlSeconds: 90,
);

class BackgroundFakeRtcEngine implements RtcEngine {
  RtcEngineEventHandler? handler;
  RtcConnection connection = const RtcConnection();
  bool autoJoin = true;
  bool failPublish = false;
  bool failDisable = false;
  Completer<void>? pendingPublish;
  Completer<void>? pendingUnmute;
  int leaves = 0;
  final published = <bool>[];
  final muted = <bool>[];
  final renewed = <String>[];
  @override
  Future<void> initialize(RtcEngineContext context) async {}
  @override
  Future<void> enableAudio() async {}
  @override
  void registerEventHandler(RtcEngineEventHandler eventHandler) =>
      handler = eventHandler;
  @override
  void unregisterEventHandler(RtcEngineEventHandler eventHandler) {
    if (identical(handler, eventHandler)) handler = null;
  }

  @override
  Future<void> joinChannel({
    required String token,
    required String channelId,
    required int uid,
    required ChannelMediaOptions options,
  }) async {
    connection = RtcConnection(channelId: channelId, localUid: uid);
    if (autoJoin) joined();
  }

  void joined() => handler?.onJoinChannelSuccess?.call(connection, 0);
  @override
  Future<void> updateChannelMediaOptions(ChannelMediaOptions options) async {
    published.add(options.publishMicrophoneTrack!);
    if (failDisable && options.publishMicrophoneTrack == false)
      throw StateError('SDK disable rejected');
    if (options.publishMicrophoneTrack == true) await pendingPublish?.future;
    if (failPublish && options.publishMicrophoneTrack == true)
      throw StateError('SDK rejected');
  }

  @override
  Future<void> muteLocalAudioStream(bool mute) async {
    muted.add(mute);
    if (!mute) await pendingUnmute?.future;
  }

  @override
  Future<void> leaveChannel({LeaveChannelOptions? options}) async {
    leaves++;
    handler?.onLeaveChannel?.call(connection, const RtcStats());
  }

  @override
  Future<void> renewToken(String token) async {
    renewed.add(token);
    handler?.onRenewTokenResult?.call(
      connection,
      token,
      RenewTokenErrorCode.renewTokenSuccess,
    );
  }

  @override
  Future<void> release({bool sync = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BackgroundPermission implements NativePermissionAdapter {
  bool granted = true;
  int requests = 0;
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<PermissionState> status(PermissionKind kind) async =>
      granted ? PermissionState.granted : PermissionState.denied;
  @override
  Future<PermissionState> request(PermissionKind kind) async {
    requests++;
    return granted ? PermissionState.granted : PermissionState.denied;
  }
}

Future<void> flushBackgroundWork() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.value();
  }
}
