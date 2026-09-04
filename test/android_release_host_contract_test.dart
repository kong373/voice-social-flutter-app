import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Directory root = Directory.current;
  final File gradleBuild = File('${root.path}/android/app/build.gradle.kts');
  final File releaseManifest = File(
    '${root.path}/android/app/src/main/AndroidManifest.xml',
  );
  final File rootIgnore = File('${root.path}/.gitignore');
  final File androidIgnore = File('${root.path}/android/.gitignore');
  final File androidBuild = File('${root.path}/android/build.gradle.kts');
  final File gradleProperties = File('${root.path}/android/gradle.properties');
  final File releaseValidator = File(
    '${root.path}/tool/release/android_release_validator.sh',
  );
  final File releaseBuild = File(
    '${root.path}/tool/release/android_release_build.sh',
  );

  test('Android host files are present and intentionally trackable', () {
    const List<String> required = <String>[
      'android/.gitignore',
      'android/app/build.gradle.kts',
      'android/app/src/main/AndroidManifest.xml',
      'android/app/src/main/kotlin/com/kong373/voice_social_app/MainActivity.kt',
      'android/app/src/main/res/values/strings.xml',
      'android/build.gradle.kts',
      'android/gradle.properties',
      'android/gradle/wrapper/gradle-wrapper.jar',
      'android/gradle/wrapper/gradle-wrapper.properties',
      'android/gradlew',
      'android/gradlew.bat',
      'android/settings.gradle.kts',
    ];

    for (final String relativePath in required) {
      expect(
        File('${root.path}/$relativePath').existsSync(),
        isTrue,
        reason: 'missing Android host file: $relativePath',
      );
    }

    final List<String> rootIgnoreLines = rootIgnore
        .readAsLinesSync()
        .map((String line) => line.trim())
        .toList();
    expect(rootIgnoreLines, isNot(contains('android/')));

    expect(
      File(
        '${root.path}/android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync(),
      contains('android:label="@string/app_name"'),
    );
    expect(
      File(
        '${root.path}/android/app/src/main/res/values/strings.xml',
      ).readAsStringSync(),
      contains('<string name="app_name">Voice Social</string>'),
    );

    final List<String> androidIgnoreLines = androidIgnore
        .readAsLinesSync()
        .map((String line) => line.trim())
        .toList();
    expect(androidIgnoreLines, isNot(contains('/gradlew')));
    expect(androidIgnoreLines, isNot(contains('/gradlew.bat')));
    expect(androidIgnoreLines, isNot(contains('gradle-wrapper.jar')));
    expect(androidIgnoreLines, contains('/.gradle'));
    expect(androidIgnoreLines, contains('/build/'));
    expect(androidIgnoreLines, contains('/app/build/'));
    expect(androidIgnoreLines, contains('/local.properties'));
    expect(androidIgnoreLines, contains('GeneratedPluginRegistrant.java'));
    expect(androidIgnoreLines, contains('key.properties'));
    expect(androidIgnoreLines, contains('*.iml'));
    expect(rootIgnoreLines, contains('*.iml'));
    expect(rootIgnoreLines, contains('*.jks'));
    expect(rootIgnoreLines, contains('*.keystore'));

    const List<String> trackablePaths = <String>[
      'android/app/build.gradle.kts',
      'android/gradle/wrapper/gradle-wrapper.jar',
    ];
    for (final String path in trackablePaths) {
      final ProcessResult trackable = Process.runSync('git', <String>[
        'check-ignore',
        '--no-index',
        path,
      ], workingDirectory: root.path);
      expect(
        trackable.exitCode,
        isNot(0),
        reason: 'tracked Android host must not remain ignored: $path',
      );
    }

    const List<String> ignoredPaths = <String>[
      'android/.gradle',
      'android/build/reports/problems-report.html',
      'android/local.properties',
      'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
      'android/key.properties',
      'android/voice_social_app.iml',
    ];
    for (final String path in ignoredPaths) {
      final ProcessResult ignored = Process.runSync('git', <String>[
        'check-ignore',
        '--no-index',
        path,
      ], workingDirectory: root.path);
      expect(
        ignored.exitCode,
        0,
        reason: 'machine/generated Android file must stay ignored: $path',
      );
    }
  });

  test('release signing is explicit and never aliases the debug config', () {
    final String source = gradleBuild.readAsStringSync();
    expect(source, contains('ANDROID_RELEASE_SIGNING_PROPERTIES_FILE'));
    expect(source, contains('ANDROID_RELEASE_STORE_FILE'));
    expect(source, contains('ANDROID_RELEASE_STORE_PASSWORD'));
    expect(source, contains('ANDROID_RELEASE_KEY_ALIAS'));
    expect(source, contains('ANDROID_RELEASE_KEY_PASSWORD'));
    expect(source, contains('create("release")'));
    expect(
      source,
      contains('signingConfig = signingConfigs.getByName("release")'),
    );
    expect(source, contains('required release signing material'));
    expect(source, contains('validateReleaseSigning'));
    expect(source, contains('KeyStore'));
    expect(source, isNot(contains('signingConfigs.getByName("debug")')));
    expect(source, isNot(contains('signing with the debug keys')));
  });

  test('release manifest removes unused Agora video and phone surfaces', () {
    final String manifestSource = releaseManifest.readAsStringSync();
    expect(
      manifestSource,
      contains('xmlns:tools="http://schemas.android.com/tools"'),
    );
    for (final String permission in <String>[
      'android.permission.CAMERA',
      'android.permission.READ_PHONE_STATE',
      'android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION',
    ]) {
      expect(
        manifestSource,
        matches(
          RegExp(
            '<uses-permission(?:(?!<uses-permission).)*'
            'android:name="$permission"(?:(?!<uses-permission).)*'
            'tools:node="remove"',
            dotAll: true,
          ),
        ),
      );
    }
    for (final String component in <String>[
      'MediaProjectionMgr\$LocalScreenCaptureAssistantActivity',
      'MediaProjectionMgr\$LocalScreenSharingService',
    ]) {
      expect(
        manifestSource,
        contains('android:name="io.agora.rtc2.extensions.$component"'),
      );
    }

    final String validatorSource = releaseValidator.readAsStringSync();
    expect(validatorSource, contains('contains_forbidden_permission'));
    expect(validatorSource, contains('android.permission.READ_PHONE_STATE'));
    expect(
      validatorSource,
      contains('android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION'),
    );
    expect(validatorSource, contains('LocalScreenCaptureAssistantActivity'));
    expect(validatorSource, contains('LocalScreenSharingService'));
  });

  test(
    'AGP 9 compatibility workaround is explicit for the pinned Agora SDK',
    () {
      expect(
        gradleProperties.readAsStringSync(),
        contains('android.uniquePackageNames=false'),
      );
      expect(androidBuild.readAsStringSync(), contains('compileSdkVersion'));
      expect(
        androidBuild.readAsStringSync(),
        contains('extra["compileSdkVersion"] = 36'),
      );
    },
  );

  test(
    'release tooling validates both artifacts and rejects debug-only surfaces',
    () {
      expect(releaseValidator.existsSync(), isTrue);
      expect(releaseBuild.existsSync(), isTrue);
      expect(
        Process.runSync('bash', <String>[
          releaseValidator.path,
          '--self-test',
        ], workingDirectory: root.path).exitCode,
        0,
      );
      expect(
        Process.runSync('bash', <String>[
          releaseBuild.path,
          '--self-test',
        ], workingDirectory: root.path).exitCode,
        0,
      );

      final String validatorSource = releaseValidator.readAsStringSync();
      expect(validatorSource, contains('app-release.apk'));
      expect(validatorSource, contains('app-release.aab'));
      expect(validatorSource, contains('NativeAlipayIsolationActivity'));
      expect(validatorSource, contains('debug_only_surface_in_aab_code'));
      expect(validatorSource, contains('Android Debug'));
      expect(validatorSource, contains('jarsigner'));
      expect(validatorSource, contains('-verify -verbose -certs'));
      expect(validatorSource, contains('aab_signature_metadata_missing'));
      expect(validatorSource, contains(r'\.SF$'));
      expect(validatorSource, contains(r'\.(RSA|DSA|EC)$'));
      expect(validatorSource, contains('non_debuggable=PASS'));
      expect(validatorSource, contains('application-debuggable'));
      expect(
        validatorSource,
        contains('self_test_debug_certificate_not_detected'),
      );
      expect(
        validatorSource,
        contains('self_test_debuggable_marker_not_detected'),
      );
      expect(validatorSource, contains('sha256_file'));
      expect(validatorSource, contains('android/local.properties'));
      expect(validatorSource, contains('sdk\\.dir='));
      expect(
        releaseBuild.readAsStringSync(),
        contains('validateReleaseSigning'),
      );
      expect(releaseBuild.readAsStringSync(), contains('apk_sha256='));
      expect(releaseBuild.readAsStringSync(), contains('aab_sha256='));
      expect(
        releaseBuild.readAsStringSync(),
        contains('GENERATED_REGISTRANT_RELATIVE'),
      );
      expect(releaseBuild.readAsStringSync(), contains('git -C'));
      expect(
        releaseBuild.readAsStringSync(),
        contains('generated_registrant_is_not_ignored'),
      );
    },
  );

  test(
    'release and debug source sets keep the Alipay isolation activity debug-only',
    () {
      final File pluginDebugManifest = File(
        '${root.path}/packages/alipay_app_pay/android/src/debug/AndroidManifest.xml',
      );
      final File pluginMainManifest = File(
        '${root.path}/packages/alipay_app_pay/android/src/main/AndroidManifest.xml',
      );
      expect(
        pluginDebugManifest.readAsStringSync(),
        contains('NativeAlipayIsolationActivity'),
      );
      expect(
        pluginMainManifest.readAsStringSync(),
        isNot(contains('NativeAlipayIsolationActivity')),
      );
      expect(
        gradleBuild.readAsStringSync(),
        isNot(contains('NativeAlipayIsolationActivity')),
      );
    },
  );
}
