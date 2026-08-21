import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fakeFlutterBin;
  late File fakeFlutterLog;
  late File fakeFlutterEnvLog;

  setUp(() {
    fakeFlutterBin = Directory.systemTemp.createTempSync('live-dev-flutter-');
    fakeFlutterLog = File('${fakeFlutterBin.path}/invocation.log');
    fakeFlutterEnvLog = File('${fakeFlutterBin.path}/environment.log');
    fakePath = fakeFlutterBin.path;
    fakeLogPath = fakeFlutterLog.path;
    fakeFlutterEnvLogPath = fakeFlutterEnvLog.path;
    final File fakeFlutter = File('${fakeFlutterBin.path}/flutter');
    fakeFlutter.writeAsStringSync('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "\$@" > "\${FAKE_FLUTTER_LOG}"
printf '%s\\n' "\${HOST_TOOL_TOKEN-<unset>}" > "\${FAKE_FLUTTER_ENV_LOG}"
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
    expect(
      invocation,
      contains('--dart-define=API_BASE_URL=http://10.0.2.2:18080/'),
    );
    expect(invocation, contains('--dart-define=OAUTH_CLIENT_ID=public-client'));
    expect(invocation, isNot(contains('SECRET')));
    expect(invocation, isNot(contains('PASSWORD')));
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
    },
  );

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
      <String>['run', '--target', 'android-emulator'],
      environment: _baseEnvironment()..['HOST_TOOL_TOKEN'] = 'host-only-token',
    );

    expect(result.exitCode, 0);
    expect(fakeFlutterEnvLog.readAsStringSync().trim(), '<unset>');
  });

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
    'FAKE_FLUTTER_ENV_LOG': fakeFlutterEnvLogPath!,
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
  ]) {
    environment.remove(name);
  }
  return environment;
}

String? fakePath;
String? fakeLogPath;
String? fakeFlutterEnvLogPath;

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
  return Process.runSync(
    'bash',
    <String>[_script.path, ...arguments],
    workingDirectory: _projectRoot,
    environment: env,
  );
}
