import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
      'ios/Flutter/Profile.xcconfig',
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
      'tool/qa/verify_ios_pod_lock.py',
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

    test('uses the frozen Voice Social brand icon', () {
      final File master = File(
        'assets/branding/voice-social-app-icon-1024.png',
      );
      final File appIcon = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png',
      );
      expect(master.existsSync(), isTrue);
      expect(appIcon.existsSync(), isTrue);
      for (final File icon in <File>[master, appIcon]) {
        expect(iosPngDimensions(icon), (1024, 1024));
        expect(
          sha256.convert(icon.readAsBytesSync()).toString(),
          '515e50dc2863b8d59c9e757ce5b90ae53fcdefde69cb6683fba0a17ac0ad6bd4',
        );
      }
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

    test(
      'implements camera permission through the first-party native bridge',
      () {
        final String swift = File(
          'packages/first_party_native_permissions/ios/'
          'first_party_native_permissions/Sources/'
          'first_party_native_permissions/FirstPartyNativePermissionsPlugin.swift',
        ).readAsStringSync();
        expect(swift, contains('case "camera"'));
        expect(swift, contains('AVCaptureDevice.authorizationStatus'));
        expect(swift, contains('AVCaptureDevice.requestAccess'));
      },
    );

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
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('enable-swift-package-manager: false'));

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
      final String profileConfig = File(
        'ios/Flutter/Profile.xcconfig',
      ).readAsStringSync();
      expect(
        profileConfig,
        contains(
          'Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig',
        ),
      );
      expect(profileConfig, contains('#include "Generated.xcconfig"'));
      final String project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(project, contains('path = Flutter/Profile.xcconfig;'));
      expect(
        project,
        contains(
          'baseConfigurationReference = C1A0503A2C92800100A10001 /* Profile.xcconfig */;',
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

    test(
      'keeps the iOS workflow read-only and normalizes helper toolchains',
      () {
        final String workflow = File(
          '.github/workflows/m5-ios-client.yml',
        ).readAsStringSync();
        expect(workflow, contains('      - main'));
        expect(workflow, contains('permissions:\n  contents: read'));
        expect(workflow, isNot(contains('contents: write')));
        expect(workflow, isNot(contains('git push')));
        expect(workflow, isNot(contains('git commit')));
        expect(
          workflow,
          contains('Canonicalize inherited Android toolchain paths'),
        );
        expect(workflow, contains('Enforce iOS-only branch scope'));
        expect(
          workflow,
          contains("github.ref_name == 'codex/m5-ios-client-reviewed'"),
        );
        expect(workflow, contains('canonical_java_home='));
        expect(workflow, contains('canonical_sdk_root='));
        expect(workflow, contains('Generate isolated Android wrapper'));
        expect(workflow, contains('if [[ -d android ]]; then'));
        expect(
          workflow,
          contains('git ls-files --error-unmatch android/gradlew'),
        );
        expect(workflow, contains("readonly COCOAPODS_VERSION='1.16.2'"));
        expect(
          workflow,
          contains(
            'gem install --user-install cocoapods --version '
            '\\\n              "\$COCOAPODS_VERSION" --no-document',
          ),
        );
        expect(workflow, contains('Gem.user_dir'));
        expect(
          workflow,
          contains(
            'cocoapods_wrapper_dir="\${RUNNER_TEMP}/voice-social-cocoapods-bin"',
          ),
        );
        expect(workflow, contains('cat > "\$cocoapods_wrapper_dir/pod" <<EOF'));
        expect(
          workflow,
          contains('echo "\$cocoapods_wrapper_dir" >> "\$GITHUB_PATH"'),
        );
        expect(
          workflow,
          isNot(
            contains('echo "\$(dirname "\$cocoapods_bin")" >> "\$GITHUB_PATH"'),
          ),
        );
        expect(
          workflow,
          contains('"\$cocoapods_wrapper_dir/pod" install --no-repo-update'),
        );
        expect(workflow, isNot(contains('install --deployment')));
        expect(workflow, isNot(contains('pod install --repo-update')));
        expect(workflow, isNot(contains('pod update')));
        expect(workflow, contains('Podfile.lock.expected'));
        expect(workflow, contains('verify_ios_pod_lock.py'));
        expect(
          workflow,
          contains('cmp -s ios/Podfile.lock ios/Pods/Manifest.lock'),
        );
        expect(workflow, contains('git diff --exit-code --'));
      },
    );

    test('keeps the resolved Pod lock paired through native tests', () {
      final String workflow = File(
        '.github/workflows/m5-ios-client.yml',
      ).readAsStringSync();
      final int nativeTests = workflow.indexOf(
        '- name: Run local StoreKit 2 native tests',
      );
      final int restoreLock = workflow.indexOf(
        'cp "\${RUNNER_TEMP}/voice-social-Podfile.lock.expected"',
      );
      expect(nativeTests, greaterThanOrEqualTo(0));
      expect(
        restoreLock,
        greaterThan(nativeTests),
        reason:
            'restoring the tracked lock before xcodebuild breaks its '
            'pair with the resolved Pods/Manifest.lock',
      );
      final String nativeStep = workflow.substring(
        nativeTests,
        workflow.indexOf('\n      - name:', nativeTests + 1),
      );
      expect(nativeStep, contains('verify_ios_pod_lock.py'));
      expect(
        nativeStep,
        contains('cmp -s ios/Podfile.lock ios/Pods/Manifest.lock'),
      );
      final String restoreStep = workflow.substring(
        workflow.lastIndexOf('\n      - name:', restoreLock),
        workflow.indexOf('\n      - name:', restoreLock),
      );
      expect(restoreStep, contains('if: always()'));
      expect(restoreStep, contains('git diff --exit-code --'));
      expect(
        workflow,
        isNot(contains('cp ios/Podfile.lock ios/Pods/Manifest.lock')),
      );
    });

    test('allows only local path-pod checksum portability drift', () {
      final Directory sandbox = Directory.systemTemp.createTempSync(
        'ios-pod-lock-contract-',
      );
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final File expected = File('${sandbox.path}/expected.lock');
      final File actual = File('${sandbox.path}/actual.lock');
      const String prefix = '''PODS:
  - LocalPod (1.0.0)
  - RemotePod (2.0.0)

DEPENDENCIES:
  - LocalPod (from `.symlinks/plugins/local/ios`)
  - RemotePod

SPEC REPOS:
  trunk:
    - RemotePod

EXTERNAL SOURCES:
  LocalPod:
    :path: ".symlinks/plugins/local/ios"

SPEC CHECKSUMS:
''';
      const String suffix = '''
PODFILE CHECKSUM: 3333333333333333333333333333333333333333

COCOAPODS: 1.16.2
''';
      expected.writeAsStringSync(
        '${prefix}  LocalPod: 1111111111111111111111111111111111111111\n'
        '  RemotePod: 2222222222222222222222222222222222222222\n'
        '$suffix',
      );
      actual.writeAsStringSync(
        '${prefix}  LocalPod: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
        '  RemotePod: 2222222222222222222222222222222222222222\n'
        '$suffix',
      );

      ProcessResult verify() => Process.runSync('python3', <String>[
        'tool/qa/verify_ios_pod_lock.py',
        expected.path,
        actual.path,
      ]);

      expect(verify().exitCode, 0);

      actual.writeAsStringSync(
        '${prefix}  LocalPod: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
        '  RemotePod: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n'
        '$suffix',
      );
      expect(verify().exitCode, isNot(0));

      actual.writeAsStringSync(
        '${prefix.replaceFirst('LocalPod (1.0.0)', 'LocalPod (1.0.1)')}'
        '  LocalPod: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
        '  RemotePod: 2222222222222222222222222222222222222222\n'
        '$suffix',
      );
      expect(verify().exitCode, isNot(0));

      actual.writeAsStringSync(
        '${prefix}  LocalPod: not-a-checksum\n'
        '  RemotePod: 2222222222222222222222222222222222222222\n'
        '$suffix',
      );
      expect(verify().exitCode, isNot(0));
    });

    test(
      'tracks one immutable Pod lock and removes self-mutating workflows',
      () {
        expect(File('ios/Podfile.lock').existsSync(), isTrue);
        final ProcessResult trackedLock = Process.runSync('git', <String>[
          'ls-files',
          '--error-unmatch',
          'ios/Podfile.lock',
        ]);
        expect(trackedLock.exitCode, 0);

        for (final String path in <String>[
          '.github/workflows/ios-phase1-authoritative.yml',
          '.github/workflows/ios-phase1-bootstrap.yml',
          '.github/workflows/ios-phase1-finalize.yml',
          '.github/workflows/ios-phase1-reconcile.yml',
        ]) {
          expect(File(path).existsSync(), isFalse, reason: path);
        }
      },
    );

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

(int, int) iosPngDimensions(File file) {
  final Uint8List bytes = file.readAsBytesSync();
  if (bytes.length < 24 ||
      bytes[0] != 0x89 ||
      bytes[1] != 0x50 ||
      bytes[2] != 0x4e ||
      bytes[3] != 0x47) {
    throw StateError('Not a PNG: ${file.path}');
  }
  final ByteData data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}
