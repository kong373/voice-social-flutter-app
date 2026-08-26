# Voice Social Flutter App

Clean-room Flutter client for the authorized reconstruction of a Chinese voice-social product.

The product denominator is frozen at **69 Page IDs**. Product scope, authorized backend behavior, authorized APK evidence, and the new Flutter design system are kept separate so legacy or retired capabilities cannot leak into the new app.

## Current checkpoint — F3/M4 first-party live integration

The current checkpoint is the F3/M4 first-party live integration boundary. The
69-page C-end UI scope is implemented and visually/widget-checked as
`UI_SCOPE=COMPLETE_69_PAGE_C_END`. That is an implementation result, not a
live-backend or emulator-acceptance result: `LIVE_DUAL_AVD_ACCEPTANCE=PENDING`
until the same candidate is exercised on both authoritative AVDs. This checkout
does not claim a live AVD `PASS`.

M0 through M3.3 provide the fixed root navigation, fixed eight-seat room,
discovery, account/social, messages, commerce, community, room PK, and all 69
Page IDs. F3 now carries the first-party HTTP/read contracts into the live
development graph; M4 is the two-AVD live acceptance gate.

The side-effect-free readiness layer still runs before any live authentication
or business request:

```text
runtime configuration validation
→ redacted environment summary
→ DNS / TCP / TLS / HTTP gateway probe
→ explicit readiness result
→ only then allow the authentication integration phase
```

The default debug build remains **mock mode**. Live mode requires authorized non-production configuration and fails closed when values are missing or unsafe.

### First-party and formal-provider status

The following status is canonical for this checkpoint:

| Capability | Current status | Boundary |
| --- | --- | --- |
| First-party HTTP/read contracts | `READY_FOR_F3_LIVE_READS` | Read responses must be server-authoritative and redacted in evidence. |
| Recharge catalog (`CM-002`) | `FIRST_PARTY_READ_READY` | The catalog can be read from the first-party route. |
| Recharge order creation / payment launch (`CM-003`) | `VENDOR_BLOCKED` | Creation and channel invocation fail closed until formal payment adapters are approved. |
| SMS | `VENDOR_BLOCKED` | Development Outbox OTP is test-only and is not formal SMS delivery. |
| RTC | `VENDOR_BLOCKED` | No live media join or publication is claimed. |
| IM | `VENDOR_BLOCKED` | No live realtime/private-message transport is claimed. |
| PAYMENT | `VENDOR_BLOCKED` | No provider order creation, SDK launch, or success is claimed. |
| PUSH | `VENDOR_BLOCKED` | OS notification permission is not push delivery. |
| OBJECT_STORAGE | `VENDOR_BLOCKED` | No provider-backed media upload is claimed. |

All six formal provider boundaries are fail-closed. A development Outbox
response may supply a local development OTP for a controlled test, but it must
never be described as a formal SMS vendor integration or acceptance.

### Video-runtime UI preview

The current frontend candidate includes the video-referenced lobby, discovery, messages, account, fixed eight-seat room, room composer, original reaction/sticker sheet, gift sheet, room tools, and persistent minimize/restore flow. Run the interactive mock preview with:

```bash
flutter run --dart-define=ENABLE_VIDEO_RUNTIME_DEMO=true
```

This switch is debug-only. It uses local repositories and adapters, does not call an RTC, IM, payment, push, SMS, or storage provider, and does not claim a live backend result.

## Scope boundaries

This public repository contains no APK source package, decompiled proprietary source, backend source archive, production host, credential, signing asset, or copied brand material.

The following capabilities remain excluded even when legacy evidence exists:

- commercial memberships/VIP, paid status tiers, and membership privileges;
- gift inventory or a gift backpack;
- red packets;
- KTV, song requests, singing, and chorus;
- blind boxes, magic balls, dango, and love letters;
- random matching, nearby users, scan-to-enter, and unconfirmed games.

Commercial VIP and gift-backpack routes are permanently `RETIRED` /
`OUT_OF_SCOPE`; they are not routes in the 69-page C-end product. Guild
membership and guild member/application governance remain in scope under
`SC-001`/`SC-002` and must not be removed by this commercial exclusion.

## Local setup

CI pins Flutter to `3.44.7`.

```bash
./tool/bootstrap_local.sh
flutter run
```

Golden/widget tests now load their checked-in CJK baseline fonts from
`test/fonts/`. If those files ever need to be regenerated, use
`python3 tool/qa/build_m33_golden_fonts.py` to rebuild the deterministic
subset from the pinned Noto Sans SC upstream commit before re-running tests.

The default mock login accepts any valid mainland China mobile number with a six-digit code. `13900000000` exercises the registration-required branch.

### Live readiness mode

Never commit runtime values. Inject development values locally or through a protected CI environment:

```bash
flutter run \
  --dart-define=BACKEND_MODE=live \
  --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=https://your-authorized-dev-gateway.example/ \
  --dart-define=CLIENT_TYPE=Android \
  --dart-define=CLIENT_INNER_VERSION=6 \
  --dart-define=OAUTH_CLIENT_ID=... \
  --dart-define=API_TIMEOUT_SECONDS=15 \
  --dart-define=LIVE_PROBE_PATH=/
```

On the live login page, `开发环境联调诊断` performs only a side-effect-free gateway transport probe. It does not request an SMS code or attempt authentication.

The manual workflow `.github/workflows/m3-live-contract-preflight.yml` reads values only from the protected GitHub `development` environment and uploads a redacted readiness artifact.

### Live development launcher

For local first-party integration, use [`tool/live_development.sh`](tool/live_development.sh) instead of hand-writing `--dart-define` values. It requires only `API_BASE_URL` and an opaque public `OAUTH_CLIENT_ID` (the caller must still ensure it is public), fixes `BACKEND_MODE=live` and `APP_ENV=development`, forces both Mock-backed shell flags off (`ENABLE_QA_CONSOLE=false` and `ENABLE_VIDEO_RUNTIME_DEMO=false`), passes `ENABLE_AGORA_RTC=false` unless the explicit `--enable-agora-rtc` switch is present, enforces Flutter 3.44.7 / Dart 3.12.2, rejects user Dart-define/Gradle-project-argument/environment aliases and unknown Flutter passthrough options, and fails before Flutter when the target address or configuration is unsafe. Android live runs and builds use a temporary generated host plus the existing audio-only manifest helper, so no ignored `android/` directory is written to the checkout.

```bash
export API_BASE_URL=http://10.0.2.2:18080/
export OAUTH_CLIENT_ID=voice-social-mobile-public

./tool/live_development.sh run --target android-emulator --device emulator-5554
./tool/live_development.sh build-apk --target android-emulator

# Explicitly enable the first-party server-issued Agora audio transport.
./tool/live_development.sh run --target android-emulator --device emulator-5554 --enable-agora-rtc
./tool/live_development.sh build-apk --target android-emulator --enable-agora-rtc
```

Use `http://127.0.0.1:18080/` with `--target host` only for `run` when Flutter itself runs on the Mac; `build-apk` accepts only `--target android-emulator`. `127.0.0.1` is not the Mac host from inside an Android Emulator. `run` requires an explicit `--device` matching its target (Android emulator selector or host selector), while `build-apk` rejects `--device`; ports must be 1 through 65535 and the API value may contain only an optional root `/`. It rejects OAuth client secrets, vendor secrets, `-D`/`--DartDefines`, Gradle define aliases, and `--dart-define-from-file` case-insensitively; ordinary token environment variables are stripped before Flutter runs, and Flutter receives only the launcher's minimal SDK environment rather than host profile/config/auth variables. See [live development](docs/live-development.md).

## Quality checks

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
```

GitHub Actions also generates an isolated Android runner, builds a debug APK, and uploads it as a workflow artifact.

## Documentation

- [Architecture](docs/architecture.md)
- [M1 backend contract](docs/contracts/m1_backend_contract.md)
- [M3.1 live readiness](docs/m3-live-backend-readiness.md)
- [F3/M4 first-party live integration](docs/f3-m4-first-party-live-integration.md)
- [Live development launcher](docs/live-development.md)
- [M3.3 video-runtime UI design QA](design-qa.md)
- [Delivery roadmap](docs/roadmap.md)
- [Security rules](docs/security.md)
