import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden_font_gate.dart';

void main() {
  test('golden fonts are checked into test/fonts', () {
    final Directory fontDirectory = resolveGoldenFontDirectory();

    expect(fontDirectory.existsSync(), isTrue);
    expect(
      File('${fontDirectory.path}/$kGoldenRegularFontFile').existsSync(),
      isTrue,
    );
    expect(
      File('${fontDirectory.path}/$kGoldenBoldFontFile').existsSync(),
      isTrue,
    );
    expect(
      File('${fontDirectory.path}/$kGoldenFontLicenseFile').existsSync(),
      isTrue,
    );
    expect(
      File('${fontDirectory.path}/$kGoldenFontSourceFile').existsSync(),
      isTrue,
    );
  });

  test('golden font loader resolves the checked-in test/fonts directory', () {
    expect(
      resolveGoldenFontDirectory().path,
      '${Directory.current.path}/test/fonts',
    );
  });

  test('checked-in fonts match their pinned provenance and hashes', () {
    final Directory fontDirectory = resolveGoldenFontDirectory();
    final Map<String, Object?> source =
        jsonDecode(
              File(
                '${fontDirectory.path}/$kGoldenFontSourceFile',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(
      source['upstream_commit'],
      'f8d157532fbfaeda587e826d4cd5b21a49186f7c',
    );
    expect(source['fonttools_version'], '4.63.0');

    final List<Object?> outputs = source['subset_outputs']! as List<Object?>;
    expect(outputs, hasLength(2));
    for (final Object? raw in outputs) {
      final Map<String, Object?> output = raw! as Map<String, Object?>;
      final File file = File('${fontDirectory.path}/${output['path']}');
      expect(file.existsSync(), isTrue, reason: file.path);
      expect(file.lengthSync(), output['size'], reason: file.path);
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        output['sha256'],
        reason: file.path,
      );
    }

    final Map<String, Object?> license =
        source['license']! as Map<String, Object?>;
    final File licenseFile = File(
      '${fontDirectory.path}/$kGoldenFontLicenseFile',
    );
    expect(licenseFile.lengthSync(), license['size']);
    expect(
      sha256.convert(licenseFile.readAsBytesSync()).toString(),
      license['sha256'],
    );
  });

  test('golden tests do not reference repository-external font paths', () {
    for (final String relativePath in <String>[
      'test/m33_all_pages_visual_golden_test.dart',
      'test/video_runtime_visual_golden_test.dart',
    ]) {
      final String contents = File(
        '${Directory.current.path}/$relativePath',
      ).readAsStringSync();
      expect(contents.contains('../artifacts/m3-3/fonts'), isFalse);
      expect(contents.contains('/artifacts/m3-3/fonts'), isFalse);
    }
  });
}
