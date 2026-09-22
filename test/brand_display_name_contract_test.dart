import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user-visible brand name is closed across Flutter and native hosts', () {
    final String appSource = File('lib/app/app.dart').readAsStringSync();
    final String loginSource = File(
      'lib/features/account/presentation/login_page.dart',
    ).readAsStringSync();
    final String androidStrings = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();
    final String iosInfo = File('ios/Runner/Info.plist').readAsStringSync();

    expect(appSource, contains('title: AppBrand.name'));
    expect(loginSource, contains('eyebrow: AppBrand.name'));
    expect(androidStrings, contains('<string name="app_name">搭子岛</string>'));
    expect(iosInfo, contains('<key>CFBundleDisplayName</key>'));
    expect(iosInfo, contains('<string>搭子岛</string>'));
  });

  test('technical identifiers remain unchanged while visible copy changes', () {
    final String androidBuild = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final String iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final String alipayRequestId = File(
      'lib/features/commerce/domain/alipay_request_id.dart',
    ).readAsStringSync();
    final String iapCoordinator = File(
      'lib/features/commerce/application/apple_iap_purchase_coordinator.dart',
    ).readAsStringSync();

    expect(
      androidBuild,
      contains('namespace = "com.kong373.voice_social_app"'),
    );
    expect(
      androidBuild,
      contains('applicationId = "com.kong373.voice_social_app"'),
    );
    expect(
      iosProject,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.kong373.voiceSocialApp;'),
    );
    expect(alipayRequestId, contains('voice-social:alipay-reconcile:'));
    expect(iapCoordinator, contains('voice-social:apple-iap-delivery:'));
  });
}
