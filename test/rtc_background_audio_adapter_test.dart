import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

import 'support/room_background_audio_fakes.dart';

void main() {
  late BackgroundFakeRtcEngine engine;
  late FakeRoomAudioPort native;
  late BackgroundPermission permission;
  late AgoraRtcAdapter rtc;
  setUp(() {
    engine = BackgroundFakeRtcEngine();
    native = FakeRoomAudioPort();
    permission = BackgroundPermission();
    rtc = AgoraRtcAdapter(
      engine: engine,
      backgroundAudioPort: native,
      microphonePermissionAdapter: permission,
      credentialsProvider: (_) async => backgroundCredentials(),
    );
  });
  tearDown(() async {
    await rtc.release();
    await native.changes.close();
  });

  test(
    'runtime starts only after real join callback; ID is local UUID',
    () async {
      engine.autoJoin = false;
      final joining = rtc.join(backgroundCredentials());
      await flushBackgroundWork();
      expect(native.starts, isEmpty);
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      engine.joined();
      await joining;
      expect(native.starts, hasLength(1));
      expect(native.starts.single.microphone, isFalse);
      expect(
        native.starts.single.sessionId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(await rtc.confirmBackgroundAudioActive(), isTrue);
      expect(await rtc.confirmBackgroundAudioActive(), isTrue);
      expect(native.queries.length, greaterThanOrEqualTo(2));
    },
  );

  test(
    'join in background does not start runtime; foreground can establish it',
    () async {
      rtc.setForeground(false);
      await rtc.join(backgroundCredentials());
      expect(native.starts, isEmpty);
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      rtc.setForeground(true);
      await flushBackgroundWork();
      expect(await rtc.confirmBackgroundAudioActive(), isTrue);
    },
  );

  test(
    'microphone upgrade precedes publication; disabling downgrades same UUID',
    () async {
      await rtc.join(backgroundCredentials());
      final id = native.starts.single.sessionId;
      native.onStart = (mic) {
        if (mic) expect(engine.published, isEmpty);
        if (!mic) expect(engine.published.last, isFalse);
      };
      await rtc.setLocalAudioEnabled(true);
      expect(native.starts.last, (sessionId: id, microphone: true));
      expect(engine.published, [true]);
      rtc.setForeground(false);
      await rtc.setLocalAudioEnabled(false);
      expect(native.starts.last, (sessionId: id, microphone: false));
      expect(await rtc.confirmBackgroundAudioActive(), isTrue);
    },
  );

  test(
    'native refusal cannot publish; null port retains foreground publication',
    () async {
      await rtc.join(backgroundCredentials());
      native.allowMicrophone = false;
      await expectLater(
        rtc.setLocalAudioEnabled(true),
        throwsA(isA<RtcAdapterException>()),
      );
      expect(engine.published.where((v) => v), isEmpty);
      expect(rtc.localAudioEnabled, isFalse);
      final noNative = AgoraRtcAdapter(
        engine: BackgroundFakeRtcEngine(),
        microphonePermissionAdapter: permission,
      );
      await noNative.join(backgroundCredentials());
      await noNative.setLocalAudioEnabled(true);
      expect(noNative.localAudioEnabled, isTrue);
      expect(await noNative.confirmBackgroundAudioActive(), isFalse);
      await noNative.release();
    },
  );

  test(
    'permission denial and audience role never request native microphone',
    () async {
      await rtc.join(backgroundCredentials());
      permission.granted = false;
      await expectLater(
        rtc.setLocalAudioEnabled(true),
        throwsA(isA<RtcAdapterException>()),
      );
      expect(native.starts.where((v) => v.microphone), isEmpty);
      await rtc.reconnect(backgroundCredentials(role: 'audience'));
      permission.granted = true;
      await expectLater(
        rtc.setLocalAudioEnabled(true),
        throwsA(isA<RtcAdapterException>()),
      );
      expect(native.starts.where((v) => v.microphone), isEmpty);
    },
  );

  test('SDK publish failure cleans native microphone capability', () async {
    await rtc.join(backgroundCredentials());
    engine.failPublish = true;
    await expectLater(
      rtc.setLocalAudioEnabled(true),
      throwsA(isA<RtcAdapterException>()),
    );
    expect(rtc.localAudioEnabled, isFalse);
    expect(
      native.starts.last.microphone == false || native.stops.isNotEmpty,
      isTrue,
    );
  });

  test(
    'native inactive event cannot be reversed by stale true event/query',
    () async {
      await rtc.join(backgroundCredentials());
      final id = native.starts.single.sessionId;
      await rtc.setLocalAudioEnabled(true);
      final reply = Completer<bool>();
      native.pendingQuery = reply;
      final query = rtc.confirmBackgroundAudioActive();
      await flushBackgroundWork();
      native.emit(id, false);
      native.emit(id, true);
      reply.complete(true);
      expect(await query, isFalse);
      await flushBackgroundWork();
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      expect(rtc.localAudioEnabled, isFalse);
    },
  );

  test(
    'old generation event/query reply cannot authorize or stop new lease',
    () async {
      await rtc.join(backgroundCredentials());
      final old = native.starts.single.sessionId;
      final reply = Completer<bool>();
      native.pendingQuery = reply;
      final query = rtc.confirmBackgroundAudioActive();
      await flushBackgroundWork();
      final reconnecting = rtc.reconnect(
        backgroundCredentials(channel: 'other-unit-room'),
      );
      await flushBackgroundWork();
      reply.complete(true);
      expect(await query, isFalse);
      await reconnecting;
      final current = native.starts.last.sessionId;
      expect(current, isNot(old));
      native.emit(old, false);
      native.emit(old, true);
      expect(await rtc.confirmBackgroundAudioActive(), isTrue);
      expect(native.stops, isNot(contains(current)));
    },
  );

  test(
    'leave during native start fences late success and cleans only old UUID',
    () async {
      final reply = Completer<bool>();
      native.pendingStart = reply;
      final joining = rtc.join(backgroundCredentials());
      await flushBackgroundWork();
      final old = native.starts.single.sessionId;
      final leaving = rtc.leave();
      reply.complete(true);
      await joining;
      await leaving;
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      expect(native.active[old], isNot(true));
      await rtc.join(backgroundCredentials(channel: 'next-unit-room'));
      expect(native.starts.last.sessionId, isNot(old));
      expect(await rtc.confirmBackgroundAudioActive(), isTrue);
    },
  );

  test(
    'reconnect and dispose stop native runtime without automatic publication',
    () async {
      await rtc.join(backgroundCredentials());
      await rtc.setLocalAudioEnabled(true);
      final old = native.starts.first.sessionId;
      await rtc.reconnect(backgroundCredentials());
      expect(native.stops, contains(old));
      expect(native.starts.last.microphone, isFalse);
      expect(rtc.localAudioEnabled, isFalse);
      final current = native.starts.last.sessionId;
      await rtc.release();
      expect(native.stops, contains(current));
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
    },
  );

  test(
    'network failure removes capability; token renewal chain is unchanged',
    () async {
      await rtc.join(backgroundCredentials());
      rtc.setForeground(false);
      engine.handler!.onTokenPrivilegeWillExpire!(
        engine.connection,
        'synthetic-unit-token',
      );
      await flushBackgroundWork();
      expect(engine.renewed, hasLength(1));
      engine.handler!.onConnectionStateChanged!(
        engine.connection,
        ConnectionStateType.connectionStateFailed,
        ConnectionChangedReasonType.values.first,
      );
      await flushBackgroundWork();
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      final starts = native.starts.length;
      rtc.setForeground(true);
      await flushBackgroundWork();
      expect(native.starts, hasLength(starts));
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
    },
  );

  test(
    'native loss while SDK publish is pending cannot subsequently unmute',
    () async {
      await rtc.join(backgroundCredentials());
      final pending = Completer<void>();
      engine.pendingPublish = pending;
      final enabling = rtc.setLocalAudioEnabled(true);
      await flushBackgroundWork();
      expect(engine.published, [true]);
      native.emit(native.starts.first.sessionId, false);
      pending.complete();
      await enabling;
      await flushBackgroundWork();
      expect(engine.muted, isNot(contains(false)));
      expect(engine.published.last, isFalse);
      expect(rtc.localAudioEnabled, isFalse);
    },
  );

  test(
    'native event stream error revokes capability and stops its UUID',
    () async {
      await rtc.join(backgroundCredentials());
      final id = native.starts.single.sessionId;
      native.changes.addError(StateError('malformed native event'));
      await flushBackgroundWork();
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      expect(native.stops, contains(id));
    },
  );

  test(
    'background transition fences a pending foreground native start',
    () async {
      final pending = Completer<bool>();
      native.pendingStart = pending;
      final joining = rtc.join(backgroundCredentials());
      await flushBackgroundWork();
      final id = native.starts.single.sessionId;
      rtc.setForeground(false);
      pending.complete(true);
      await joining;
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      expect(native.active[id], isNot(true));
    },
  );

  test(
    'cleanup timeout fences local capability without claiming native stopped',
    () async {
      await rtc.join(backgroundCredentials());
      final id = native.starts.single.sessionId;
      native.stopFailure = TimeoutException('bounded native stop');
      await rtc.leave();
      await flushBackgroundWork();
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      expect(
        native.active[id],
        isTrue,
      ); // Unknown native teardown is not success.
      native.emit(id, true);
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      await rtc.release();
    },
  );

  test('native loss falls back to RTC leave when SDK disable fails', () async {
    await rtc.join(backgroundCredentials());
    await rtc.setLocalAudioEnabled(true);
    engine.failDisable = true;
    native.emit(native.starts.first.sessionId, false);
    await flushBackgroundWork();
    expect(engine.leaves, 1);
    expect(rtc.joined, isFalse);
    expect(await rtc.confirmBackgroundAudioActive(), isFalse);
  });

  test(
    'duplicate SDK recovery callback cannot downgrade a queued mic upgrade',
    () async {
      await rtc.join(backgroundCredentials());
      engine.handler!.onConnectionStateChanged!(
        engine.connection,
        ConnectionStateType.connectionStateReconnecting,
        ConnectionChangedReasonType.connectionChangedInterrupted,
      );
      await flushBackgroundWork();
      final start = Completer<bool>();
      native.pendingStart = start;
      engine.handler!.onConnectionStateChanged!(
        engine.connection,
        ConnectionStateType.connectionStateConnected,
        ConnectionChangedReasonType.connectionChangedJoinSuccess,
      );
      await flushBackgroundWork();
      final enabling = rtc.setLocalAudioEnabled(true);
      await flushBackgroundWork();
      engine.handler!.onRejoinChannelSuccess!(engine.connection, 0);
      start.complete(true);
      await enabling;
      await flushBackgroundWork();
      expect(native.starts.last.microphone, isTrue);
      expect(rtc.localAudioEnabled, isTrue);
    },
  );

  test(
    'late SDK unmute failure cannot roll back a newer RTC generation',
    () async {
      await rtc.join(backgroundCredentials());
      final unmute = Completer<void>();
      engine.pendingUnmute = unmute;
      final enabling = rtc.setLocalAudioEnabled(true);
      final rejected = expectLater(
        enabling,
        throwsA(isA<RtcAdapterException>()),
      );
      await flushBackgroundWork();
      await rtc.reconnect(
        backgroundCredentials(channel: 'new-unit-room', role: 'audience'),
      );
      final published = List<bool>.of(engine.published);
      final muted = List<bool>.of(engine.muted);
      unmute.completeError(StateError('late old unmute failure'));
      await rejected;
      expect(engine.published, published);
      expect(engine.muted, muted);
      expect(await rtc.confirmBackgroundAudioActive(), isTrue);
    },
  );

  test(
    'timed out start stays ordered; late success cannot revive old UUID',
    () async {
      final pending = Completer<bool>();
      native.pendingStart = pending;
      await rtc.join(backgroundCredentials()); // Adapter's bounded 2s timeout.
      final old = native.starts.single.sessionId;
      expect(await rtc.confirmBackgroundAudioActive(), isFalse);
      await rtc.leave();
      final joining = rtc.join(backgroundCredentials(channel: 'after-timeout'));
      await flushBackgroundWork();
      expect(
        native.starts,
        hasLength(1),
      ); // No native overtaking while unknown.
      pending.complete(true);
      await joining;
      expect(native.active[old], isNot(true));
      expect(native.starts.last.sessionId, isNot(old));
      expect(await rtc.confirmBackgroundAudioActive(), isTrue);
    },
  );

  test(
    'disable during pending native upgrade wins without SDK publish',
    () async {
      await rtc.join(backgroundCredentials());
      final pending = Completer<bool>();
      native.pendingStart = pending;
      final enabling = rtc.setLocalAudioEnabled(true);
      await flushBackgroundWork();
      final disabling = rtc.setLocalAudioEnabled(false);
      pending.complete(true);
      await enabling;
      await disabling;
      expect(engine.published, [false]);
      expect(native.starts.last.microphone, isFalse);
    },
  );
}
