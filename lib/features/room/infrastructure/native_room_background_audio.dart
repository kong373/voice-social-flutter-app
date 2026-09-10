import 'package:first_party_room_audio/first_party_room_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:voice_social_app/features/room/domain/room_background_audio.dart';

/// Application-owned mapping from bounded native signals to the RTC port.
/// It is inert until a real joined RTC session requests native eligibility.
class NativeRoomBackgroundAudio implements RoomBackgroundAudioPort {
  final FirstPartyRoomAudio _native = FirstPartyRoomAudio();

  static NativeRoomBackgroundAudio? forCurrentPlatform() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }
    return NativeRoomBackgroundAudio();
  }

  @override
  Stream<RoomBackgroundAudioActivity> get activities => _native.events.map(
    (event) => RoomBackgroundAudioActivity(
      sessionId: event.sessionId,
      active: event.active,
      interruption: switch (event.interruption) {
        AudioInterruptionPhase.began => RoomAudioInterruptionPhase.began,
        AudioInterruptionPhase.ended => RoomAudioInterruptionPhase.ended,
        null => null,
      },
    ),
  );

  @override
  Future<bool> start({required String sessionId, required bool microphone}) =>
      _native.start(sessionId: sessionId, microphone: microphone);

  @override
  Future<void> stop({required String sessionId}) =>
      _native.stop(sessionId: sessionId);

  @override
  Future<bool> isActive({required String sessionId}) =>
      _native.isActive(sessionId: sessionId);

  Future<void> dispose() => _native.dispose();
}
