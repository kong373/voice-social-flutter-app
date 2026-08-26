import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String flutterCi = File(
    '.github/workflows/flutter-ci.yml',
  ).readAsStringSync();
  final String formatAutofix = File(
    '.github/workflows/m32-candidate-format-autofix.yml',
  ).readAsStringSync();
  final String snapshotAutofix = File(
    '.github/workflows/m32-snapshot-only-autofix.yml',
  ).readAsStringSync();
  final String reviewPublisher = File(
    '.github/workflows/m32-review-result-publisher.yml',
  ).readAsStringSync();

  test('flutter ci stays read-only and uses pinned actions', () {
    expect(flutterCi, contains('permissions:\n  contents: read'));
    for (final String pinnedAction in <String>[
      'actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4',
      'subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2',
      'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4',
    ]) {
      expect(flutterCi, contains(pinnedAction), reason: pinnedAction);
    }
    expect(flutterCi, isNot(contains('contents: write')));
  });

  test('only the live Android debug APK opts into Agora RTC', () {
    final int androidStart = flutterCi.indexOf('  android-debug:');
    expect(androidStart, greaterThanOrEqualTo(0));
    final String quality = flutterCi.substring(0, androidStart);
    final String android = flutterCi.substring(androidStart);

    expect(android, contains('--dart-define=ENABLE_AGORA_RTC=true'));
    expect(quality, isNot(contains('--dart-define=ENABLE_AGORA_RTC=true')));
    expect(android, isNot(contains('--dart-define=CLIENT_SECRET')));
    expect(android, isNot(contains('--dart-define=OAUTH_CLIENT_SECRET')));
  });

  test('autofix workflows are manual-only and scope write permission', () {
    for (final String workflow in <String>[formatAutofix, snapshotAutofix]) {
      expect(workflow, contains('on:\n  workflow_dispatch:'));
      expect(workflow, isNot(contains('  push:')));
      expect(
        workflow,
        contains(
          "if: github.ref == 'refs/heads/feat/m3-2a-live-auth-readonly'",
        ),
      );
      expect(workflow, contains('permissions:\n  contents: read'));
      expect(workflow, contains('    permissions:\n      contents: write'));
      expect(workflow, contains('concurrency:'));
      expect(
        workflow,
        contains(
          'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2',
        ),
      );
      expect(
        workflow,
        contains(
          'subosito/flutter-action@fd55f4c5af5b953cc57a2be44cb082c8f6635e8e # v2.21.0',
        ),
      );
      expect(workflow, isNot(contains('uses: actions/checkout@v4')));
      expect(workflow, isNot(contains('uses: subosito/flutter-action@v2')));
    }
  });

  test('workflow-run publisher requires upstream success before writing', () {
    expect(reviewPublisher, contains('permissions:\n  contents: read'));
    expect(
      reviewPublisher,
      contains('    permissions:\n      contents: write'),
    );
    expect(
      reviewPublisher,
      contains("github.event.workflow_run.conclusion == 'success' &&"),
    );
    expect(
      reviewPublisher,
      contains("github.event.workflow_run.event == 'push' &&"),
    );
    expect(
      reviewPublisher,
      contains(
        'github.event.workflow_run.head_repository.full_name == '
        'github.repository &&',
      ),
    );
    expect(
      reviewPublisher,
      contains('ref: \${{ github.event.repository.default_branch }}'),
    );
    expect(
      reviewPublisher,
      contains(
        'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2',
      ),
    );
    expect(reviewPublisher, isNot(contains('uses: actions/checkout@v4')));
  });
}
