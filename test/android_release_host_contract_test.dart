import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
  final File releaseConfigValidator = File(
    '${root.path}/tool/release/android_release_config_validator.py',
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

  test('launcher icons use the frozen Voice Social brand source', () {
    final File master = File(
      '${root.path}/assets/branding/voice-social-app-icon-1024.png',
    );
    expect(master.existsSync(), isTrue);
    expect(
      sha256.convert(master.readAsBytesSync()).toString(),
      '515e50dc2863b8d59c9e757ce5b90ae53fcdefde69cb6683fba0a17ac0ad6bd4',
    );
    expect(pngDimensions(master), (1024, 1024));

    const Map<String, ({int size, String flutterDefaultSha})>
    icons = <String, ({int size, String flutterDefaultSha})>{
      'mipmap-mdpi': (
        size: 48,
        flutterDefaultSha:
            'c7c0c0189145e4e32a401c61c9bdc615754b0264e7afae24e834bb81049eaf81',
      ),
      'mipmap-hdpi': (
        size: 72,
        flutterDefaultSha:
            '6a7c8f0d703e3682108f9662f813302236240d3f8f638bb391e32bfb96055fef',
      ),
      'mipmap-xhdpi': (
        size: 96,
        flutterDefaultSha:
            'e14aa40904929bf313fded22cf7e7ffcbf1d1aac4263b5ef1be8bfce650397aa',
      ),
      'mipmap-xxhdpi': (
        size: 144,
        flutterDefaultSha:
            '4d470bf22d5c17d84edc5f82516d1ba8a1c09559cd761cefb792f86d9f52b540',
      ),
      'mipmap-xxxhdpi': (
        size: 192,
        flutterDefaultSha:
            '3c34e1f298d0c9ea3455d46db6b7759c8211a49e9ec6e44b635fc5c87dfb4180',
      ),
    };
    for (final MapEntry<String, ({int size, String flutterDefaultSha})> entry
        in icons.entries) {
      final File icon = File(
        '${root.path}/android/app/src/main/res/${entry.key}/ic_launcher.png',
      );
      expect(icon.existsSync(), isTrue);
      expect(pngDimensions(icon), (entry.value.size, entry.value.size));
      expect(
        sha256.convert(icon.readAsBytesSync()).toString(),
        isNot(entry.value.flutterDefaultSha),
      );
    }
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
      expect(releaseConfigValidator.existsSync(), isTrue);
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
      expect(releaseBuild.readAsStringSync(), contains('--config-file'));
      expect(
        releaseBuild.readAsStringSync(),
        contains('android_release_config_validator.py'),
      );
      expect(
        releaseBuild.readAsStringSync(),
        contains(r'--dart-define-from-file="$CONFIG_SNAPSHOT"'),
      );
      expect(releaseBuild.readAsStringSync(), contains('mktemp -d'));
      expect(releaseBuild.readAsStringSync(), contains('chmod 700'));
      expect(releaseConfigValidator.readAsStringSync(), contains('O_EXCL'));
      expect(releaseConfigValidator.readAsStringSync(), contains('0o600'));
      expect(
        releaseConfigValidator.readAsStringSync(),
        contains('object_pairs_hook'),
      );
    },
  );

  test('release config rejects before fake Gradle or Flutter can run', () {
    final _ReleaseBuildFixture fixture = _createReleaseBuildFixture(root);
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final ProcessResult missingConfig = _runReleaseBuild(
      fixture,
      includeConfig: false,
    );
    expect(missingConfig.exitCode, isNot(0));
    expect(missingConfig.stderr, contains('config_file_required'));
    expect(_eventLog(fixture), isEmpty);

    final ProcessResult missingFile = _runReleaseBuild(fixture);
    expect(missingFile.exitCode, isNot(0));
    expect(missingFile.stderr, contains('config_missing'));
    expect(_eventLog(fixture), isEmpty);

    final List<({String name, Map<String, Object?> config, String? secret})>
    invalidConfigs =
        <({String name, Map<String, Object?> config, String? secret})>[
          (
            name: 'invalid environment',
            config: _validReleaseConfig(appEnv: 'development'),
            secret: null,
          ),
          (
            name: 'insecure HTTP origin',
            config: _validReleaseConfig(
              apiBaseUrl: 'http://public.example.test/',
            ),
            secret: null,
          ),
          (
            name: 'userinfo in HTTPS origin',
            config: _validReleaseConfig(
              apiBaseUrl: 'https://public:password@public.example.test/',
            ),
            secret: null,
          ),
          (
            name: 'query in HTTPS origin',
            config: _validReleaseConfig(
              apiBaseUrl: 'https://public.example.test/?probe=1',
            ),
            secret: null,
          ),
          (
            name: 'fragment in HTTPS origin',
            config: _validReleaseConfig(
              apiBaseUrl: 'https://public.example.test/#fragment',
            ),
            secret: null,
          ),
          (
            name: 'authority-prefixed live probe path',
            config: <String, Object?>{
              ..._validReleaseConfig(),
              'LIVE_PROBE_PATH': '//attacker.example/health',
            },
            secret: null,
          ),
          (
            name: 'secret field',
            config: <String, Object?>{
              ..._validReleaseConfig(),
              'OAUTH_CLIENT_SECRET': 'do-not-print-this-secret',
            },
            secret: 'do-not-print-this-secret',
          ),
          (
            name: 'insecure HTTP flag',
            config: <String, Object?>{
              ..._validReleaseConfig(),
              'ALLOW_INSECURE_HTTP': true,
            },
            secret: null,
          ),
          (
            name: 'formal Alipay acceptance flag',
            config: <String, Object?>{
              ..._validReleaseConfig(),
              'ALIPAY_FORMAL_ACCEPTANCE': true,
            },
            secret: null,
          ),
          (
            name: 'Apple IAP flag',
            config: <String, Object?>{
              ..._validReleaseConfig(),
              'ENABLE_APPLE_IAP': true,
            },
            secret: null,
          ),
        ];

    for (final ({String name, Map<String, Object?> config, String? secret})
        invalid
        in invalidConfigs) {
      _writeConfig(fixture.config, jsonEncode(invalid.config));
      _clearEvents(fixture);
      final ProcessResult result = _runReleaseBuild(fixture);
      expect(result.exitCode, isNot(0), reason: invalid.name);
      expect(_eventLog(fixture), isEmpty, reason: invalid.name);
      if (invalid.secret != null) {
        expect(
          '${result.stdout}\n${result.stderr}',
          isNot(contains(invalid.secret!)),
          reason: invalid.name,
        );
      }
    }
  });

  test('release config rejects duplicate keys and symlink files', () {
    final _ReleaseBuildFixture fixture = _createReleaseBuildFixture(root);
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    _writeConfig(
      fixture.config,
      '{"APP_ENV":"staging","APP_ENV":"production",'
      '"BACKEND_MODE":"live","API_BASE_URL":"https://public.example.test/",'
      '"OAUTH_CLIENT_ID":"voice-social-mobile-public","CLIENT_TYPE":"Android"}',
    );
    final ProcessResult duplicate = _runReleaseBuild(fixture);
    expect(duplicate.exitCode, isNot(0));
    expect(_eventLog(fixture), isEmpty);

    final File realConfig = File('${fixture.root.path}/real-config.json');
    _writeConfig(realConfig, jsonEncode(_validReleaseConfig()));
    final Link configLink = Link(fixture.config.path);
    if (configLink.existsSync()) {
      configLink.deleteSync();
    } else if (fixture.config.existsSync()) {
      fixture.config.deleteSync();
    }
    configLink.createSync(realConfig.path);
    _clearEvents(fixture);
    final ProcessResult symlink = _runReleaseBuild(fixture);
    expect(symlink.exitCode, isNot(0));
    expect(_eventLog(fixture), isEmpty);
  });

  test(
    'one validated snapshot survives public config replacement in both builds',
    () {
      final _ReleaseBuildFixture fixture = _createReleaseBuildFixture(root);
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      _writeConfig(fixture.config, jsonEncode(_validReleaseConfig()));

      final ProcessResult result = _runReleaseBuild(fixture);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      final List<String> events = _eventLog(fixture).split('\n');
      final List<String> flutterEvents = events
          .where((String line) => line.startsWith('flutter '))
          .toList();
      expect(flutterEvents, hasLength(2));
      expect(flutterEvents[0], contains('build apk'));
      expect(flutterEvents[1], contains('build appbundle'));
      for (final String event in flutterEvents) {
        expect(event, contains('--dart-define-from-file='));
        expect(event, isNot(contains(fixture.config.path)));
      }
      final List<String> snapshotEvents = events
          .where((String line) => line.startsWith('flutter-config-hash '))
          .toList();
      expect(snapshotEvents, hasLength(2));
      expect(
        snapshotEvents[0],
        matches(
          RegExp(r'^flutter-config-hash [0-9a-f]{64} mode=600 parent=700$'),
        ),
      );
      expect(snapshotEvents[0], snapshotEvents[1]);
      expect(events, contains('gradle-overwrite'));
      expect(events, contains('apk-overwrite'));
      final Map<String, Object?> replacedConfig =
          jsonDecode(fixture.config.readAsStringSync()) as Map<String, Object?>;
      expect(replacedConfig['APP_ENV'], 'production');
      expect(replacedConfig['BACKEND_MODE'], 'offline');
      expect(events.indexWhere((String line) => line.startsWith('gradle ')), 0);
      expect(
        events.indexWhere((String line) => line.startsWith('validator ')),
        greaterThan(0),
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

class _ReleaseBuildFixture {
  _ReleaseBuildFixture({
    required this.root,
    required this.build,
    required this.config,
    required this.events,
    required this.flutter,
  });

  final Directory root;
  final File build;
  final File config;
  final File events;
  final File flutter;
}

_ReleaseBuildFixture _createReleaseBuildFixture(Directory sourceRoot) {
  final Directory sandbox = Directory.systemTemp.createTempSync(
    'android-release-contract-',
  );
  final Directory releaseDirectory = Directory('${sandbox.path}/tool/release')
    ..createSync(recursive: true);
  Directory('${sandbox.path}/android').createSync(recursive: true);

  final File build = File('${releaseDirectory.path}/android_release_build.sh');
  File(
    '${sourceRoot.path}/tool/release/android_release_build.sh',
  ).copySync(build.path);
  File(
    '${sourceRoot.path}/tool/release/android_release_config_validator.py',
  ).copySync('${releaseDirectory.path}/android_release_config_validator.py');

  final File events = File('${sandbox.path}/events.log');
  final File validator = File(
    '${releaseDirectory.path}/android_release_validator.sh',
  );
  validator.writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
printf 'validator %s\n' "$*" >> "${EVENTS:?}"
''');
  _makeExecutable(validator);

  final File gradle = File('${sandbox.path}/android/gradlew');
  gradle.writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
printf 'gradle %s\n' "$*" >> "${EVENTS:?}"
printf '{"APP_ENV":"development","BACKEND_MODE":"debug"}\n' > "${ORIGINAL_CONFIG:?}"
printf 'gradle-overwrite\n' >> "${EVENTS:?}"
''');
  _makeExecutable(gradle);

  final File flutter = File('${sandbox.path}/fake-flutter');
  flutter.writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
printf 'flutter %s\n' "$*" >> "${EVENTS:?}"
config_file=''
for arg in "$@"; do
  case "$arg" in
    --dart-define-from-file=*) config_file="${arg#*=}" ;;
  esac
done
[[ -n "$config_file" ]]
config_facts="$(python3 - "$config_file" <<'PY'
import hashlib
import json
import os
import stat
import sys

path = sys.argv[1]
with open(path, 'rb') as snapshot_file:
    raw = snapshot_file.read()
config = json.loads(raw)
if (
    config.get('APP_ENV') != 'staging'
    or config.get('BACKEND_MODE') != 'live'
    or 'OAUTH_CLIENT_SECRET' in config
    or stat.S_IMODE(os.stat(path).st_mode) != 0o600
    or stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode) != 0o700
):
    raise SystemExit('unsafe_snapshot')
print(f"{hashlib.sha256(raw).hexdigest()} mode=600 parent=700")
PY
)"
printf 'flutter-config-hash %s\n' "$config_facts" >> "${EVENTS:?}"
case "${2:-}" in
  apk)
    printf '{"APP_ENV":"production","BACKEND_MODE":"offline"}\n' > "${ORIGINAL_CONFIG:?}"
    printf 'apk-overwrite\n' >> "${EVENTS:?}"
    mkdir -p build/app/outputs/flutter-apk
    printf 'fake apk\n' > build/app/outputs/flutter-apk/app-release.apk
    ;;
  appbundle)
    mkdir -p build/app/outputs/bundle/release
    printf 'fake aab\n' > build/app/outputs/bundle/release/app-release.aab
    ;;
  *)
    exit 2
    ;;
esac
''');
  _makeExecutable(flutter);

  final File config = File('${sandbox.path}/config.json');
  return _ReleaseBuildFixture(
    root: sandbox,
    build: build,
    config: config,
    events: events,
    flutter: flutter,
  );
}

Map<String, Object?> _validReleaseConfig({
  String appEnv = 'staging',
  String apiBaseUrl = 'https://public.example.test/',
}) {
  return <String, Object?>{
    'APP_ENV': appEnv,
    'BACKEND_MODE': 'live',
    'API_BASE_URL': apiBaseUrl,
    'OAUTH_CLIENT_ID': 'voice-social-mobile-public',
    'CLIENT_TYPE': 'Android',
    'CLIENT_INNER_VERSION': '1',
    'API_TIMEOUT_SECONDS': 15,
    'LIVE_PROBE_PATH': '/',
    'ALLOW_INSECURE_HTTP': false,
    'ENABLE_AGORA_RTC': false,
    'ENABLE_ALIPAY_APP_PAY': false,
    'ALIPAY_FORMAL_ACCEPTANCE': false,
    'ENABLE_APPLE_IAP': false,
    'ENABLE_TENCENT_IM': false,
  };
}

void _writeConfig(File config, String contents) {
  config.parent.createSync(recursive: true);
  config.writeAsStringSync(contents);
}

void _clearEvents(_ReleaseBuildFixture fixture) {
  if (fixture.events.existsSync()) {
    fixture.events.writeAsStringSync('');
  }
}

String _eventLog(_ReleaseBuildFixture fixture) {
  return fixture.events.existsSync() ? fixture.events.readAsStringSync() : '';
}

ProcessResult _runReleaseBuild(
  _ReleaseBuildFixture fixture, {
  bool includeConfig = true,
}) {
  final Map<String, String> environment = <String, String>{
    ...Platform.environment,
    'EVENTS': fixture.events.path,
    'ORIGINAL_CONFIG': fixture.config.path,
  };
  return Process.runSync(
    'bash',
    <String>[
      fixture.build.path,
      if (includeConfig) ...<String>['--config-file', fixture.config.path],
      '--flutter-bin',
      fixture.flutter.path,
    ],
    workingDirectory: fixture.root.path,
    environment: environment,
  );
}

void _makeExecutable(File file) {
  final ProcessResult result = Process.runSync('chmod', <String>[
    '700',
    file.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Unable to make contract fixture executable: ${file.path}',
    );
  }
}

(int, int) pngDimensions(File file) {
  final Uint8List bytes = file.readAsBytesSync();
  if (bytes.length < 24 ||
      bytes[0] != 0x89 ||
      bytes[1] != 0x50 ||
      bytes[2] != 0x4e ||
      bytes[3] != 0x47) {
    throw StateError('Not a PNG: ${file.path}');
  }
  final ByteData data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}
