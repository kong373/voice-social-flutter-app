import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String androidManifest = File(
    'packages/first_party_native_permissions/android/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final String iosPatchScript = File(
    'tool/apply_native_permissions.sh',
  ).readAsStringSync();
  final String androidPlugin = File(
    'packages/first_party_native_permissions/android/src/main/kotlin/com/kong373/first_party_native_permissions/FirstPartyNativePermissionsPlugin.kt',
  ).readAsStringSync();
  final String iosPlugin = File(
    'packages/first_party_native_permissions/ios/first_party_native_permissions/Sources/first_party_native_permissions/FirstPartyNativePermissionsPlugin.swift',
  ).readAsStringSync();

  test(
    'native permission host declares only the three product capabilities',
    () {
      for (final String permission in <String>[
        'android.permission.RECORD_AUDIO',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
        'android.permission.READ_EXTERNAL_STORAGE',
      ]) {
        expect(androidManifest, contains(permission));
      }
      for (final String forbidden in <String>[
        'android.permission.CAMERA',
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.READ_CONTACTS',
        'android.permission.READ_PHONE_STATE',
      ]) {
        expect(androidManifest, isNot(contains(forbidden)));
      }
    },
  );

  test('iOS usage descriptions are owned by the generated app host', () {
    expect(iosPatchScript, contains('NSMicrophoneUsageDescription'));
    expect(iosPatchScript, contains('NSPhotoLibraryUsageDescription'));
    expect(iosPatchScript, isNot(contains('NSCameraUsageDescription')));
    expect(
      iosPatchScript,
      isNot(contains('NSLocationWhenInUseUsageDescription')),
    );
  });

  test(
    'external upgrade navigation stays a strict HTTPS first-party bridge',
    () {
      expect(androidPlugin, contains('openExternalUrl'));
      expect(androidPlugin, contains('Intent.ACTION_VIEW'));
      expect(androidPlugin, contains('scheme?.lowercase() != "https"'));
      expect(iosPlugin, contains('case "openExternalUrl"'));
      expect(iosPlugin, contains('UIApplication.shared.open'));
      expect(iosPlugin, contains('url.scheme?.lowercased() == "https"'));
    },
  );
}
