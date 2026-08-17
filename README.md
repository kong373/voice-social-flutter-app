# Voice Social Flutter App

Clean-room Flutter client for the authorized reconstruction of a Chinese voice-social product.

The product denominator is frozen at **69 Page IDs**. Product scope, authorized backend behavior, authorized APK evidence, and the new Flutter design system are kept separate so legacy or retired capabilities cannot leak into the new app.

## Current checkpoint — M3 authorized development integration

M0 through M2.4 are merged into `main`. The mock-backed product baseline includes all 69 Page IDs, fixed root navigation, the fixed eight-seat room, discovery, account/social, messages, commerce, community, room PK, and the Android dual-emulator QA harness.

M3.1 adds a side-effect-free live-readiness layer before any real SMS, login, room, wallet, RTC, IM, or payment call is attempted:

```text
runtime configuration validation
→ redacted environment summary
→ DNS / TCP / TLS / HTTP gateway probe
→ explicit readiness result
→ only then allow the authentication integration phase
```

The default debug build remains **mock mode**. Live mode requires authorized non-production configuration and fails closed when values are missing or unsafe.

## Scope boundaries

This public repository contains no APK source package, decompiled proprietary source, backend source archive, production host, credential, signing asset, or copied brand material.

The following capabilities remain excluded even when legacy evidence exists:

- red packets;
- KTV, song requests, singing, and chorus;
- blind boxes, magic balls, dango, and love letters;
- random matching, nearby users, scan-to-enter, and unconfirmed games.

## Local setup

CI pins Flutter to `3.44.7`.

```bash
./tool/bootstrap_local.sh
flutter run
```

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
  --dart-define=OAUTH_CLIENT_SECRET=... \
  --dart-define=API_TIMEOUT_SECONDS=15 \
  --dart-define=LIVE_PROBE_PATH=/
```

On the live login page, `开发环境联调诊断` performs only a side-effect-free gateway transport probe. It does not request an SMS code or attempt authentication.

The manual workflow `.github/workflows/m3-live-contract-preflight.yml` reads values only from the protected GitHub `development` environment and uploads a redacted readiness artifact.

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
- [Delivery roadmap](docs/roadmap.md)
- [Security rules](docs/security.md)
