import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Linux contains exactly the reviewed 69-page and 14-state baselines',
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

      expect(macBaselines, hasLength(83));
      expect(linuxBaselines, macBaselines);
    },
  );
}
