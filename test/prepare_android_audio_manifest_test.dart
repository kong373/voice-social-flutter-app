import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'audio manifest overlay adds microphone and removes video/phone permissions',
    () {
      final Directory root = Directory.systemTemp.createTempSync(
        'android-audio-manifest-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File manifest = File(
        '${root.path}/android/app/src/main/AndroidManifest.xml',
      )..createSync(recursive: true);
      final File androidBuild = File('${root.path}/android/build.gradle.kts')
        ..createSync(recursive: true);
      androidBuild.writeAsStringSync(
        'allprojects { repositories { google(); mavenCentral() } }',
      );
      final File properties = File('${root.path}/android/gradle.properties')
        ..createSync(recursive: true);
      properties.writeAsStringSync('android.useAndroidX=true\n');
      manifest.writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
        '<application /></manifest>',
      );

      final ProcessResult first = Process.runSync('python3', <String>[
        'tool/prepare_android_audio_manifest.py',
        root.path,
      ]);
      expect(first.exitCode, 0, reason: '${first.stdout}\n${first.stderr}');
      final String output = manifest.readAsStringSync();
      expect(
        output,
        contains('xmlns:tools="http://schemas.android.com/tools"'),
      );
      expect(output, contains('android.permission.RECORD_AUDIO'));
      expect(
        output,
        contains('android.permission.CAMERA" tools:node="remove"'),
      );
      expect(
        output,
        contains('android.permission.READ_PHONE_STATE" tools:node="remove"'),
      );
      expect(
        output,
        contains(
          'android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" '
          'tools:node="remove"',
        ),
      );
      expect(
        output,
        contains(
          'io.agora.rtc2.extensions.MediaProjectionMgr\$LocalScreenCaptureAssistantActivity" '
          'tools:node="remove"',
        ),
      );
      expect(
        output,
        contains(
          'io.agora.rtc2.extensions.MediaProjectionMgr\$LocalScreenSharingService" '
          'tools:node="remove"',
        ),
      );
      expect(
        androidBuild.readAsStringSync(),
        startsWith('rootProject.extra["compileSdkVersion"] = 36'),
      );
      expect(
        properties.readAsStringSync(),
        contains('android.uniquePackageNames=false'),
      );

      final ProcessResult second = Process.runSync('python3', <String>[
        'tool/prepare_android_audio_manifest.py',
        root.path,
      ]);
      expect(second.exitCode, 0, reason: '${second.stdout}\n${second.stderr}');
      final String rerun = manifest.readAsStringSync();
      expect(
        RegExp('android.permission.RECORD_AUDIO').allMatches(rerun),
        hasLength(1),
      );
      expect(
        RegExp(
          'android.permission.CAMERA" tools:node="remove"',
        ).allMatches(rerun),
        hasLength(1),
      );
      expect(
        RegExp(
          'FOREGROUND_SERVICE_MEDIA_PROJECTION" tools:node="remove"',
        ).allMatches(rerun),
        hasLength(1),
      );
      expect(
        RegExp(
          'LocalScreenCaptureAssistantActivity" tools:node="remove"',
        ).allMatches(rerun),
        hasLength(1),
      );
      expect(
        RegExp(
          'rootProject.extra\\["compileSdkVersion"\\] = 36',
        ).allMatches(androidBuild.readAsStringSync()),
        hasLength(1),
      );
      expect(
        RegExp(
          'android.uniquePackageNames=false',
        ).allMatches(properties.readAsStringSync()),
        hasLength(1),
      );
    },
  );

  test('audio manifest overlay patches a generated Groovy root build once', () {
    final Directory root = Directory.systemTemp.createTempSync(
      'android-audio-manifest-groovy-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File manifest = File(
      '${root.path}/android/app/src/main/AndroidManifest.xml',
    )..createSync(recursive: true);
    manifest.writeAsStringSync(
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
      '<application /></manifest>',
    );
    final File androidBuild = File('${root.path}/android/build.gradle')
      ..createSync(recursive: true);
    androidBuild.writeAsStringSync('allprojects { repositories {} }');

    final ProcessResult result = Process.runSync('python3', <String>[
      'tool/prepare_android_audio_manifest.py',
      root.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      androidBuild.readAsStringSync(),
      startsWith('ext {\n    compileSdkVersion = 36\n}'),
    );
  });

  test('audio manifest overlay replaces an unsafe package-name setting', () {
    final Directory root = Directory.systemTemp.createTempSync(
      'android-audio-manifest-properties-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File manifest = File(
      '${root.path}/android/app/src/main/AndroidManifest.xml',
    )..createSync(recursive: true);
    manifest.writeAsStringSync(
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
      '<application /></manifest>',
    );
    final File properties = File('${root.path}/android/gradle.properties')
      ..createSync(recursive: true);
    properties.writeAsStringSync(
      'android.uniquePackageNames=true\norg.gradle.jvmargs=-Xmx1g\n',
    );

    final ProcessResult result = Process.runSync('python3', <String>[
      'tool/prepare_android_audio_manifest.py',
      root.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      properties.readAsStringSync(),
      contains('android.uniquePackageNames=false'),
    );
    expect(
      RegExp(
        'android.uniquePackageNames=',
      ).allMatches(properties.readAsStringSync()),
      hasLength(1),
    );
  });

  test('audio manifest overlay fails closed for malformed hosts', () {
    final Directory root = Directory.systemTemp.createTempSync(
      'android-audio-manifest-bad-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File manifest = File(
      '${root.path}/android/app/src/main/AndroidManifest.xml',
    )..createSync(recursive: true);
    manifest.writeAsStringSync('<manifest>');

    final ProcessResult result = Process.runSync('python3', <String>[
      'tool/prepare_android_audio_manifest.py',
      root.path,
    ]);
    expect(result.exitCode, isNonZero);
  });
}
