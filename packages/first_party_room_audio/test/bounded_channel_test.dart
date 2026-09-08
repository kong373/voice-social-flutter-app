import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:first_party_room_audio/first_party_room_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('voice_social_app/room_audio');
  const events = MethodChannel('voice_social_app/room_audio/events');
  const id = '12345678-1234-4234-8234-123456789abc';
  const next = '12345678-1234-4234-8234-123456789abd';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late FirstPartyRoomAudio audio;
  late Future<Object?> Function(MethodCall) respond;
  setUp(() {
    calls.clear();
    respond = (call) async => call.method == 'stop' ? null : true;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return respond(call);
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    audio = FirstPartyRoomAudio(
      channelTimeout: const Duration(milliseconds: 30),
    );
  });
  tearDown(() async {
    respond = (call) async => call.method == 'stop' ? null : false;
    try {
      await audio.dispose().timeout(const Duration(seconds: 1));
    } on TimeoutException {
      // A failed dispose retains its failure for subsequent callers.
    }
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });
  void emit(Object value) => ServicesBinding.instance.channelBuffers.push(
    events.name,
    const StandardMethodCodec().encodeSuccessEnvelope(value),
    (_) {},
  );

  test(
    'hung start releases serial queue and late true cannot restore old lease',
    () async {
      final late = Completer<Object?>();
      respond = (call) async =>
          call.method == 'start' && (call.arguments as Map)['sessionId'] == id
          ? late.future
          : call.method == 'stop'
          ? null
          : true;
      expect(
        await audio
            .start(sessionId: id, microphone: false)
            .timeout(const Duration(seconds: 1)),
        isFalse,
      );
      expect(await audio.start(sessionId: next, microphone: false), isTrue);
      late.complete(true);
      emit({'sessionId': id, 'active': true});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await audio.isActive(sessionId: next), isTrue);
      expect(
        calls
            .where((c) => c.method == 'stop')
            .map((c) => (c.arguments as Map)['sessionId']),
        [id],
      );
    },
  );
  for (final method in ['stop', 'dispose']) {
    test(
      'hung $method reports timeout and does not block subsequent disposal',
      () async {
        await audio.start(sessionId: id, microphone: false);
        respond = (_) => Completer<Object?>().future;
        await expectLater(
          method == 'stop' ? audio.stop(sessionId: id) : audio.dispose(),
          throwsA(isA<TimeoutException>()),
        );
        if (method == 'dispose') {
          await expectLater(audio.dispose(), throwsA(isA<TimeoutException>()));
        } else {
          respond = (call) async => call.method == 'stop' ? null : false;
          await audio.dispose().timeout(const Duration(seconds: 1));
        }
      },
    );
  }
  test(
    'hung isActive clears only queried generation and stops its renewal',
    () async {
      await audio.start(sessionId: id, microphone: false);
      respond = (call) => call.method == 'isActive'
          ? Completer<Object?>().future
          : Future.value(call.method == 'stop' ? null : true);
      expect(await audio.isActive(sessionId: next), isFalse);
      expect(await audio.start(sessionId: next, microphone: false), isFalse);
      expect(await audio.isActive(sessionId: id), isFalse);
      expect(await audio.start(sessionId: next, microphone: false), isTrue);
    },
  );
  test(
    'malformed event invalidates pending start despite late success',
    () async {
      final late = Completer<Object?>();
      respond = (call) =>
          call.method == 'start' ? late.future : Future.value(null);
      final errors = <Object>[];
      final values = <RoomAudioActivity>[];
      final sub = audio.events.listen(values.add, onError: errors.add);
      final started = audio.start(sessionId: id, microphone: false);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      emit({'sessionId': id, 'active': 1});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      late.complete(true);
      expect(await started, isFalse);
      expect(values.single.active, isFalse);
      expect(errors.single, isA<FormatException>());
      await sub.cancel();
    },
  );
  test(
    'malformed event emits inactive and never renews invalidated generation',
    () async {
      final errors = <Object>[];
      final values = <RoomAudioActivity>[];
      final sub = audio.events.listen(values.add, onError: errors.add);
      await audio.start(sessionId: id, microphone: false);
      emit({'sessionId': id, 'active': true, 'extra': 1});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(values.single.active, isFalse);
      expect(errors.single, isA<FormatException>());
      await Future<void>.delayed(const Duration(seconds: 11));
      expect(calls.where((c) => c.method == 'renew'), isEmpty);
      expect(calls.where((c) => c.method == 'stop').single.arguments, {
        'sessionId': id,
      });
      await sub.cancel();
    },
  );
  test(
    'late cleanup of malformed generation never stops its replacement',
    () async {
      final cleanup = Completer<Object?>();
      respond = (call) =>
          call.method == 'stop' && (call.arguments as Map)['sessionId'] == id
          ? cleanup.future
          : Future.value(call.method == 'stop' ? null : true);
      final values = <RoomAudioActivity>[];
      final sub = audio.events.listen(values.add, onError: (Object _) {});
      await audio.start(sessionId: id, microphone: false);
      emit({'active': false});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await audio.start(sessionId: next, microphone: false), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      cleanup.complete(null);
      emit({'sessionId': id, 'active': true});
      await Future<void>.delayed(Duration.zero);
      expect(values.where((event) => event.active), isEmpty);
      expect(await audio.isActive(sessionId: next), isTrue);
      expect(
        calls
            .where((call) => call.method == 'stop')
            .map((call) => (call.arguments as Map)['sessionId']),
        [id],
      );
      await sub.cancel();
    },
  );
  test('hung renew expires locally and frees stop and dispose', () async {
    respond = (call) => call.method == 'renew'
        ? Completer<Object?>().future
        : Future.value(call.method == 'stop' ? null : true);
    await audio.start(sessionId: id, microphone: false);
    final inactive = await audio.events.first.timeout(
      const Duration(seconds: 12),
    );
    expect(inactive.sessionId, id);
    expect(inactive.active, isFalse);
    await audio.stop(sessionId: id).timeout(const Duration(seconds: 1));
    await audio.dispose().timeout(const Duration(seconds: 1));
  });
}
