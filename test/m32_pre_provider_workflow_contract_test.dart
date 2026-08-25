import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String workflow = File(
    '.github/workflows/m32-pre-provider-review.yml',
  ).readAsStringSync();
  final String contractServer = File(
    'tool/qa/m32_review_contract_server.py',
  ).readAsStringSync();

  test('M3.2 review workflow pins every action to an immutable commit', () {
    for (final String pinnedAction in <String>[
      'actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683',
      'actions/setup-java@c5195efecf7bdfc987ee8bae7a71cb8b11521c00',
      'subosito/flutter-action@fd55f4c5af5b953cc57a2be44cb082c8f6635e8e',
      'ReactiveCircus/android-emulator-runner@324029e2f414c084d8b15ba075288885e74aef9c',
      'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02',
      'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093',
    ]) {
      expect(workflow, contains(pinnedAction), reason: pinnedAction);
    }
    expect(
      RegExp(r'uses:\s+[^\s#]+@v\d+', multiLine: true).hasMatch(workflow),
      isFalse,
    );
  });

  test('M3.2 AVD review avoids nonessential Google background services', () {
    expect(workflow, contains('target: default'));
    expect(workflow, isNot(contains('target: google_apis')));
    expect(workflow, contains('disable-animations: true'));
    expect(workflow, contains('disable-spellchecker: true'));
  });

  test('M3.2 room flow follows the authoritative lifecycle contract', () {
    expect(
      workflow,
      contains('python3 tool/qa/m32_review_contract_server_test.py'),
    );
    expect(
      contractServer,
      contains('ENTER_ROOM = "/app-room-api/room/com/v1/enterRoom"'),
    );
    expect(
      contractServer,
      contains('EXIT_ROOM = "/app-room-api/room/com/v1/exitRoom"'),
    );
    expect(
      contractServer,
      contains('"contractVersion": "m3.2-review-contract-v3"'),
    );
    expect(
      contractServer,
      contains('if path in {LEGACY_ROOM_SNAPSHOT, ENTER_ROOM}:'),
    );
    expect(contractServer, contains('if path == EXIT_ROOM:'));
  });
}
