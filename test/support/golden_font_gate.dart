import 'dart:io';

import 'package:flutter/services.dart';

const String kGoldenFontFamily = 'M3GoldenCjk';
const String kGoldenRegularFontFile = 'M3GoldenCjkRegular.otf';
const String kGoldenBoldFontFile = 'M3GoldenCjkBold.otf';
const String kGoldenFontLicenseFile = 'OFL.txt';
const String kGoldenFontSourceFile = 'SOURCE.txt';

Directory resolveGoldenFontDirectory() {
  return Directory('${Directory.current.path}/test/fonts');
}

Future<void> loadGoldenFonts({Directory? goldenFontDirectory}) async {
  final Directory fontDirectory =
      goldenFontDirectory ?? resolveGoldenFontDirectory();
  final File regularFont = File(
    '${fontDirectory.path}/$kGoldenRegularFontFile',
  );
  final File boldFont = File('${fontDirectory.path}/$kGoldenBoldFontFile');

  if (!regularFont.existsSync()) {
    throw StateError(
      'M3.3 golden font gate failed: missing the checked-in CJK baseline font '
      'at ${regularFont.path}. Golden tests fail closed and never fall back to '
      'repository-external font directories.',
    );
  }
  if (!boldFont.existsSync()) {
    throw StateError(
      'M3.3 golden font gate failed: missing the checked-in bold CJK font '
      'at ${boldFont.path}.',
    );
  }

  final Uint8List regularBytes = _readGoldenFontBytes(regularFont, 'CJK');
  final Uint8List boldBytes = _readGoldenFontBytes(boldFont, 'bold CJK');
  final FontLoader loader = FontLoader(kGoldenFontFamily)
    ..addFont(
      Future<ByteData>.value(
        regularBytes.buffer.asByteData(
          regularBytes.offsetInBytes,
          regularBytes.lengthInBytes,
        ),
      ),
    )
    ..addFont(
      Future<ByteData>.value(
        boldBytes.buffer.asByteData(
          boldBytes.offsetInBytes,
          boldBytes.lengthInBytes,
        ),
      ),
    );
  try {
    await loader.load();
  } on Object catch (error) {
    throw StateError(
      'M3.3 golden font gate failed: could not load the checked-in CJK fonts '
      'from ${fontDirectory.path}: $error',
    );
  }

  final Directory flutterRoot = File(
    Platform.resolvedExecutable,
  ).parent.parent.parent.parent.parent.parent;
  final File iconFont = File(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!iconFont.existsSync()) {
    throw StateError(
      'M3.3 golden font gate failed: missing the Flutter MaterialIcons font '
      'at ${iconFont.path}.',
    );
  }
  final Uint8List iconBytes = _readGoldenFontBytes(iconFont, 'MaterialIcons');
  final FontLoader iconLoader = FontLoader('MaterialIcons')
    ..addFont(
      Future<ByteData>.value(
        iconBytes.buffer.asByteData(
          iconBytes.offsetInBytes,
          iconBytes.lengthInBytes,
        ),
      ),
    );
  try {
    await iconLoader.load();
  } on Object catch (error) {
    throw StateError(
      'M3.3 golden font gate failed: could not load the Flutter MaterialIcons '
      'font from ${iconFont.path}: $error',
    );
  }
}

Uint8List _readGoldenFontBytes(File font, String label) {
  try {
    return font.readAsBytesSync();
  } on Object catch (error) {
    throw StateError(
      'M3.3 golden font gate failed: could not read the $label font '
      'from ${font.path}: $error',
    );
  }
}
