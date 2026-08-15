import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final String outputDirectory =
      Platform.environment['QA_SCREENSHOT_DIR'] ??
      'artifacts/qa/m2.4-emulator/screenshots';
  await integrationDriver(
    onScreenshot:
        (
          String screenshotName,
          List<int> screenshotBytes, [
          Map<String, Object?>? args,
        ]) async {
          final Directory directory = Directory(outputDirectory);
          await directory.create(recursive: true);
          final String safeName = screenshotName.replaceAll(
            RegExp(r'[^A-Za-z0-9_.-]'),
            '_',
          );
          await File(
            '${directory.path}/$safeName.png',
          ).writeAsBytes(screenshotBytes, flush: true);
          return true;
        },
  );
}
