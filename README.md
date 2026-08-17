# Voice Social Flutter App

Clean-room Flutter client for the authorized reconstruction of a Chinese voice-social product.

The fixed product denominator is **69 Page IDs**. The first executable slice implements the selected dark premium direction and a working flow:

```text
Home room discovery
→ enter room directly
→ fixed 8 microphone seats
→ request a seat
→ realtime-screen demo
→ open gift Bottom Sheet in the room
→ weak-network recovery demo
→ confirm and leave the room
```

## Important boundaries

- This public repository contains no APK, decompiled proprietary source, backend source, production endpoint, secret, credential, or copied brand asset.
- Legacy backend and APK capabilities are evidence, not automatic product scope.
- Red packets, KTV/song-request/singing/chorus, blind boxes, magic balls, dango, and love letters are excluded.
- The current data layer is local demonstration code. Real HTTP, realtime, RTC, payment, and persistence adapters are not connected yet.

## Local setup

Flutter is pinned to `3.44.7` in CI.

```bash
./tool/bootstrap_local.sh
flutter run
```

The bootstrap script generates standard Android and iOS runner folders locally. They are intentionally ignored during M0 so the source review stays focused on application architecture.

## Quality checks

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

GitHub Actions also builds an Android debug APK in an isolated generated runner and uploads it as a workflow artifact.

## Documentation

- [Architecture](docs/architecture.md)
- [Delivery roadmap](docs/roadmap.md)
- [Security rules](docs/security.md)
