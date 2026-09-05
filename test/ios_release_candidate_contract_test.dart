import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Directory root = Directory.current;
  final File validator = File(
    '${root.path}/tool/release/ios_release_validator.sh',
  );
  final File releaseDocument = File('${root.path}/docs/release/ios-release.md');

  test('iOS release validator self-test is deterministic and redacted', () {
    expect(validator.existsSync(), isTrue);

    final ProcessResult result = Process.runSync(
      'bash',
      <String>[validator.path, '--self-test'],
      workingDirectory: root.path,
      environment: <String, String>{
        ...Platform.environment,
        'IOS_RELEASE_TEST_SENTINEL': 'do-not-print-this-sentinel',
      },
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout.toString().trim(),
      'ios-release-validator=self-test-PASS',
    );
    expect(result.stderr.toString(), isEmpty);
    expect(
      result.stdout.toString(),
      isNot(contains('ios-release-validation=PASS')),
    );
    expect(
      result.stdout.toString(),
      isNot(contains('do-not-print-this-sentinel')),
    );
  });

  test('self-test cannot be mistaken for candidate validation', () {
    final ProcessResult result = Process.runSync('bash', <String>[
      validator.path,
      '--self-test',
      '--archive',
      '/tmp/ignored.xcarchive',
    ], workingDirectory: root.path);

    expect(result.exitCode, isNonZero);
    expect(
      result.stderr.toString().trim(),
      'ios-release-validation=FAIL reason=self_test_arguments_invalid',
    );
    expect(result.stdout.toString(), isEmpty);
  });

  test(
    'validator accepts explicit archive, optional IPA, and expectations',
    () {
      final String source = validator.readAsStringSync();

      for (final String required in <String>[
        '--archive',
        '--ipa',
        '--expected-bundle-id',
        '--expected-version',
        '--expected-build',
        '--expected-team-id',
        '--self-test',
      ]) {
        expect(source, contains(required), reason: required);
      }
      expect(source, contains('.xcarchive'));
      expect(source, contains('.ipa'));
      expect(source, contains('ios-release-validation=PASS'));
    },
  );

  test('validator fail-closes every required iOS release evidence surface', () {
    final String source = validator.readAsStringSync();

    for (final String required in <String>[
      'Info.plist',
      'ArchiveVersion',
      'Products/Applications',
      'CFBundleIdentifier',
      'CFBundleShortVersionString',
      'CFBundleVersion',
      'CFBundleExecutable',
      'DTPlatformName',
      'iphoneos',
      'Mach-O',
      'otool',
      'IOSSIMULATOR',
      'codesign',
      '--verify',
      '--deep',
      '--strict',
      '--display',
      '--entitlements',
      'Apple Distribution',
      'iPhone Distribution',
      'adhoc',
      'embedded.mobileprovision',
      'security',
      'cms',
      'application-identifier',
      'com.apple.developer.team-identifier',
      'get-task-allow',
      'ExpirationDate',
      'PrivacyInfo.xcprivacy',
      'privacy_manifest_not_dictionary',
      'sha256',
      'unzip',
      '-n',
      'Payload',
      'ipa_duplicate_entry',
      'ipa_special_file_detected',
      'app_special_file_detected',
      'path_traversal',
      'symlink',
      'arm64',
      'device_architecture_not_supported',
      '-b',
    ]) {
      expect(source, contains(required), reason: required);
    }
    expect(source, contains('profile_expired'));
    expect(source, contains('entitlement'));
    expect(source, contains('signed_application_identifier_mismatch'));
    expect(source, contains('signed_team_identifier_mismatch'));
    expect(source, contains('signed_get_task_allow_enabled'));
    expect(source, contains('executable_sha256'));
  });

  test('IPA correspondence allows export-time re-signing', () {
    final String source = validator.readAsStringSync();

    expect(source, contains('executable_content_sha256'));
    expect(source, contains('--remove-signature'));
    expect(source, contains('ipa_executable_content_hash_mismatch'));
    expect(source, contains('ipa_executable_name_mismatch'));
    expect(source, contains('ipa_bundle_content_hash_mismatch'));
    expect(source, contains('archive_app_content_sha256'));
    expect(source, contains('ipa_app_content_sha256'));
    expect(source, contains('different Flutter code fixture'));
    expect(source, contains('different Flutter asset fixture'));
    expect(source, isNot(contains('ipa_app_hash_mismatch')));
    expect(source, isNot(contains('ipa_executable_hash_mismatch')));
    expect(source, isNot(contains('ipa_signing_mismatch')));
  });

  test(
    'validator has no signing, upload, App Store, or secret-output behavior',
    () {
      final String source = validator.readAsStringSync();
      final List<RegExp> forbidden = <RegExp>[
        RegExp(r'codesign\s+[^\n]*\s(?:-s|--sign)(?:\s|=)', multiLine: true),
        RegExp(
          r'\bsecurity\s+(?:import|add-certificates|delete|unlock)',
          multiLine: true,
        ),
        RegExp(
          r'\b(?:xcodebuild|xcrun|altool|notarytool|iTMSTransporter|fastlane|pilot)\b',
        ),
        RegExp(r'\b(?:curl|wget|scp|rsync)\b'),
        RegExp(r'\b(?:open|osascript)\b'),
        RegExp(r'^(?!#!.*)\s*(?:printenv|env)\b', multiLine: true),
        RegExp(r'\bset\s+-x\b'),
        RegExp(r'\$\{?(?:SECRET|TOKEN|PASSWORD|PRIVATE_KEY|API_KEY)'),
        RegExp(
          r'printf\s+[^\n]*\$(?:ARCHIVE_PATH|IPA_PATH|EXPECTED_|ARCHIVE_SIGNING|CURRENT_SIGNING|TEAM_IDENTIFIER|CERT|PROFILE_PATH)',
          multiLine: true,
        ),
      ];

      for (final RegExp pattern in forbidden) {
        expect(source, isNot(matches(pattern)), reason: pattern.pattern);
      }
      expect(source, isNot(contains('security cms -e')));
      expect(source, isNot(contains('security cms -E')));
      expect(source, isNot(contains('codesign -s')));
      expect(source, isNot(contains('codesign --sign')));
      expect(source, isNot(contains('upload')));
      expect(source, isNot(contains('App Store Connect')));
      expect(source, isNot(contains('-----BEGIN')));
      expect(source, isNot(contains('UUID')));
      expect(source, isNot(contains('set -o xtrace')));
    },
  );

  test(
    'release documentation distinguishes real evidence from fake self-test evidence',
    () {
      expect(releaseDocument.existsSync(), isTrue);
      final String document = releaseDocument.readAsStringSync();
      for (final String required in <String>[
        'ios_release_validator.sh',
        '--archive',
        '--expected-bundle-id',
        '--expected-version',
        '--expected-build',
        '--expected-team-id',
        '--ipa',
        '--self-test',
        'read-only',
        'not a real archive',
        'does not prove',
        'sha256',
      ]) {
        expect(
          document.toLowerCase(),
          contains(required.toLowerCase()),
          reason: required,
        );
      }
    },
  );
}
