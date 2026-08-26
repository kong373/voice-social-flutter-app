import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fakeFlutterBin;
  late File fakeFlutterLog;
  late File fakeFlutterEnvLog;
  late File fakeFlutterVersionConfig;
  late File fakeFlutterBehaviorConfig;
  late File fakeFlutterHostLog;
  late Directory liveArtifactDirectory;
  late File liveArtifact;
  late File liveArtifactHash;
  late bool liveArtifactDirectoryExisted;
  late bool liveArtifactDirectoryRemovedForTest;
  late List<int>? preservedArtifactBytes;
  late String? preservedArtifactHash;

  setUp(() {
    fakeFlutterBin = Directory.systemTemp.createTempSync('live-dev-flutter-');
    fakeFlutterLog = File('${fakeFlutterBin.path}/invocation.log');
    fakeFlutterEnvLog = File('${fakeFlutterBin.path}/environment.log');
    fakeFlutterVersionConfig = File('${fakeFlutterBin.path}/version.config');
    fakeFlutterBehaviorConfig = File('${fakeFlutterBin.path}/behavior.config')
      ..writeAsStringSync('success\n');
    fakeFlutterHostLog = File('${fakeFlutterBin.path}/android-host.log');
    liveArtifactDirectory = Directory('build/live-development');
    liveArtifact = File('${liveArtifactDirectory.path}/app-debug.apk');
    liveArtifactHash = File(
      '${liveArtifactDirectory.path}/app-debug.apk.sha256',
    );
    final FileSystemEntityType artifactDirectoryType =
        FileSystemEntity.typeSync(
          liveArtifactDirectory.path,
          followLinks: false,
        );
    if (artifactDirectoryType != FileSystemEntityType.notFound &&
        artifactDirectoryType != FileSystemEntityType.directory) {
      throw StateError('live artifact path must be a real directory');
    }
    liveArtifactDirectoryExisted =
        artifactDirectoryType == FileSystemEntityType.directory;
    liveArtifactDirectoryRemovedForTest = false;
    preservedArtifactBytes = liveArtifact.existsSync()
        ? liveArtifact.readAsBytesSync()
        : null;
    preservedArtifactHash = liveArtifactHash.existsSync()
        ? liveArtifactHash.readAsStringSync()
        : null;
    if (liveArtifact.existsSync()) {
      liveArtifact.deleteSync();
    }
    if (liveArtifactHash.existsSync()) {
      liveArtifactHash.deleteSync();
    }
    if (liveArtifactDirectoryExisted &&
        liveArtifactDirectory.listSync().isEmpty) {
      liveArtifactDirectory.deleteSync();
      liveArtifactDirectoryRemovedForTest = true;
    }
    fakePath = fakeFlutterBin.path;
    fakeLogPath = fakeFlutterLog.path;
    fakeFlutterEnvLogPath = fakeFlutterEnvLog.path;
    fakeVersionConfigPath = fakeFlutterVersionConfig.path;
    fakeHostLogPath = fakeFlutterHostLog.path;
    final File fakeFlutter = File('${fakeFlutterBin.path}/flutter');
    fakeFlutter.writeAsStringSync('''#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1-}" == "--version" && "\${2-}" == "--machine" ]]; then
  version_line='3.44.7|3.12.2'
  if [[ -f "${fakeFlutterVersionConfig.path}" ]]; then
    IFS= read -r version_line < "${fakeFlutterVersionConfig.path}"
  fi
  IFS='|' read -r framework_version dart_version <<< "\$version_line"
  printf '{"frameworkVersion":"%s","dartSdkVersion":"%s"}\\n' "\$framework_version" "\$dart_version"
  exit 0
fi
if [[ "\${1-}" == "create" ]]; then
  host="\${@: -1}"
  mkdir -p "\$host/android/app/src/main"
  cat > "\$host/android/app/src/main/AndroidManifest.xml" <<'MANIFEST'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application />
</manifest>
MANIFEST
  printf '%s\\n' "\$host" > "${fakeFlutterHostLog.path}"
  exit 0
fi
if [[ "\${1-}" == "pub" ]]; then
  exit 0
fi
if [[ "\${1-}" == "build" && "\${2-}" == "apk" ]]; then
  build_behavior='success'
  if [[ -f "${fakeFlutterBehaviorConfig.path}" ]]; then
    IFS= read -r build_behavior < "${fakeFlutterBehaviorConfig.path}"
  fi
  if [[ "\$build_behavior" == 'fail' ]]; then
    exit 17
  fi
  if [[ "\$build_behavior" != 'missing-apk' ]]; then
    mkdir -p build/app/outputs/flutter-apk
    printf 'fake-live-debug-apk\n' > build/app/outputs/flutter-apk/app-debug.apk
  fi
fi
if [[ -f android/app/src/main/AndroidManifest.xml ]]; then
  printf 'manifest=%s\\n' "\$(tr -d '[:space:]' < android/app/src/main/AndroidManifest.xml)" >> "${fakeFlutterHostLog.path}"
fi
printf '%s\\n' "\$@" > "${fakeFlutterLog.path}"
printf 'HOST_TOOL_TOKEN=%s\\n' "\${HOST_TOOL_TOKEN-<unset>}" > "${fakeFlutterEnvLog.path}"
printf 'access_token=%s\\n' "\${access_token-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'Access_Token=%s\\n' "\${Access_Token-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'MiXeD_TOkEn=%s\\n' "\${MiXeD_TOkEn-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'AWS_PROFILE=%s\\n' "\${AWS_PROFILE-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'KUBECONFIG=%s\\n' "\${KUBECONFIG-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'SSH_AUTH_SOCK=%s\\n' "\${SSH_AUTH_SOCK-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'PATH=%s\\n' "\${PATH-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'HOME=%s\\n' "\${HOME-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'JAVA_HOME=%s\\n' "\${JAVA_HOME-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'ANDROID_HOME=%s\\n' "\${ANDROID_HOME-<unset>}" >> "${fakeFlutterEnvLog.path}"
printf 'ANDROID_SDK_ROOT=%s\\n' "\${ANDROID_SDK_ROOT-<unset>}" >> "${fakeFlutterEnvLog.path}"
''');
    Process.runSync('chmod', <String>['+x', fakeFlutter.path]);
  });

  tearDown(() {
    if (fakeFlutterBin.existsSync()) {
      fakeFlutterBin.deleteSync(recursive: true);
    }
    fakePath = null;
    fakeLogPath = null;
    fakeFlutterEnvLogPath = null;
    fakeVersionConfigPath = null;
    fakeHostLogPath = null;
    if (liveArtifact.existsSync()) {
      liveArtifact.deleteSync();
    }
    if (liveArtifactHash.existsSync()) {
      liveArtifactHash.deleteSync();
    }
    final FileSystemEntityType artifactDirectoryType =
        FileSystemEntity.typeSync(
          liveArtifactDirectory.path,
          followLinks: false,
        );
    if (!liveArtifactDirectoryExisted) {
      if (artifactDirectoryType == FileSystemEntityType.link) {
        Link(liveArtifactDirectory.path).deleteSync();
      } else if (artifactDirectoryType == FileSystemEntityType.file) {
        File(liveArtifactDirectory.path).deleteSync();
      }
    }
    if (preservedArtifactBytes case final List<int> bytes) {
      liveArtifactDirectory.createSync(recursive: true);
      liveArtifact.writeAsBytesSync(bytes);
    }
    if (preservedArtifactHash case final String hash) {
      liveArtifactDirectory.createSync(recursive: true);
      liveArtifactHash.writeAsStringSync(hash);
    }
    if (liveArtifactDirectoryRemovedForTest &&
        !liveArtifactDirectory.existsSync()) {
      liveArtifactDirectory.createSync(recursive: true);
    } else if (!liveArtifactDirectoryExisted &&
        liveArtifactDirectory.existsSync() &&
        liveArtifactDirectory.listSync().isEmpty) {
      liveArtifactDirectory.deleteSync();
    }
  });

  test('help describes the two supported live-development entry points', () {
    final ProcessResult result = _run(<String>['help']);

    expect(result.exitCode, 0);
    expect(result.stdout, contains('run'));
    expect(result.stdout, contains('build-apk'));
    expect(result.stdout, contains('10.0.2.2'));
    expect(result.stdout, contains('127.0.0.1'));
  });

  test('run fails before Flutter when API_BASE_URL is missing', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment()..remove('API_BASE_URL'));

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('API_BASE_URL is required'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('target rejects a host URL for the Android emulator', () {
    final ProcessResult result = _run(
      <String>['run', '--target', 'android-emulator'],
      environment: _baseEnvironment()
        ..['API_BASE_URL'] = 'http://127.0.0.1:18080/',
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('10.0.2.2'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test(
    'target selection is required instead of guessing the network namespace',
    () {
      final ProcessResult result = _run(<String>[
        'run',
      ], environment: _baseEnvironment());

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('--target is required'));
      expect(fakeFlutterLog.existsSync(), isFalse);
    },
  );

  test('run passes only live public-client defines to Flutter', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--device',
      'emulator-5554',
    ], environment: _baseEnvironment());

    expect(result.exitCode, 0);
    final String invocation = fakeFlutterLog.readAsStringSync();
    expect(invocation, contains('run'));
    expect(invocation, contains('-d'));
    expect(invocation, contains('emulator-5554'));
    expect(invocation, contains('--dart-define=BACKEND_MODE=live'));
    expect(invocation, contains('--dart-define=APP_ENV=development'));
    expect(invocation, contains('--dart-define=ENABLE_QA_CONSOLE=false'));
    expect(
      invocation,
      contains('--dart-define=ENABLE_VIDEO_RUNTIME_DEMO=false'),
    );
    expect(invocation, contains('--dart-define=ENABLE_AGORA_RTC=false'));
    expect(
      invocation,
      contains('--dart-define=API_BASE_URL=http://10.0.2.2:18080/'),
    );
    expect(invocation, contains('--dart-define=OAUTH_CLIENT_ID=public-client'));
    expect(invocation, isNot(contains('SECRET')));
    expect(invocation, isNot(contains('PASSWORD')));
  });

  test('explicit Agora switch passes exactly the public enable define', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--device',
      'emulator-5554',
      '--enable-agora-rtc',
    ], environment: _baseEnvironment());

    expect(result.exitCode, 0);
    final List<String> invocationLines = fakeFlutterLog
        .readAsStringSync()
        .trim()
        .split('\n');
    expect(invocationLines, contains('--dart-define=ENABLE_AGORA_RTC=true'));
    expect(
      invocationLines,
      isNot(contains('--dart-define=ENABLE_AGORA_RTC=false')),
    );
    expect(
      invocationLines.where(
        (String line) => line.startsWith('--dart-define=ENABLE_AGORA_RTC='),
      ),
      hasLength(1),
    );
  });

  test('run rejects a Flutter SDK other than the frozen 3.44.7', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--device',
      'emulator-5554',
    ], environment: _baseEnvironment()..['FAKE_FLUTTER_VERSION'] = '3.45.0');

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Flutter 3.44.7'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('run rejects a Dart SDK other than the frozen 3.12.2', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--device',
      'emulator-5554',
    ], environment: _baseEnvironment()..['FAKE_DART_VERSION'] = '3.13.0');

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Dart 3.12.2'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('run requires an explicit device for the Android emulator target', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment());

    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('android-emulator target requires --device'),
    );
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('run requires an explicit device for the host target', () {
    final ProcessResult result = _run(
      <String>['run', '--target', 'host'],
      environment: _baseEnvironment()
        ..['API_BASE_URL'] = 'http://127.0.0.1:18080/',
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('host target requires --device'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('build-apk rejects a Flutter SDK other than the frozen 3.44.7', () {
    final ProcessResult result = _run(<String>[
      'build-apk',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment()..['FAKE_FLUTTER_VERSION'] = '3.45.0');

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Flutter 3.44.7'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('build-apk rejects a Dart SDK other than the frozen 3.12.2', () {
    final ProcessResult result = _run(<String>[
      'build-apk',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment()..['FAKE_DART_VERSION'] = '3.13.0');

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Dart 3.12.2'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test(
    'build-apk rejects the host target before Flutter can bake 127.0.0.1',
    () {
      final ProcessResult result = _run(
        <String>['build-apk', '--target', 'host', '--dry-run'],
        environment: _baseEnvironment()
          ..['API_BASE_URL'] = 'http://127.0.0.1:18080/',
      );

      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('build-apk only supports android-emulator'),
      );
      expect(fakeFlutterLog.existsSync(), isFalse);
    },
  );

  test(
    'build dry-run identifies the Android Emulator target without invoking Flutter',
    () {
      final ProcessResult result = _run(<String>[
        'build-apk',
        '--target',
        'android-emulator',
        '--dry-run',
      ], environment: _baseEnvironment());

      expect(result.exitCode, 0);
      expect(result.stdout, contains('target=android-emulator'));
      expect(result.stdout, contains('api_origin=http://10.0.2.2:18080'));
      expect(result.stdout, contains('flutter build apk --debug'));
      expect(fakeFlutterLog.existsSync(), isFalse);
      expect(liveArtifact.existsSync(), isFalse);
      expect(liveArtifactHash.existsSync(), isFalse);
    },
  );

  test('successful build retains the APK and SHA-256 after wrapper exit', () {
    final ProcessResult result = _run(<String>[
      'build-apk',
      '--target',
      'android-emulator',
      '--enable-agora-rtc',
    ], environment: _baseEnvironment());

    expect(result.exitCode, 0);
    expect(liveArtifact.existsSync(), isTrue);
    expect(liveArtifactHash.existsSync(), isTrue);
    expect(liveArtifact.readAsStringSync(), 'fake-live-debug-apk\n');
    final String digest = sha256
        .convert(liveArtifact.readAsBytesSync())
        .toString();
    expect(liveArtifactHash.readAsStringSync(), '$digest  app-debug.apk\n');
    expect(
      result.stdout,
      contains('live_apk_path=${liveArtifact.absolute.path}'),
    );
    expect(result.stdout, contains('live_apk_sha256=$digest'));
  });

  test('failed build leaves no retained APK or SHA-256', () {
    liveArtifactDirectory.createSync(recursive: true);
    liveArtifact.writeAsStringSync('stale-apk');
    liveArtifactHash.writeAsStringSync('stale-hash');
    fakeFlutterBehaviorConfig.writeAsStringSync('fail\n');

    final ProcessResult result = _run(<String>[
      'build-apk',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment());

    expect(result.exitCode, isNot(0));
    expect(liveArtifact.existsSync(), isFalse);
    expect(liveArtifactHash.existsSync(), isFalse);
  });

  test('build rejects a symbolic-link artifact output directory', () {
    final Directory linkTarget = Directory.systemTemp.createTempSync(
      'live-apk-link-target-',
    );
    addTearDown(() {
      if (linkTarget.existsSync()) {
        linkTarget.deleteSync(recursive: true);
      }
    });
    Link(liveArtifactDirectory.path).createSync(linkTarget.path);

    final ProcessResult result = _run(<String>[
      'build-apk',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment());

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('must be a real directory'));
    expect(fakeFlutterLog.existsSync(), isFalse);
    expect(linkTarget.listSync(), isEmpty);
  });

  test('build rejects a non-directory artifact output parent', () {
    File(liveArtifactDirectory.path)
      ..createSync(recursive: true)
      ..writeAsStringSync('not-a-directory');

    final ProcessResult result = _run(<String>[
      'build-apk',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment());

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('must be a real directory'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('missing Flutter APK fails closed without retained output', () {
    fakeFlutterBehaviorConfig.writeAsStringSync('missing-apk\n');

    final ProcessResult result = _run(<String>[
      'build-apk',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment());

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('expected Flutter APK was not produced'));
    expect(liveArtifact.existsSync(), isFalse);
    expect(liveArtifactHash.existsSync(), isFalse);
  });

  test(
    'build-apk passes only live public-client defines without a device flag',
    () {
      final ProcessResult result = _run(<String>[
        'build-apk',
        '--target',
        'android-emulator',
      ], environment: _baseEnvironment());

      expect(result.exitCode, 0);
      final List<String> invocationLines = fakeFlutterLog
          .readAsStringSync()
          .trim()
          .split('\n');
      expect(invocationLines, contains('build'));
      expect(invocationLines, contains('apk'));
      expect(invocationLines, contains('--debug'));
      expect(invocationLines, contains('--no-pub'));
      expect(invocationLines, contains('--dart-define=BACKEND_MODE=live'));
      expect(invocationLines, contains('--dart-define=APP_ENV=development'));
      expect(
        invocationLines,
        contains('--dart-define=ENABLE_QA_CONSOLE=false'),
      );
      expect(
        invocationLines,
        contains('--dart-define=ENABLE_VIDEO_RUNTIME_DEMO=false'),
      );
      expect(invocationLines, contains('--dart-define=ENABLE_AGORA_RTC=false'));
      expect(
        invocationLines,
        contains('--dart-define=API_BASE_URL=http://10.0.2.2:18080/'),
      );
      expect(
        invocationLines,
        contains('--dart-define=ALLOW_INSECURE_HTTP=true'),
      );
      expect(
        invocationLines,
        contains('--dart-define=OAUTH_CLIENT_ID=public-client'),
      );
      expect(invocationLines, contains('--dart-define=CLIENT_TYPE=Android'));
      expect(invocationLines, contains('--dart-define=CLIENT_INNER_VERSION=6'));
      expect(invocationLines, contains('--dart-define=API_TIMEOUT_SECONDS=15'));
      expect(invocationLines, contains('--dart-define=LIVE_PROBE_PATH=/'));
      expect(invocationLines, isNot(contains('-d')));
      expect(invocationLines, isNot(contains('emulator-5554')));
    },
  );

  test(
    'build-apk rejects a device selector instead of silently ignoring it',
    () {
      final ProcessResult result = _run(<String>[
        'build-apk',
        '--target',
        'android-emulator',
        '--device',
        'emulator-5554',
      ], environment: _baseEnvironment());

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('--device is only valid for run'));
      expect(fakeFlutterLog.existsSync(), isFalse);
    },
  );

  test(
    'fixed client metadata cannot be overridden by the host environment',
    () {
      final ProcessResult result = _run(
        <String>['build-apk', '--target', 'android-emulator'],
        environment: _baseEnvironment()
          ..['CLIENT_TYPE'] = 'iOS'
          ..['CLIENT_INNER_VERSION'] = 'SECRET'
          ..['API_TIMEOUT_SECONDS'] = '99999'
          ..['LIVE_PROBE_PATH'] = '/token',
      );

      expect(result.exitCode, 0);
      final String invocation = fakeFlutterLog.readAsStringSync();
      expect(invocation, contains('--dart-define=CLIENT_TYPE=Android'));
      expect(invocation, contains('--dart-define=CLIENT_INNER_VERSION=6'));
      expect(invocation, contains('--dart-define=API_TIMEOUT_SECONDS=15'));
      expect(invocation, contains('--dart-define=LIVE_PROBE_PATH=/'));
      expect(invocation, isNot(contains('CLIENT_TYPE=iOS')));
      expect(invocation, isNot(contains('CLIENT_INNER_VERSION=SECRET')));
      expect(invocation, isNot(contains('API_TIMEOUT_SECONDS=99999')));
      expect(invocation, isNot(contains('LIVE_PROBE_PATH=/token')));
    },
  );

  test('live launcher overrides host Mock-shell requests to false', () {
    final ProcessResult result = _run(
      <String>[
        'run',
        '--target',
        'android-emulator',
        '--device',
        'emulator-5554',
      ],
      environment: _baseEnvironment()
        ..['ENABLE_QA_CONSOLE'] = 'true'
        ..['ENABLE_VIDEO_RUNTIME_DEMO'] = 'true',
    );

    expect(result.exitCode, 0);
    final List<String> invocationLines = fakeFlutterLog
        .readAsStringSync()
        .trim()
        .split('\n');
    expect(invocationLines, contains('--dart-define=ENABLE_QA_CONSOLE=false'));
    expect(
      invocationLines,
      isNot(contains('--dart-define=ENABLE_QA_CONSOLE=true')),
    );
    expect(
      invocationLines,
      contains('--dart-define=ENABLE_VIDEO_RUNTIME_DEMO=false'),
    );
    expect(
      invocationLines,
      isNot(contains('--dart-define=ENABLE_VIDEO_RUNTIME_DEMO=true')),
    );
  });

  test(
    'rejects OAuth and vendor secret environment variables without echoing values',
    () {
      const String secretValue = 'never-print-this-secret';
      final ProcessResult result = _run(
        <String>['run', '--target', 'android-emulator'],
        environment: _baseEnvironment()..['OAUTH_CLIENT_SECRET'] = secretValue,
      );

      final String output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, isNot(0));
      expect(output, contains('confidential credential'));
      expect(output, isNot(contains(secretValue)));
      expect(fakeFlutterLog.existsSync(), isFalse);
    },
  );

  test('strips an unrelated host token before invoking Flutter', () {
    final ProcessResult result = _run(
      <String>[
        'run',
        '--target',
        'android-emulator',
        '--device',
        'emulator-5554',
      ],
      environment: _baseEnvironment()..['HOST_TOOL_TOKEN'] = 'host-only-token',
    );

    expect(result.exitCode, 0);
    expect(
      fakeFlutterEnvLog.readAsStringSync(),
      contains('HOST_TOOL_TOKEN=<unset>'),
    );
  });

  test('rejects an environment alias for the fixed Agora switch', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--device',
      'emulator-5554',
    ], environment: _baseEnvironment()..['ENABLE_AGORA_RTC'] = 'true');

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('--enable-agora-rtc'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('rejects environment Dart-define aliases before Flutter', () {
    final ProcessResult result = _run(
      <String>[
        'run',
        '--target',
        'android-emulator',
        '--device',
        'emulator-5554',
      ],
      environment: _baseEnvironment()
        ..['DART_DEFINES'] = 'QkFDS0VORF9NT0RFPW1vY2s=',
    );

    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('runtime defines are owned by this wrapper'),
    );
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('Android live entry prepares an isolated audio-only host', () {
    final ProcessResult result = _run(<String>[
      'build-apk',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment());

    expect(result.exitCode, 0);
    expect(fakeFlutterHostLog.readAsStringSync(), contains('RECORD_AUDIO'));
    expect(fakeFlutterHostLog.readAsStringSync(), contains('CAMERA'));
    expect(fakeFlutterHostLog.readAsStringSync(), contains('READ_PHONE_STATE'));
    expect(
      fakeFlutterHostLog.readAsStringSync(),
      contains('FOREGROUND_SERVICE_MEDIA_PROJECTION'),
    );
    expect(
      fakeFlutterHostLog.readAsStringSync(),
      contains('LocalScreenCaptureAssistantActivity'),
    );
    expect(Directory('android').existsSync(), isFalse);
  });

  test('Android live entry refuses a dirty checkout before Flutter', () {
    final File untrackedMarker = File('live-development-dirty-checkout-marker')
      ..writeAsStringSync('test-only');
    addTearDown(() {
      if (untrackedMarker.existsSync()) {
        untrackedMarker.deleteSync();
      }
    });

    final ProcessResult result = _run(<String>[
      'build-apk',
      '--target',
      'android-emulator',
    ], environment: _baseEnvironment());

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('requires a clean checkout'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('strips lowercase and mixed-case token environment variables', () {
    final ProcessResult result = _run(
      <String>[
        'run',
        '--target',
        'android-emulator',
        '--device',
        'emulator-5554',
      ],
      environment: _baseEnvironment()
        ..['access_token'] = 'lowercase-token'
        ..['Access_Token'] = 'mixed-token'
        ..['MiXeD_TOkEn'] = 'mixed-token-2',
    );

    final String output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0);
    expect(output, isNot(contains('lowercase-token')));
    expect(output, isNot(contains('mixed-token')));
    expect(output, isNot(contains('mixed-token-2')));
    final String childEnvironment = fakeFlutterEnvLog.readAsStringSync();
    expect(childEnvironment, contains('access_token=<unset>'));
    expect(childEnvironment, contains('Access_Token=<unset>'));
    expect(childEnvironment, contains('MiXeD_TOkEn=<unset>'));
  });

  test('passes only the minimal SDK environment to Flutter', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--device',
      'emulator-5554',
    ], environment: _baseEnvironment());

    expect(result.exitCode, 0);
    final String childEnvironment = fakeFlutterEnvLog.readAsStringSync();
    expect(childEnvironment, contains('AWS_PROFILE=<unset>'));
    expect(childEnvironment, contains('KUBECONFIG=<unset>'));
    expect(childEnvironment, contains('SSH_AUTH_SOCK=<unset>'));
    expect(childEnvironment, contains('PATH=${fakePath!}:'));
    expect(childEnvironment, contains('HOME=/tmp/live-development-test-home'));
    expect(
      childEnvironment,
      contains('JAVA_HOME=/tmp/live-development-test-java'),
    );
    expect(
      childEnvironment,
      contains('ANDROID_HOME=/tmp/live-development-test-android'),
    );
    expect(
      childEnvironment,
      contains('ANDROID_SDK_ROOT=/tmp/live-development-test-android'),
    );
  });

  test(
    'rejects API-key and credential environment variables before Flutter',
    () {
      for (final MapEntry<String, String> entry in <String, String>{
        'STRIPE_API_KEY': 'stripe-api-key-value',
        'google_application_credentials': 'google-credentials-value',
        'GitHub_Pat': 'github-pat-value',
        'vendor_auth': 'vendor-auth-value',
        'VENDOR_BEARER': 'vendor-bearer-value',
      }.entries) {
        final ProcessResult result = _run(<String>[
          'run',
          '--target',
          'android-emulator',
        ], environment: _baseEnvironment()..[entry.key] = entry.value);

        final String output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, isNot(0), reason: entry.key);
        expect(output, contains('confidential credential'), reason: entry.key);
        expect(output, isNot(contains(entry.value)), reason: entry.key);
        expect(fakeFlutterLog.existsSync(), isFalse, reason: entry.key);
      }
    },
  );

  test(
    'rejects lowercase and mixed-case confidential environment variables',
    () {
      for (final MapEntry<String, String> entry in <String, String>{
        'oauth_client_secret': 'lowercase-client-secret',
        'OAuth_Client_Secret': 'mixed-client-secret',
        'sEcReT': 'mixed-secret',
        'PaSsWoRd': 'mixed-password',
        'private_key': 'lowercase-private-key',
        'ACCESS_KEY': 'mixed-access-key',
      }.entries) {
        final ProcessResult result = _run(<String>[
          'run',
          '--target',
          'android-emulator',
        ], environment: _baseEnvironment()..[entry.key] = entry.value);

        final String output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, isNot(0), reason: entry.key);
        expect(output, contains('confidential credential'), reason: entry.key);
        expect(output, isNot(contains(entry.value)), reason: entry.key);
        expect(fakeFlutterLog.existsSync(), isFalse, reason: entry.key);
      }
    },
  );

  test('rejects a dart-define file before Flutter can read it', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--dart-define-from-file=local.env.json',
    ], environment: _baseEnvironment());

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('dart-define-from-file'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('rejects mixed-case define and define-file arguments', () {
    for (final String argument in <String>[
      '--DART-DEFINE=access_token=lowercase-token',
      '--DART-DEFINE',
      '--dArT-DeFiNe-FrOm-FiLe=local.env.json',
    ]) {
      final ProcessResult result = _run(<String>[
        'run',
        '--target',
        'android-emulator',
        argument,
      ], environment: _baseEnvironment());

      final String output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, isNot(0), reason: argument);
      expect(output, isNot(contains('lowercase-token')), reason: argument);
      expect(fakeFlutterLog.existsSync(), isFalse, reason: argument);
    }
  });

  test('rejects lowercase and mixed-case confidential CLI arguments', () {
    for (final MapEntry<String, String> entry in <String, String>{
      '--oauth_client_secret=lowercase-client-secret':
          'lowercase-client-secret',
      '--PrIvAtE_KeY=mixed-private-key': 'mixed-private-key',
      '--ACCESS_TOKEN=mixed-access-token': 'mixed-access-token',
      '--api-key=mixed-api-key': 'mixed-api-key',
      '--AUTH=mixed-auth': 'mixed-auth',
      '--BEARER=mixed-bearer': 'mixed-bearer',
    }.entries) {
      final ProcessResult result = _run(<String>[
        'run',
        '--target',
        'android-emulator',
        entry.key,
      ], environment: _baseEnvironment());

      final String output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, isNot(0), reason: entry.key);
      expect(output, contains('confidential credential'), reason: entry.key);
      expect(output, isNot(contains(entry.value)), reason: entry.key);
      expect(fakeFlutterLog.existsSync(), isFalse, reason: entry.key);
    }
  });

  test('rejects separated OAuth client-id values that look confidential', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--oauth-client-id',
      'client_secret_value',
    ], environment: _baseEnvironment());

    final String output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0));
    expect(output, contains('confidential credential'));
    expect(output, isNot(contains('client_secret_value')));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('rejects a newline in a separated OAuth client-id value', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--oauth-client-id',
      'public-client\n-injected',
    ], environment: _baseEnvironment());

    final String output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0));
    expect(output, contains('confidential credential'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('rejects an obviously confidential OAuth environment value', () {
    final ProcessResult result = _run(
      <String>['run', '--target', 'android-emulator'],
      environment: _baseEnvironment()
        ..['OAUTH_CLIENT_ID'] = 'client_secret_value',
    );

    final String output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0));
    expect(output, contains('confidential credential'));
    expect(output, isNot(contains('client_secret_value')));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('rejects all user Dart-define aliases before Flutter', () {
    for (final List<String> alias in <List<String>>[
      <String>['-D', 'BACKEND_MODE=mock'],
      <String>['-DENABLE_QA_CONSOLE=true'],
      <String>['--DartDefines', 'BACKEND_MODE=mock'],
      <String>['--DartDefines=ENABLE_QA_CONSOLE=true'],
    ]) {
      final ProcessResult result = _run(<String>[
        'run',
        '--target',
        'android-emulator',
        ...alias,
      ], environment: _baseEnvironment());

      expect(result.exitCode, isNot(0), reason: alias.join(' '));
      expect(
        result.stderr,
        contains('runtime defines are owned by this wrapper'),
        reason: alias.join(' '),
      );
      expect(fakeFlutterLog.existsSync(), isFalse, reason: alias.join(' '));
    }
  });

  test('rejects Android project define aliases before Flutter', () {
    for (final List<String> alias in <List<String>>[
      <String>['-Pdart-defines=QkFDS0VORF9NT0RFPW1vY2s='],
      <String>['-P', 'dart-defines=QkFDS0VORF9NT0RFPW1vY2s='],
      <String>['--android-project-arg=dart-defines=QkFDS0VORF9NT0RFPW1vY2s='],
      <String>[
        '--android-project-arg',
        'dart-defines=QkFDS0VORF9NT0RFPW1vY2s=',
      ],
    ]) {
      final ProcessResult result = _run(<String>[
        'build-apk',
        '--target',
        'android-emulator',
        ...alias,
      ], environment: _baseEnvironment());

      expect(result.exitCode, isNot(0), reason: alias.join(' '));
      expect(
        result.stderr,
        contains('runtime defines are owned by this wrapper'),
        reason: alias.join(' '),
      );
      expect(fakeFlutterLog.existsSync(), isFalse, reason: alias.join(' '));
    }
  });

  test('rejects an unapproved Flutter passthrough option', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--target-platform=android-arm64',
    ], environment: _baseEnvironment());

    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('additional Flutter arguments are restricted'),
    );
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('allows a harmless verbosity flag through the explicit allowlist', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--device',
      'emulator-5554',
      '--',
      '--verbose',
    ], environment: _baseEnvironment());

    expect(result.exitCode, 0);
    expect(fakeFlutterLog.readAsStringSync(), contains('--verbose'));
  });

  test('rejects an Android emulator selector for the host target', () {
    final ProcessResult result = _run(
      <String>['run', '--target', 'host', '--device', 'emulator-5554'],
      environment: _baseEnvironment()
        ..['API_BASE_URL'] = 'http://127.0.0.1:18080/',
    );

    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('host target cannot use an Android emulator'),
    );
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('requires an Android emulator selector for the emulator target', () {
    final ProcessResult result = _run(<String>[
      'run',
      '--target',
      'android-emulator',
      '--device',
      'macos',
    ], environment: _baseEnvironment());

    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains(
        'android-emulator target requires an Android emulator device selector',
      ),
    );
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('rejects API ports outside 1 through 65535', () {
    for (final String port in <String>['0', '65536']) {
      final ProcessResult result = _run(
        <String>[
          'run',
          '--target',
          'android-emulator',
          '--device',
          'emulator-5554',
        ],
        environment: _baseEnvironment()
          ..['API_BASE_URL'] = 'http://10.0.2.2:$port/',
      );

      expect(result.exitCode, isNot(0), reason: port);
      expect(
        result.stderr,
        contains('port must be between 1 and 65535'),
        reason: port,
      );
      expect(fakeFlutterLog.existsSync(), isFalse, reason: port);
    }
  });

  test('rejects whitespace in the API URL before Flutter', () {
    final ProcessResult result = _run(
      <String>[
        'run',
        '--target',
        'android-emulator',
        '--device',
        'emulator-5554',
      ],
      environment: _baseEnvironment()
        ..['API_BASE_URL'] = 'http://10.0.2.2:18080/path with space',
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('API_BASE_URL must not contain whitespace'));
    expect(fakeFlutterLog.existsSync(), isFalse);
  });

  test('rejects a non-root API URL path before Flutter', () {
    final ProcessResult result = _run(
      <String>[
        'run',
        '--target',
        'android-emulator',
        '--device',
        'emulator-5554',
      ],
      environment: _baseEnvironment()
        ..['API_BASE_URL'] = 'http://10.0.2.2:18080/token',
    );

    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('API_BASE_URL must be an absolute HTTP(S) origin'),
    );
    expect(fakeFlutterLog.existsSync(), isFalse);
  });
}

String get _projectRoot => Directory.current.path;

File get _script => File('$_projectRoot/tool/live_development.sh');

Map<String, String> _baseEnvironment() {
  final Map<String, String> environment = <String, String>{
    ...Platform.environment,
    'PATH': '${fakePath!}:${Platform.environment['PATH'] ?? ''}',
    'API_BASE_URL': 'http://10.0.2.2:18080/',
    'OAUTH_CLIENT_ID': 'public-client',
    'FAKE_FLUTTER_LOG': fakeLogPath!,
    'FAKE_FLUTTER_HOST_LOG': fakeHostLogPath!,
    'FAKE_FLUTTER_ENV_LOG': fakeFlutterEnvLogPath!,
    'HOME': '/tmp/live-development-test-home',
    'USER': 'live-development-test',
    'LOGNAME': 'live-development-test',
    'TMPDIR': '/tmp/live-development-test-tmp',
    'SHELL': '/bin/bash',
    'JAVA_HOME': '/tmp/live-development-test-java',
    'ANDROID_HOME': '/tmp/live-development-test-android',
    'ANDROID_SDK_ROOT': '/tmp/live-development-test-android',
    'AWS_PROFILE': 'host-profile',
    'KUBECONFIG': '/private/host-kubeconfig',
    'SSH_AUTH_SOCK': '/tmp/host-ssh-agent.sock',
  };
  for (final String name in <String>[
    'OAUTH_CLIENT_SECRET',
    'M3_OAUTH_CLIENT_SECRET',
    'JWT_SECRET',
    'MYSQL_PASSWORD',
    'REDIS_PASSWORD',
    'TENCENT_SECRET_ID',
    'TENCENT_SECRET_KEY',
    'ALIYUN_ACCESS_KEY_ID',
    'ALIYUN_ACCESS_KEY_SECRET',
    'AWS_ACCESS_KEY_ID',
    'AWS_SECRET_ACCESS_KEY',
    'APNS_PRIVATE_KEY',
    'IM_ADMIN_SECRET',
    'PAYMENT_PRIVATE_KEY',
    'oauth_client_secret',
    'OAuth_Client_Secret',
    'sEcReT',
    'PaSsWoRd',
    'private_key',
    'ACCESS_KEY',
    'STRIPE_API_KEY',
    'google_application_credentials',
    'GitHub_Pat',
    'vendor_auth',
    'VENDOR_BEARER',
    'CLIENT_TYPE',
    'CLIENT_INNER_VERSION',
    'API_TIMEOUT_SECONDS',
    'LIVE_PROBE_PATH',
    'access_token',
    'Access_Token',
    'MiXeD_TOkEn',
  ]) {
    environment.remove(name);
  }
  return environment;
}

String? fakePath;
String? fakeLogPath;
String? fakeFlutterEnvLogPath;
String? fakeVersionConfigPath;
String? fakeHostLogPath;

ProcessResult _run(List<String> arguments, {Map<String, String>? environment}) {
  final Map<String, String> env = <String, String>{
    ...Platform.environment,
    ...?environment,
  };
  final String? path = env['PATH'];
  final List<String> pathParts =
      path?.split(Platform.isWindows ? ';' : ':') ?? <String>[];
  fakePath = pathParts.isNotEmpty ? pathParts.first : null;
  fakeLogPath = env['FAKE_FLUTTER_LOG'];
  fakeHostLogPath = env['FAKE_FLUTTER_HOST_LOG'];
  final String frameworkVersion = env['FAKE_FLUTTER_VERSION'] ?? '3.44.7';
  final String dartVersion = env['FAKE_DART_VERSION'] ?? '3.12.2';
  File(
    fakeVersionConfigPath!,
  ).writeAsStringSync('$frameworkVersion|$dartVersion\n');
  return Process.runSync(
    'bash',
    <String>[_script.path, ...arguments],
    workingDirectory: _projectRoot,
    environment: env,
  );
}
