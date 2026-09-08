import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/room/infrastructure/native_room_background_audio.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

import 'support/room_background_audio_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('voice_social_app/room_audio');
  const events = MethodChannel('voice_social_app/room_audio/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'stop' ? null : true;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('only mobile native hosts create the background audio port', () async {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final audio = NativeRoomBackgroundAudio.forCurrentPlatform();
      expect(
        audio != null,
        platform == TargetPlatform.android || platform == TargetPlatform.iOS,
      );
      await audio?.dispose();
    }
    expect(calls, isEmpty);
  });

  test(
    'joined RTC uses actual native bridge and fresh query, loss revokes it',
    () async {
      final audio = NativeRoomBackgroundAudio();
      final engine = BackgroundFakeRtcEngine();
      final rtc = AgoraRtcAdapter(
        engine: engine,
        microphonePermissionAdapter: BackgroundPermission(),
        backgroundAudioPort: audio,
      );
      expect(calls, isEmpty);
      await rtc.join(backgroundCredentials());
      final id = (calls.single.arguments as Map)['sessionId'] as String;
      expect(calls.single.method, 'start');
      expect((calls.single.arguments as Map)['microphone'], false);
      await rtc.setLocalAudioEnabled(true);
      expect(engine.published, [true]);
      rtc.setForeground(false);
      expect(await rtc.confirmBackgroundAudioActive(), true);
      expect(calls.last.method, 'isActive');
      expect(calls.last.arguments, {'sessionId': id});
      ServicesBinding.instance.channelBuffers.push(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'sessionId': id,
          'active': false,
        }),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      await flushBackgroundWork();
      expect(await rtc.confirmBackgroundAudioActive(), false);
      expect(rtc.localAudioEnabled, false);
      await rtc.release();
      await audio.dispose();
      expect(calls.where((c) => c.method == 'stop'), isNotEmpty);
      expect(calls.every((c) => (c.arguments as Map)['sessionId'] == id), true);
    },
  );

  test(
    'native teardown error is not translated into confirmed success',
    () async {
      final audio = NativeRoomBackgroundAudio();
      const id = '12345678-1234-4234-8234-123456789abc';
      await audio.start(sessionId: id, microphone: false);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      await expectLater(
        audio.stop(sessionId: id),
        throwsA(isA<PlatformException>()),
      );
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'stop' ? null : false,
      );
      await audio.dispose();
    },
  );
}
