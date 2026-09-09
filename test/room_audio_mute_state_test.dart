import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_audio_mute_state.dart';

void main() {
  test(
    'snapshot has no seat version and unoccupied stale effective bit is not a member restriction',
    () {
      final state = RoomAudioMuteState.optionalSnapshot({
        'selfMuted': false,
        'forcedMuted': false,
        'legacyMuted': false,
        'muted': true,
      }, occupied: false);
      expect(state?.effectiveMuted, isFalse);
      expect(state?.version, isNull);
      expect(
        RoomAudioMuteState.optionalSnapshot({'muted': false}, occupied: true),
        isNull,
      );
      expect(
        () => RoomAudioMuteState.optionalSnapshot({
          'selfMuted': false,
          'muted': false,
        }, occupied: true),
        throwsA(isA<ApiException>()),
      );
    },
  );
  for (var mask = 0; mask < 8; mask++) {
    test('independent microphone mute reasons $mask', () {
      final state = RoomAudioMuteState.parse({
        'selfMuted': mask & 1 != 0,
        'forcedMuted': mask & 2 != 0,
        'legacyMuted': mask & 4 != 0,
        'muted': mask != 0,
        'version': 9,
      });
      expect(state.selfMuted, mask & 1 != 0);
      expect(state.forcedMuted, mask & 2 != 0);
      expect(state.legacyMuted, mask & 4 != 0);
      expect(state.effectiveMuted, mask != 0);
      expect(state.version, 9);
    });
  }
  for (final invalid in [
    <String, Object?>{},
    {'selfMuted': 0},
    {'forcedMuted': 'false'},
    {'legacyMuted': null},
    {'version': -1},
    {'version': '1'},
    {'muted': true},
  ]) {
    test('strict microphone authority rejects $invalid', () {
      final map = invalid.isEmpty
          ? invalid
          : <String, Object?>{
              'selfMuted': false,
              'forcedMuted': false,
              'legacyMuted': false,
              'muted': false,
              'version': 0,
              ...invalid,
            };
      expect(() => RoomAudioMuteState.parse(map), throwsA(isA<ApiException>()));
    });
  }
}
