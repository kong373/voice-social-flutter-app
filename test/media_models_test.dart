import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/api_exception.dart';

const mediaId = '11111111-2222-4333-8444-555555555555';
Map<String, Object?> reference({String purpose = 'PRIVATE_IMAGE'}) => {
  'assetId': mediaId,
  'purpose': purpose,
  'mediaType': 'image/png',
  'bytes': 12,
  'durationMillis': 0,
  'version': 3,
};
Map<String, Object?> status({String state = 'ALLOCATED', int version = 0}) => {
  ...reference(),
  'state': state,
  'version': version,
  'maximumBytes': 10000000,
  'expiresAt': '2030-01-01T00:00:00Z',
  if (state != 'READY') ...{
    'mediaType': null,
    'bytes': state == 'QUARANTINED' || state == 'REJECTED' ? 12 : null,
    'durationMillis': null,
  },
};

void main() {
  test('strict six fields and READY status preserve authoritative values', () {
    final value = MediaReference.fromJson(reference());
    expect(value.toJson(), reference());
    expect(
      MediaAssetStatus.fromJson(
        status(state: 'READY', version: 3),
      ).ready!.toJson(),
      reference(),
    );
    expect(MediaAssetStatus.fromJson(status()).ready, isNull);
    expect(
      MediaAssetStatus.fromJson({
        ...status(state: 'QUARANTINED', version: 2),
        'bytes': 12,
      }).bytes,
      12,
    );
  });
  test('reject invalid/extra fields, coercions and contradictory READY', () {
    for (final bad in <Map<String, Object?>>[
      {...reference(), 'url': 'https://external.invalid/file'},
      {...reference()}..remove('durationMillis'),
      {...reference(), 'bytes': '12'},
      {...reference(), 'bytes': 12.0},
      {...reference(), 'version': -1},
      {...reference(), 'assetId': '../content'},
      {...reference(), 'purpose': 'UNKNOWN'},
      {...reference(), 'mediaType': 'image/png; charset=UTF-8'},
      {...reference(), 'durationMillis': 1},
      {...reference(), 'bytes': 10000001},
    ]) {
      expect(() => MediaReference.fromJson(bad), throwsA(isA<ApiException>()));
    }
    for (final bad in <Map<String, Object?>>[
      {...status(), 'state': 'DONE'},
      {...status(), 'maximumBytes': 100000000},
      {...status(), 'version': '0'},
      {...status(), 'expiresAt': '2030-02-31T00:00:00Z'},
      {...status(), 'expiresAt': '2030-01-01T08:00:00+08:00'},
      {...status(), 'state': 'READY'},
      {...status(), 'storagePath': '/private/file'},
    ]) {
      expect(
        () => MediaAssetStatus.fromJson(bad),
        throwsA(isA<ApiException>()),
      );
    }
  });
  test('decimal byte, millisecond, type and per-submission count limits', () {
    for (final purpose in MediaPurpose.values) {
      final timed =
          purpose == MediaPurpose.privateVoice ||
          purpose == MediaPurpose.privateVideo;
      final duration = purpose == MediaPurpose.privateVoice
          ? 60000
          : timed
          ? 30000
          : 0;
      MediaLimits.validateSelection(
        purpose,
        bytes: purpose.maximumBytes,
        durationMillis: duration,
      );
      expect(
        () => MediaLimits.validateSelection(
          purpose,
          bytes: purpose.maximumBytes + 1,
          durationMillis: duration,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => MediaLimits.validateSelection(
          purpose,
          bytes: 0,
          durationMillis: duration,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => MediaLimits.validateSelection(
          purpose,
          bytes: 1,
          durationMillis: duration + 1,
        ),
        throwsA(isA<ApiException>()),
      );
    }
    for (final purpose in [
      MediaPurpose.dynamicImage,
      MediaPurpose.supportImage,
      MediaPurpose.privateImage,
    ]) {
      final ids = List.generate(
        purpose.maximumCount,
        (i) => '11111111-2222-4333-8444-${i.toString().padLeft(12, '0')}',
      );
      MediaLimits.validateReferences(purpose, ids);
      MediaLimits.validateReferences(
        purpose,
        ids,
      ); // each support submission, not total history
      expect(
        () => MediaLimits.validateReferences(purpose, [...ids, mediaId]),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => MediaLimits.validateReferences(purpose, [mediaId, mediaId]),
        throwsA(isA<ApiException>()),
      );
    }
    expect(
      MediaReference.fromJson({
        ...reference(purpose: 'PRIVATE_VOICE'),
        'mediaType': 'audio/mp4',
        'durationMillis': 60000,
      }).durationMillis,
      60000,
    );
    expect(
      () => MediaReference.fromJson({
        ...reference(purpose: 'PRIVATE_VIDEO'),
        'mediaType': 'video/mp4',
        'durationMillis': 30001,
      }),
      throwsA(isA<ApiException>()),
    );
  });
}
