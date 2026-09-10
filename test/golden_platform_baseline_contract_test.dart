import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Linux mirrors retained page, runtime-state, and preset-avatar baselines',
    () {
      final Directory goldenRoot = Directory('test/goldens');
      final Directory linuxRoot = Directory('${goldenRoot.path}/linux');

      final List<String> macBaselines =
          goldenRoot
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (File file) =>
                    file.path.endsWith('.png') &&
                    !file.path.startsWith('${linuxRoot.path}/'),
              )
              .map(
                (File file) => file.path.substring(goldenRoot.path.length + 1),
              )
              .toList()
            ..sort();
      final List<String> linuxBaselines =
          linuxRoot
              .listSync(recursive: true)
              .whereType<File>()
              .where((File file) => file.path.endsWith('.png'))
              .map(
                (File file) => file.path.substring(linuxRoot.path.length + 1),
              )
              .toList()
            ..sort();

      // The retained page archive includes retired pages. Active-page coverage
      // is separately driven by qaPageCatalog; this is platform file parity.
      expect(
        macBaselines.where((String path) => path.startsWith('m3_3_all/')),
        hasLength(69),
      );
      expect(
        macBaselines.where(
          (String path) =>
              path.startsWith('m3_3_') && !path.startsWith('m3_3_all/'),
        ),
        hasLength(14),
      );
      expect(macBaselines, contains('preset_avatar_gallery_360.png'));
      expect(macBaselines, hasLength(84));
      expect(linuxBaselines, macBaselines);
    },
  );
}
