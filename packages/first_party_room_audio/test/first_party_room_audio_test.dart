import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:first_party_room_audio/first_party_room_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('voice_social_app/room_audio');
  const eventChannel = MethodChannel('voice_social_app/room_audio/events');
  const id = '12345678-1234-4234-8234-123456789abc';
  const other = '12345678-1234-4234-8234-123456789abd';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(eventChannel, (_) async => null);
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'stop' ? null : true,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(eventChannel, null);
  });
  void emit(Object payload) {
    ServicesBinding.instance.channelBuffers.push(
      eventChannel.name,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  test('rejects token-shaped identifiers before native invocation', () async {
    final audio = FirstPartyRoomAudio();
    await expectLater(
      audio.start(sessionId: 'secret.token', microphone: false),
      throwsArgumentError,
    );
    await audio.dispose();
  });
  test(
    'stale stop cannot release current generation; conflicts fail closed',
    () async {
      final audio = FirstPartyRoomAudio();
      expect(await audio.start(sessionId: id, microphone: false), isTrue);
      expect(await audio.start(sessionId: other, microphone: false), isFalse);
      await audio.stop(sessionId: other);
      expect(await audio.isActive(sessionId: id), isTrue);
      await audio.dispose();
    },
  );
  test('non boolean native result fails closed', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'stop' ? null : 1,
    );
    final audio = FirstPartyRoomAudio();
    expect(await audio.start(sessionId: id, microphone: true), isFalse);
    await audio.dispose();
  });
  test('stable platform failure is false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'stop') return null;
      throw PlatformException(code: 'unavailable');
    });
    final audio = FirstPartyRoomAudio();
    expect(await audio.start(sessionId: id, microphone: false), isFalse);
    await audio.dispose();
  });
  test('events reject unknown fields, wrong bool and malformed UUID', () async {
    final audio = FirstPartyRoomAudio();
    final values = <RoomAudioActivity>[];
    final errors = <Object>[];
    final sub = audio.events.listen(values.add, onError: errors.add);
    await audio.start(sessionId: id, microphone: false);
    emit({'sessionId': id, 'active': true, 'extra': false});
    emit({'sessionId': id, 'active': 1});
    emit({'sessionId': '$id\n', 'active': true});
    emit({'sessionId': id, 'active': true});
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(3));
    expect(errors.every((e) => e is FormatException), isTrue);
    expect(values, hasLength(1));
    expect(values.single.sessionId, id);
    expect(values.single.active, isFalse);
    await sub.cancel();
    await audio.dispose();
  });
  test('old inactive event does not clear current generation', () async {
    final audio = FirstPartyRoomAudio();
    await audio.start(sessionId: id, microphone: false);
    emit({'sessionId': other, 'active': false});
    await Future<void>.delayed(Duration.zero);
    expect(await audio.start(sessionId: other, microphone: false), isFalse);
    emit({'sessionId': id, 'active': false});
    await Future<void>.delayed(Duration.zero);
    expect(await audio.start(sessionId: other, microphone: false), isTrue);
    await audio.dispose();
  });
  test(
    'start waits for native confirmation; stop is serialized after it',
    () async {
      final confirmation = Completer<bool>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'start' ? confirmation.future : null;
      });
      final audio = FirstPartyRoomAudio();
      final start = audio.start(sessionId: id, microphone: false);
      final stop = audio.stop(sessionId: id);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['start']);
      confirmation.complete(true);
      expect(await start, isTrue);
      await stop;
      expect(calls, ['start', 'stop']);
      await audio.dispose();
    },
  );
  test('failed native renewal emits inactive and stops renewing', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'stop' ? null : call.method == 'start';
    });
    final audio = FirstPartyRoomAudio();
    final values = <RoomAudioActivity>[];
    final sub = audio.events.listen(values.add);
    expect(await audio.start(sessionId: id, microphone: false), isTrue);
    await audio.events.first.timeout(const Duration(seconds: 15));
    expect(calls.where((c) => c == 'renew'), hasLength(1));
    expect(values.single.active, isFalse);
    expect(values.single.sessionId, id);
    await Future<void>.delayed(const Duration(seconds: 11));
    expect(calls.where((c) => c == 'renew'), hasLength(1));
    await sub.cancel();
    await audio.dispose();
  });
  test(
    'failed upgrade keeps current generation until native invalidation',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'start'
            ? (call.arguments as Map)['microphone'] == false
            : call.method == 'stop'
            ? null
            : true,
      );
      final audio = FirstPartyRoomAudio();
      expect(await audio.start(sessionId: id, microphone: false), isTrue);
      expect(await audio.start(sessionId: id, microphone: true), isFalse);
      expect(await audio.start(sessionId: other, microphone: false), isFalse);
      await audio.dispose();
    },
  );
}
