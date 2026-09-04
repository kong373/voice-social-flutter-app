import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current;

  File workspaceFile(String path) => File('${root.path}/$path');

  String projectBlock(String project, String marker) {
    final start = project.indexOf(marker);
    expect(
      start,
      isNonNegative,
      reason: 'Missing Xcode project marker: $marker',
    );
    final end = project.indexOf('\n\t\t};', start);
    expect(end, greaterThan(start), reason: 'Unterminated Xcode project block');
    return project.substring(start, end);
  }

  test('Runner packages the app privacy manifest at the app bundle root', () {
    final manifest = workspaceFile('ios/Runner/PrivacyInfo.xcprivacy');
    expect(
      manifest.existsSync(),
      isTrue,
      reason: 'Runner must declare an app-level PrivacyInfo.xcprivacy',
    );

    final contents = manifest.readAsStringSync();
    expect(contents, contains('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(contents, contains('<key>NSPrivacyTracking</key>'));
    expect(contents, contains('<key>NSPrivacyCollectedDataTypes</key>'));
    expect(contents, contains('<key>NSPrivacyAccessedAPITypes</key>'));
    expect(
      contents,
      isNot(contains('<key>NSPrivacyTracking</key>\n  <true/>')),
    );

    const requiredDataTypes = <String>[
      'NSPrivacyCollectedDataTypeName',
      'NSPrivacyCollectedDataTypePhoneNumber',
      'NSPrivacyCollectedDataTypeUserID',
      'NSPrivacyCollectedDataTypeDeviceID',
      'NSPrivacyCollectedDataTypeOtherUserContent',
      'NSPrivacyCollectedDataTypePurchaseHistory',
      'NSPrivacyCollectedDataTypeSearchHistory',
      'NSPrivacyCollectedDataTypeProductInteraction',
      'NSPrivacyCollectedDataTypeCustomerSupport',
    ];
    for (final dataType in requiredDataTypes) {
      expect(contents, contains(dataType));
    }

    expect(
      contents,
      isNot(
        contains('NSPrivacyCollectedDataTypeTracking</key>\n      <true/>'),
      ),
    );
    expect(contents, isNot(contains('NSPrivacyAccessedAPICategory')));

    final projectFile = workspaceFile('ios/Runner.xcodeproj/project.pbxproj');
    expect(projectFile.existsSync(), isTrue);
    final project = projectFile.readAsStringSync();
    final fileReference = RegExp(
      r'([A-F0-9]{24}) /\* PrivacyInfo\.xcprivacy \*/ = \{isa = PBXFileReference;',
    ).firstMatch(project);
    final buildFile = RegExp(
      r'([A-F0-9]{24}) /\* PrivacyInfo\.xcprivacy in Resources \*/ = \{isa = PBXBuildFile;',
    ).firstMatch(project);
    expect(fileReference, isNotNull);
    expect(buildFile, isNotNull);

    final runnerGroup = projectBlock(
      project,
      '97C146F01CF9000F007C117D /* Runner */ = {',
    );
    expect(
      runnerGroup,
      contains('${fileReference!.group(1)} /* PrivacyInfo.xcprivacy */'),
    );

    final resources = projectBlock(
      project,
      '97C146EC1CF9000F007C117D /* Resources */ = {',
    );
    expect(
      resources,
      contains(
        '${buildFile!.group(1)} /* PrivacyInfo.xcprivacy in Resources */',
      ),
    );
  });

  test(
    'privacy manifest documentation records code evidence and owner review',
    () {
      final documentation = workspaceFile('docs/ios-privacy-manifest.md');
      expect(documentation.existsSync(), isTrue);
      final contents = documentation.readAsStringSync();
      expect(contents, contains('Apple privacy manifest'));
      expect(contents, contains('external owner input'));
      expect(contents, contains('third-party SDK'));
      expect(contents, contains('not legal approval'));
    },
  );
}
