# Voice Social Flutter App

Clean-room Flutter client for the authorized reconstruction of a Chinese voice-social product.

The product denominator is frozen at **69 Page IDs**. Product scope, authorized backend behavior, authorized APK evidence, and the new Flutter design system are kept separate so legacy or retired capabilities cannot leak into the new app.

## Current checkpoint — M1 authentication and room contracts

The executable flow now covers:

```text
AC-001 session restoration
→ AC-002 agreement and privacy consent
→ AC-003 SMS login / registration branch
→ DS-001 room discovery
→ RM-004 room entry through a repository contract
→ fixed 8-seat adapter
→ RTC and realtime gateway ports
→ mic request / mute / leave mic
→ realtime public screen
→ in-room ordinary gift Bottom Sheet
→ reconnect warning and recovery
→ confirmed room exit
```

The default debug build runs in **mock mode** and persists the local login session with secure storage. Live mode uses redacted runtime configuration and the authorized backend contract, but real RTC and realtime SDK drivers are intentionally blocked until their approved provider configuration is supplied.

## Scope boundaries

This public repository contains no APK, decompiled proprietary source, backend source archive, production host, credential, signing asset, or copied brand material.

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

### Live contract mode

Never commit runtime values. Inject them locally or through the CI secret store:

```bash
flutter run \
  --dart-define=BACKEND_MODE=live \
  --dart-define=API_BASE_URL=https://your-authorized-gateway.example \
  --dart-define=CLIENT_TYPE=Android \
  --dart-define=CLIENT_INNER_VERSION=1 \
  --dart-define=OAUTH_CLIENT_ID=... \
  --dart-define=OAUTH_CLIENT_SECRET=...
```

Live room entry remains intentionally unavailable until approved RTC and realtime adapters replace the blocking implementations.

## Quality checks

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

GitHub Actions also generates an isolated Android runner, builds a debug APK, and uploads it as a workflow artifact.

## Documentation

- [Architecture](docs/architecture.md)
- [M1 backend contract](docs/contracts/m1_backend_contract.md)
- [M1 acceptance gate](docs/m1-acceptance.md)
- [Delivery roadmap](docs/roadmap.md)
- [Security rules](docs/security.md)
