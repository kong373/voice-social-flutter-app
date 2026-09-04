# Voice-Social iOS Phase 1 host boundary

## Source binding

- Repository: `kong373/voice-social-flutter-app`
- Base branch: `codex/m5-unified-release-candidate`
- Base SHA: `6b6e35fc03c08431b2c2d6b0147daccd8307c5b9`
- iOS branch: `codex/m5-ios-client`
- Product denominator: the frozen 69-page C-end Flutter scope.

This phase adds an iOS 13 Runner host around the existing Dart application. It
does not redesign a page, add a route, add membership/VIP, or add a gift
backpack.

## Implemented source boundary

- `ios/Runner` uses the Flutter 3.44 implicit-engine and `UIScene` lifecycle.
- `GeneratedPluginRegistrant` is the sole host registration boundary for:
  - `first_party_native_permissions`;
  - `agora_rtc_engine`;
  - `tencent_cloud_chat_sdk`;
  - `flutter_secure_storage`.
- CocoaPods installs the existing Flutter plugins with deployment target 13.0.
- Swift Package Manager is disabled at the project level so CI and local builds
  resolve the pinned native plugin graph through `Podfile.lock` instead of
  cloning mutable provider repositories during an application build.
- `CLIENT_TYPE=iOS` is required for live runs so the backend receives platform
  type 2.
- Microphone, photo-library, photo-save and camera purpose strings describe the
  existing product actions. iOS has no Apple-defined notification purpose
  string key, so `VoiceSocialNotificationUsageDescription` is app-owned
  metadata; the system prompt is still controlled by `UserNotifications`.
- App Pay remains Android-only:
  `ALIPAY_IOS=UNSUPPORTED_FAIL_CLOSED`.
  No iOS Alipay SDK, URL scheme, transaction call or Apple IAP substitute is
  present.

## Static placeholders and deliberately absent Apple capabilities

`com.kong373.voiceSocialApp` is an
`UNREGISTERED_DEVELOPMENT_PLACEHOLDER`. It is suitable only for source-level
and unsigned simulator work until the Apple Developer account confirms the
real application identifier.

Current capability state:

```text
APPLE_TEAM_ID=NOT_CONFIGURED
REGISTERED_BUNDLE_ID=NOT_CONFIGURED
RELEASE_SIGNING=NOT_CONFIGURED
APNS=NOT_CONFIGURED
UNIVERSAL_LINKS=NOT_CONFIGURED
ALIPAY_IOS=UNSUPPORTED_FAIL_CLOSED
```

`Runner.entitlements` is intentionally empty. It contains no APNs environment,
Associated Domains, App Groups or background modes. `Info.plist` contains no
payment URL scheme and no global ATS bypass.

## Verification classification

Source-level tests verify the host manifest, deployment target, plugin
registration seam, permission text, empty entitlements and Android-only
payment boundary.

The following are not proven by merely committing this host:

- CocoaPods resolution and Xcode simulator compilation;
- installation on a signed iPhone;
- microphone, camera, photos and notification prompts on a device;
- Agora join, audio routing, interruption and reconnection on iOS;
- Tencent IM login, C2C callback and AVChatRoom lifecycle on iOS;
- APNs delivery or notification tap routing;
- Universal Links;
- release signing, archive, TestFlight or App Store readiness.

A protected macOS GitHub Actions job performs an unsigned simulator build.
Codex must still repeat Pods, Xcode, simulator and physical-device acceptance
on the authorized Mac and bind evidence to an exact branch SHA.

## Phase exemptions

These statuses are exemptions, not completion claims:

```text
CHUANGLAN_DELIVERY_RECEIPT=EXEMPT
ALIPAY_ASYNC_CALLBACK=EXEMPT
ALIPAY_REFUND=EXEMPT
```

No real SMS, payment or provider transaction is executed by this phase.
