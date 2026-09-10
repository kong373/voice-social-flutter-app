import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_models.dart';

void main() {
  for (final purpose in ['ROOM_COVER', 'ROOM_BACKGROUND']) {
    test('$purpose accepts strict image descriptor and decimal 10MB limit', () {
      final media = MediaReference.fromJson({
        'assetId': '11111111-2222-4333-8444-555555555555',
        'purpose': purpose,
        'mediaType': 'image/webp',
        'bytes': 10000000,
        'durationMillis': 0,
        'version': 3,
      });
      expect(media.purpose.maximumBytes, 10000000);
      expect(media.purpose.maximumCount, 1);
      expect(media.version, 3);
    });
  }
}
