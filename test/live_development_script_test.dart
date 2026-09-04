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
  Directory? isolatedCheckoutParent;
  Directory? isolatedCheckout;

  setUpAll(() async {
    _originalWorkingDirectory = Directory.current.path;
    _originalCheckoutRoot = _originalWorkingDirectory;
    _originalCheckoutHead = _gitOutput(_originalCheckoutRoot!, <String>[
      'rev-parse',
      'HEAD',
    ]);
    _originalCheckoutSentinel = await _captureCheckoutSentinel(
      _originalCheckoutRoot!,
    );

    // Every test process gets its own shallow checkout at the exact test HEAD.
    // Fetching only that commit avoids asking a partial/promisor source clone
    // to repack unrelated historical objects that may not exist locally.  The
    // wrapper derives ROOT_DIR from its own script path, so changing this
    // process's cwd is enough to keep all build/run output inside the isolated
    // checkout.  The original checkout is never renamed or cleaned.
    isolatedCheckoutParent = Directory.systemTemp.createTempSync(
      'live-development-script-test-',
    );
    isolatedCheckout = Directory('${isolatedCheckoutParent!.path}/checkout');
    isolatedCheckout!.createSync(recursive: true);
    final ProcessResult initResult = Process.runSync('git', <String>[
      '-C',
      isolatedCheckout!.path,
      'init',
      '--quiet',
    ]);
    final ProcessResult fetchResult = initResult.exitCode == 0
        ? Process.runSync('git', <String>[
            '-C',
            isolatedCheckout!.path,
            'fetch',
            '--quiet',
            '--depth=1',
            _originalCheckoutRoot!,
            _originalCheckoutHead!,
          ])
        : initResult;
    if (initResult.exitCode != 0 || fetchResult.exitCode != 0) {
      throw StateError('unable to fetch isolated test checkout');
    }
    final ProcessResult detachResult = Process.runSync('git', <String>[
      '-C',
      isolatedCheckout!.path,
      'checkout',
      '--detach',
      '--quiet',
      'FETCH_HEAD',
    ]);
    if (detachResult.exitCode != 0 ||
        _gitOutput(isolatedCheckout!.path, <String>['rev-parse', 'HEAD']) !=
            _originalCheckoutHead) {
      throw StateError('isolated test checkout is not at the exact test HEAD');
    }
    if (_gitOutput(isolatedCheckout!.path, <String>[
      'status',
      '--porcelain',
      '--untracked-files=normal',
    ]).isNotEmpty) {
      throw StateError('isolated test checkout is not clean');
    }

    Directory.current = isolatedCheckout!.path;
    liveArtifactDirectory = Directory(
      '${isolatedCheckout!.path}/build/live-development',
    );
    liveArtifact = File('${liveArtifactDirectory.path}/app-debug.apk');
    liveArtifactHash = File(
      '${liveArtifactDirectory.path}/app-debug.apk.sha256',
    );
  });

  setUp(() {
    fakeFlutterBin = Directory.systemTemp.createTempSync('live-dev-flutter-');
    fakeFlutterLog = File('${fakeFlutterBin.path}/invocation.log');
    fakeFlutterEnvLog = File('${fakeFlutterBin.path}/environment.log');
    fakeFlutterVersionConfig = File('${fakeFlutterBin.path}/version.config');
    fakeFlutterBehaviorConfig = File('${fakeFlutterBin.path}/behavior.config')
      ..writeAsStringSync('success\n');
    fakeFlutterHostLog = File('${fakeFlutterBin.path}/android-host.log');
    _removeEntityIfPresent(liveArtifactDirectory.path, recursive: true);
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
    python3 - "\$build_behavior" "build/app/outputs/flutter-apk/app-debug.apk" <<'PY'
import pathlib
import sys
import zipfile

mode = sys.argv[1]
apk = pathlib.Path(sys.argv[2])
apk.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(apk, 'w', compression=zipfile.ZIP_STORED) as archive:
    if mode == 'forbidden-apk':
        archive.writestr(
            'lib/arm64-v8a/libagora_face_capture_extension.so',
            b'forbidden',
        )
        archive.writestr(
            'lib/arm64-v8a/libagora_lip_sync_extension.so',
            b'forbidden',
        )
        archive.writestr(
          'assets/secret.pem',
          b'-----BEGIN ' b'RSA ' b'PRIVATE ' b'KEY-----\\nsecret\\n-----END '
          b'RSA ' b'PRIVATE ' b'KEY-----\\n',
        )
    else:
        archive.writestr('assets/placeholder.txt', b'safe-apk')
PY
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
    try {
      if (fakeFlutterBin.existsSync()) {
        fakeFlutterBin.deleteSync(recursive: true);
      }
      fakePath = null;
      fakeLogPath = null;
      fakeFlutterEnvLogPath = null;
      fakeVersionConfigPath = null;
      fakeHostLogPath = null;
    } finally {
      // Only remove output from this test's private clone.  In particular,
      // never clean a path in the original checkout from tearDown.
      _removeEntityIfPresent(liveArtifactDirectory.path, recursive: true);
    }
  });

  tearDownAll(() async {
    try {
      // Restore cwd before removing the clone.  If the test process is
      // interrupted, the clone may remain in system temp, but it cannot
      // affect the real checkout or its retained APK.
      if (_originalWorkingDirectory != null) {
        Directory.current = _originalWorkingDirectory!;
        await _assertOriginalCheckoutUntouched();
      }
    } finally {
      if (isolatedCheckoutParent?.existsSync() ?? false) {
        isolatedCheckoutParent!.deleteSync(recursive: true);
      }
    }
  });

  test('help describes the two supported live-development entry points', () {
    final ProcessResult result = _runCurrentLauncher(<String>['help']);

    expect(result.exitCode, 0);
    expect(result.stdout, contains('run'));
    expect(result.stdout, contains('build-apk'));
    expect(result.stdout, contains('10.0.2.2'));
    expect(result.stdout, contains('127.0.0.1'));
    expect(result.stdout, contains('--enable-tencent-im'));
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

  test(
    'explicit Tencent IM switch passes exactly the public enable define',
    () {
      final ProcessResult result = _runCurrentLauncher(
        <String>[
          'run',
          '--target',
          'host',
          '--device',
          'macos',
          '--enable-tencent-im',
        ],
        environment: _baseEnvironment()
          ..['API_BASE_URL'] = 'http://127.0.0.1:18080/',
      );

      expect(result.exitCode, 0);
      final List<String> invocationLines = fakeFlutterLog
          .readAsStringSync()
          .trim()
          .split('\n');
      expect(invocationLines, contains('--dart-define=ENABLE_TENCENT_IM=true'));
      expect(
        invocationLines,
        isNot(contains('--dart-define=ENABLE_TENCENT_IM=false')),
      );
      expect(
        invocationLines.where(
          (String line) => line.startsWith('--dart-define=ENABLE_TENCENT_IM='),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'Tencent IM switch defaults to false without an environment override',
    () {
      final ProcessResult result = _runCurrentLauncher(
        <String>['run', '--target', 'host', '--device', 'macos'],
        environment: _baseEnvironment()
          ..['API_BASE_URL'] = 'http://127.0.0.1:18080/',
      );

      expect(result.exitCode, 0);
      final List<String> invocationLines = fakeFlutterLog
          .readAsStringSync()
          .trim()
          .split('\n');
      expect(
        invocationLines,
        contains('--dart-define=ENABLE_TENCENT_IM=false'),
      );
      expect(
        invocationLines,
        isNot(contains('--dart-define=ENABLE_TENCENT_IM=true')),
      );
    },
  );

  test('Tencent IM switch is strict and does not accept a value', () {
    final ProcessResult result = _runCurrentLauncher(
      <String>[
        'run',
        '--target',
        'host',
        '--device',
        'macos',
        '--enable-tencent-im=true',
      ],
      environment: _baseEnvironment()
        ..['API_BASE_URL'] = 'http://127.0.0.1:18080/',
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('--enable-tencent-im'));
    expect(fakeFlutterLog.existsSync(), isFalse);
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

  test(
    'successful build retains the APK and SHA-256 after wrapper exit',
    () async {
      final ProcessResult result = _run(<String>[
        'build-apk',
        '--target',
        'android-emulator',
        '--enable-agora-rtc',
      ], environment: _baseEnvironment());

      expect(result.exitCode, 0);
      expect(liveArtifact.existsSync(), isTrue);
      expect(liveArtifactHash.existsSync(), isTrue);
      expect(liveArtifact.lengthSync(), greaterThan(0));
      final ProcessResult zipCheck = Process.runSync('python3', <String>[
        '-c',
        'import sys,zipfile; print("\\n".join(sorted(zipfile.ZipFile(sys.argv[1]).namelist())))',
        liveArtifact.path,
      ]);
      expect(
        zipCheck.exitCode,
        0,
        reason: '${zipCheck.stdout}\n${zipCheck.stderr}',
      );
      expect(zipCheck.stdout, contains('assets/placeholder.txt'));
      final String digest = sha256
          .convert(liveArtifact.readAsBytesSync())
          .toString();
      expect(liveArtifactHash.readAsStringSync(), '$digest  app-debug.apk\n');
      expect(result.stdout, contains('live_apk_path='));
      final String reportedPath = result.stdout
          .toString()
          .split('\n')
          .firstWhere((String line) => line.startsWith('live_apk_path='))
          .substring('live_apk_path='.length);
      expect(
        File(reportedPath).resolveSymbolicLinksSync(),
        liveArtifact.resolveSymbolicLinksSync(),
      );
      expect(result.stdout, contains('live_apk_sha256=$digest'));
      await _assertOriginalCheckoutUntouched();
    },
  );

  test(
    'build-apk rejects APKs that still contain Agora extensions or private-key PEM material',
    () {
      fakeFlutterBehaviorConfig.writeAsStringSync('forbidden-apk\n');

      final ProcessResult result = _run(<String>[
        'build-apk',
        '--target',
        'android-emulator',
      ], environment: _baseEnvironment());

      final String output = '${result.stdout}\n${result.stderr}';
      expect(result.exitCode, isNot(0));
      expect(
        output,
        contains(
          'forbidden Agora extension artifacts or private-key PEM material',
        ),
      );
      expect(
        output,
        isNot(
          contains(
            'BEGIN '
            'RSA '
            'PRIVATE '
            'KEY',
          ),
        ),
      );
      expect(output, isNot(contains('libagora_face_capture_extension.so')));
      expect(output, isNot(contains('libagora_lip_sync_extension.so')));
      expect(liveArtifact.existsSync(), isFalse);
      expect(liveArtifactHash.existsSync(), isFalse);
    },
  );

  test('dry-run reports Tencent IM as a boolean without credentials', () {
    final ProcessResult result = _runCurrentLauncher(<String>[
      'build-apk',
      '--target',
      'android-emulator',
      '--enable-tencent-im',
      '--dry-run',
    ], environment: _baseEnvironment());

    expect(result.exitCode, 0);
    expect(result.stdout, contains('enable_tencent_im=true'));
    expect(result.stdout, isNot(contains('public-client')));
    expect(fakeFlutterLog.existsSync(), isFalse);
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

  test('rejects environment aliases for the fixed Tencent IM switch', () {
    for (final String name in <String>[
      'ENABLE_TENCENT_IM',
      'TENCENT_IM',
      'TENCENT_ENABLE_IM',
      'ORG_GRADLE_PROJECT_ENABLE_TENCENT_IM',
      'GRADLE_OPTS',
    ]) {
      final ProcessResult result = _runCurrentLauncher(
        <String>['run', '--target', 'host', '--device', 'macos'],
        environment: _baseEnvironment()
          ..['API_BASE_URL'] = 'http://127.0.0.1:18080/'
          ..[name] = 'true',
      );

      expect(result.exitCode, isNot(0), reason: name);
      if (name == 'ORG_GRADLE_PROJECT_ENABLE_TENCENT_IM' ||
          name == 'GRADLE_OPTS') {
        expect(
          result.stderr,
          contains('runtime defines are owned by this wrapper'),
          reason: name,
        );
      } else {
        expect(result.stderr, contains('--enable-tencent-im'), reason: name);
      }
      expect(fakeFlutterLog.existsSync(), isFalse, reason: name);
    }
  });

  test('rejects Tencent IM Dart-define and Gradle aliases', () {
    for (final List<String> alias in <List<String>>[
      <String>['--dart-define=ENABLE_TENCENT_IM=true'],
      <String>['-PENABLE_TENCENT_IM=true'],
      <String>['-P', 'ENABLE_TENCENT_IM=true'],
      <String>['--android-project-arg=ENABLE_TENCENT_IM=true'],
      <String>['--android-project-arg', 'ENABLE_TENCENT_IM=true'],
    ]) {
      final ProcessResult result = _runCurrentLauncher(
        <String>['run', '--target', 'host', '--device', 'macos', ...alias],
        environment: _baseEnvironment()
          ..['API_BASE_URL'] = 'http://127.0.0.1:18080/',
      );

      expect(result.exitCode, isNot(0), reason: alias.join(' '));
      expect(
        result.stderr,
        contains('runtime defines are owned by this wrapper'),
        reason: alias.join(' '),
      );
      expect(fakeFlutterLog.existsSync(), isFalse, reason: alias.join(' '));
    }
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

  test('Android live entry prepares an isolated audio-only host copy', () {
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
    expect(Directory('android').existsSync(), isTrue);
    expect(
      _gitOutput(isolatedCheckout!.path, <String>[
        'status',
        '--porcelain',
        '--untracked-files=normal',
      ]),
      isEmpty,
      reason: 'the tracked Android host must not be mutated by live builds',
    );
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

String? _originalWorkingDirectory;
String? _originalCheckoutRoot;
String? _originalCheckoutHead;
_CheckoutSentinel? _originalCheckoutSentinel;

class _CheckoutSentinel {
  const _CheckoutSentinel({
    required this.gitHead,
    required this.gitStatus,
    required this.entries,
  });

  final String gitHead;
  final String gitStatus;
  final Map<String, String> entries;
}

Future<_CheckoutSentinel> _captureCheckoutSentinel(String root) async {
  final Map<String, String> entries = <String, String>{};
  await _captureEntity(root, 'build', entries, includeChildren: false);
  await _captureEntity(
    root,
    'build/live-development',
    entries,
    includeChildren: true,
  );
  await _captureEntity(root, 'android', entries, includeChildren: true);
  return _CheckoutSentinel(
    gitHead: _gitOutput(root, <String>['rev-parse', 'HEAD']),
    gitStatus: _gitOutput(root, <String>[
      'status',
      '--porcelain',
      '--untracked-files=normal',
    ]),
    entries: entries,
  );
}

Future<void> _captureEntity(
  String root,
  String relativePath,
  Map<String, String> entries, {
  required bool includeChildren,
}) async {
  final String path = '$root/$relativePath';
  final FileSystemEntityType type = FileSystemEntity.typeSync(
    path,
    followLinks: false,
  );
  if (type == FileSystemEntityType.notFound) {
    entries[relativePath] = 'not-found';
    return;
  }

  if (type == FileSystemEntityType.link) {
    entries[relativePath] = '${type.toString()}|${Link(path).targetSync()}';
    return;
  }
  final FileStat stat = FileStat.statSync(path);
  String digest = '';
  if (type == FileSystemEntityType.file) {
    digest = (await sha256.bind(File(path).openRead())).toString();
  }
  entries[relativePath] =
      '${type.toString()}|${stat.mode}|${stat.size}|'
      '${stat.modified.microsecondsSinceEpoch}|$digest';

  if (includeChildren && type == FileSystemEntityType.directory) {
    final List<FileSystemEntity> children =
        Directory(path).listSync(followLinks: false).toList()
          ..sort((FileSystemEntity left, FileSystemEntity right) {
            return left.path.compareTo(right.path);
          });
    for (final FileSystemEntity child in children) {
      final int separator = child.path.lastIndexOf(Platform.pathSeparator);
      final String name = separator < 0
          ? child.path
          : child.path.substring(separator + 1);
      await _captureEntity(
        root,
        '$relativePath/$name',
        entries,
        includeChildren: true,
      );
    }
  }
}

String _gitOutput(String root, List<String> arguments) {
  final ProcessResult result = Process.runSync('git', <String>[
    '-C',
    root,
    ...arguments,
  ]);
  if (result.exitCode != 0) {
    throw StateError('git command failed while preparing the isolated test');
  }
  return result.stdout.toString().trimRight();
}

Future<void> _assertOriginalCheckoutUntouched() async {
  final _CheckoutSentinel? before = _originalCheckoutSentinel;
  final String? root = _originalCheckoutRoot;
  if (before == null || root == null) {
    return;
  }
  final _CheckoutSentinel after = await _captureCheckoutSentinel(root);
  if (after.gitHead != before.gitHead ||
      after.gitStatus != before.gitStatus ||
      !_sameMap(after.entries, before.entries)) {
    throw StateError(
      'the original checkout changed while testing live-development',
    );
  }
}

bool _sameMap(Map<String, String> left, Map<String, String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final MapEntry<String, String> entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

String get _projectRoot => Directory.current.path;

File get _script => File('$_projectRoot/tool/live_development.sh');

void _removeEntityIfPresent(String path, {required bool recursive}) {
  switch (FileSystemEntity.typeSync(path, followLinks: false)) {
    case FileSystemEntityType.directory:
      Directory(path).deleteSync(recursive: recursive);
    case FileSystemEntityType.file:
      File(path).deleteSync();
    case FileSystemEntityType.link:
      Link(path).deleteSync();
    case FileSystemEntityType.notFound:
      return;
    default:
      throw StateError('unsupported filesystem entry: $path');
  }
}

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
    'ENABLE_TENCENT_IM',
    'TENCENT_IM',
    'TENCENT_ENABLE_IM',
    'ORG_GRADLE_PROJECT_ENABLE_TENCENT_IM',
    'GRADLE_OPTS',
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
  return _runScript(
    arguments,
    environment: environment,
    scriptPath: _script.path,
    workingDirectory: _projectRoot,
  );
}

ProcessResult _runCurrentLauncher(
  List<String> arguments, {
  Map<String, String>? environment,
}) {
  final String? checkoutRoot = _originalCheckoutRoot;
  if (checkoutRoot == null) {
    throw StateError('original checkout root is not initialized');
  }
  return _runScript(
    arguments,
    environment: environment,
    scriptPath: '$checkoutRoot/tool/live_development.sh',
    workingDirectory: checkoutRoot,
  );
}

ProcessResult _runScript(
  List<String> arguments, {
  required String scriptPath,
  required String workingDirectory,
  Map<String, String>? environment,
}) {
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
    <String>[scriptPath, ...arguments],
    workingDirectory: workingDirectory,
    environment: env,
  );
}
