import 'dart:async';

import 'package:first_party_room_audio/first_party_room_audio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('voice_social_app/room_audio');
  const events = MethodChannel('voice_social_app/room_audio/events');
  const id = '12345678-1234-4234-8234-123456789abc';
  const next = '12345678-1234-4234-8234-123456789abd';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final received = <RoomAudioActivity>[];
  final errors = <Object>[];
  late FirstPartyRoomAudio audio;
  late StreamSubscription<RoomAudioActivity> sub;
  setUp(() {
    calls.clear();
    received.clear();
    errors.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'stop' ? null : true;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    audio = FirstPartyRoomAudio();
    sub = audio.events.listen(received.add, onError: errors.add);
  });
  tearDown(() async {
    await audio.dispose();
    await sub.cancel();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });
  void emit(Map<String, Object> data) =>
      ServicesBinding.instance.channelBuffers.push(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(data),
        (_) {},
      );
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Map<String, Object> phase(String value, {String session = id}) => {
    'sessionId': session,
    'active': false,
    'interruption': value,
  };

  test(
    'matched interruption is inactive until an explicit start; never calls native stop on began',
    () async {
      await audio.start(sessionId: id, microphone: true);
      emit(phase('began'));
      await flush();
      expect(received.single.interruption, AudioInterruptionPhase.began);
      expect(received.single.active, isFalse);
      expect(calls.where((c) => c.method == 'stop'), isEmpty);
      expect(await audio.start(sessionId: id, microphone: true), isFalse);
      emit(phase('ended'));
      emit(phase('ended'));
      emit({
        'sessionId': id,
        'active': true,
      }); // A late true is not a fresh start ack.
      await flush();
      expect(received.map((e) => e.interruption), [
        AudioInterruptionPhase.began,
        AudioInterruptionPhase.ended,
      ]);
      expect(received.every((e) => !e.active), isTrue);
      expect(calls.where((c) => c.method == 'start').length, 1);
      expect(await audio.start(sessionId: id, microphone: true), isTrue);
    },
  );
  for (final revoke in ['stop', 'expiry', 'malformed', 'dispose']) {
    test(
      '$revoke cancels an interrupted generation before a late end',
      () async {
        await audio.start(sessionId: id, microphone: true);
        emit(phase('began'));
        await flush();
        switch (revoke) {
          case 'stop':
            await audio.stop(sessionId: id);
          case 'expiry':
            emit({'sessionId': id, 'active': false});
          case 'malformed':
            emit({...phase('ended'), 'extra': true});
          case 'dispose':
            await audio.dispose();
        }
        await flush();
        if (revoke != 'dispose') {
          await audio.start(sessionId: next, microphone: false);
          emit(phase('ended'));
          await flush();
          expect(await audio.isActive(sessionId: next), isTrue);
        }
        expect(
          received.where((e) => e.interruption == AudioInterruptionPhase.ended),
          isEmpty,
        );
      },
    );
  }
  test(
    'unmatched end and foreign begin cannot interrupt another active UUID',
    () async {
      await audio.start(sessionId: id, microphone: true);
      emit(phase('ended'));
      emit(phase('began', session: next));
      emit(phase('ended', session: next));
      await flush();
      expect(received, isEmpty);
      expect(await audio.isActive(sessionId: id), isTrue);
    },
  );
  for (final malformed in [
    {...phase('began'), 'active': true},
    phase('unknown'),
    phase('ended', session: '$id\n'),
  ]) {
    test('invalid interruption wire fails closed: $malformed', () async {
      await audio.start(sessionId: id, microphone: true);
      emit(malformed);
      await flush();
      expect(errors.single, isA<FormatException>());
      expect(received.single.active, isFalse);
      expect(received.single.interruption, isNull);
      emit(phase('ended'));
      await flush();
      expect(received.length, 1);
    });
  }
  test(
    'old in-flight renew false cannot cancel a later system interruption',
    () async {
      final renew = Completer<Object?>();
      final enteredRenew = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'renew') {
          if (!enteredRenew.isCompleted) enteredRenew.complete();
          return renew.future;
        }
        return call.method == 'stop' ? null : true;
      });
      expect(
        await audio
            .start(sessionId: id, microphone: true)
            .timeout(const Duration(seconds: 2)),
        isTrue,
      );
      await enteredRenew.future.timeout(const Duration(seconds: 12));
      expect(calls.where((c) => c.method == 'renew').length, 1);
      emit(phase('began'));
      await flush();
      renew.complete(false);
      await flush();
      emit(phase('ended'));
      await flush();
      expect(received.map((e) => e.interruption), [
        AudioInterruptionPhase.began,
        AudioInterruptionPhase.ended,
      ]);
      expect(calls.where((c) => c.method == 'stop'), isEmpty);
      await audio.dispose().timeout(const Duration(seconds: 2));
    },
  );
}
