import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_environment.dart';

void main() {
  group('iOS runtime contract', () {
    test('iOS identifies itself as backend platform type 2', () {
      final AppEnvironment environment = AppEnvironment.fromResolvedValues(
        backendModeValue: 'live',
        deploymentValue: 'development',
        timeoutValue: '15',
        apiBaseUrl: 'http://127.0.0.1:18080/',
        clientType: 'iOS',
        clientInnerVersion: '6',
        oauthClientId: 'voice-social-mobile-public',
        realtimeEndpoint: '',
        liveProbePath: '/',
        allowInsecureHttp: true,
        releaseBuild: false,
      );

      expect(environment.platformType, 2);
      expect(environment.clientType, 'iOS');
      expect(environment.enableAlipayAppPay, isFalse);
      expect(environment.useAlipaySandbox, isFalse);
      expect(environment.validateLiveConfiguration, returnsNormally);
    });
  });

  group('committed iOS host', () {
    const List<String> requiredFiles = <String>[
      'ios/Podfile',
      'ios/Flutter/AppFrameworkInfo.plist',
      'ios/Flutter/Debug.xcconfig',
      'ios/Flutter/Release.xcconfig',
      'ios/Runner/AppDelegate.swift',
      'ios/Runner/SceneDelegate.swift',
      'ios/Runner/Info.plist',
      'ios/Runner/Runner-Bridging-Header.h',
      'ios/Runner/Runner.entitlements',
      'ios/Runner/Base.lproj/Main.storyboard',
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png',
      'ios/Runner.xcodeproj/project.pbxproj',
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
      'ios/Runner.xcworkspace/contents.xcworkspacedata',
      'ios/RunnerTests/RunnerTests.swift',
      'docs/ios/phase1-ios-host.md',
      '.github/workflows/m5-ios-client.yml',
    ];

    test('contains a complete tracked Runner source host', () {
      for (final String path in requiredFiles) {
        expect(File(path).existsSync(), isTrue, reason: 'missing $path');
      }
      final List<String> rootIgnore = File('.gitignore').readAsLinesSync();
      expect(
        rootIgnore,
        isNot(contains('ios/')),
        reason: 'the committed root iOS host must not be ignored',
      );
    });

    test('pins iOS 13 and keeps signing identifiers as placeholders', () {
      final String project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(
        RegExp(
          r'IPHONEOS_DEPLOYMENT_TARGET = 13\.0;',
        ).allMatches(project).length,
        greaterThanOrEqualTo(3),
      );
      expect(
        project,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.kong373.voiceSocialApp;'),
      );
      expect(
        project,
        contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'),
      );
      expect(project, isNot(contains('DEVELOPMENT_TEAM =')));
    });

    test('declares truthful permission purposes without provider claims', () {
      final String info = File('ios/Runner/Info.plist').readAsStringSync();
      expect(info, contains('<key>NSMicrophoneUsageDescription</key>'));
      expect(info, contains('语音房上麦和实时语音交流'));
      expect(info, contains('<key>NSPhotoLibraryUsageDescription</key>'));
      expect(info, contains('选择头像或动态图片'));
      expect(info, contains('<key>NSPhotoLibraryAddUsageDescription</key>'));
      expect(info, contains('<key>NSCameraUsageDescription</key>'));
      expect(info, contains('拍摄头像或动态照片'));
      expect(
        info,
        contains('<key>VoiceSocialNotificationUsageDescription</key>'),
      );
      expect(info, contains('私信、房间互动和系统通知提醒'));
      expect(info, contains('<key>UIApplicationSceneManifest</key>'));
      expect(info, isNot(contains('<key>CFBundleURLTypes</key>')));
    });

    test('keeps unconfigured Apple capabilities absent and fail-closed', () {
      final String entitlements = File(
        'ios/Runner/Runner.entitlements',
      ).readAsStringSync();
      expect(entitlements, isNot(contains('aps-environment')));
      expect(
        entitlements,
        isNot(contains('com.apple.developer.associated-domains')),
      );
      expect(entitlements, isNot(contains('application-groups')));

      final String alipayPlugin = File(
        'packages/alipay_app_pay/pubspec.yaml',
      ).readAsStringSync();
      expect(alipayPlugin, contains('First-party Android bridge'));
      expect(alipayPlugin, isNot(contains('\n      ios:')));
    });

    test('installs Flutter plugins through CocoaPods and implicit engine', () {
      final String podfile = File('ios/Podfile').readAsStringSync();
      expect(podfile, contains("platform :ios, '13.0'"));
      expect(podfile, contains('flutter_install_all_ios_pods'));
      expect(podfile, contains('use_frameworks!'));
      expect(
        podfile,
        contains(
          "config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'",
        ),
      );

      final String delegate = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();
      expect(delegate, contains('FlutterImplicitEngineDelegate'));
      expect(delegate, contains('GeneratedPluginRegistrant.register'));

      final String scene = File(
        'ios/Runner/SceneDelegate.swift',
      ).readAsStringSync();
      expect(scene, contains('FlutterSceneDelegate'));
    });

    test('documents static, verified, pending and exempt boundaries', () {
      final String document = File(
        'docs/ios/phase1-ios-host.md',
      ).readAsStringSync();
      expect(document, contains('6b6e35fc03c08431b2c2d6b0147daccd8307c5b9'));
      expect(document, contains('com.kong373.voiceSocialApp'));
      expect(document, contains('UNREGISTERED_DEVELOPMENT_PLACEHOLDER'));
      expect(document, contains('ALIPAY_IOS=UNSUPPORTED_FAIL_CLOSED'));
      expect(document, contains('APNS=NOT_CONFIGURED'));
      expect(document, contains('UNIVERSAL_LINKS=NOT_CONFIGURED'));
      expect(document, contains('ALIPAY_ASYNC_CALLBACK=EXEMPT'));
      expect(document, contains('ALIPAY_REFUND=EXEMPT'));
      expect(document, contains('CHUANGLAN_DELIVERY_RECEIPT=EXEMPT'));
    });
  });
}
