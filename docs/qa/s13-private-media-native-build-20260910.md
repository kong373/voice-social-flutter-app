# S13 private-media native compile checkpoint

Product source: `653b528` (private image/voice/video UI and identity-bound durable
recovery, including explicit abandonment of an allocated-but-never-sent upload).

2026-09-10 local gates with Flutter 3.44.7 / Dart 3.12.2:

- Main merged related Flutter tests: 341 passed; full analyze: no issues.
- `flutter pub get --enforce-lockfile`: passed; Dart lockfile unchanged.
- Android debug APK: `flutter build apk --debug --no-pub` passed.
- iOS simulator Runner: `flutter build ios --simulator --debug --no-pub` passed.
- Native host/privacy/release-validator contracts: 24 passed. The first check
  exposed an obsolete photo-permission text expectation; the purpose string now
  covers avatars, dynamic/support images and private images/videos explicitly,
  with corresponding meaningful assertions. The original failure log remains.
- Build defines: `BACKEND_MODE=mock`, `APP_ENV=development`, plus `CLIENT_TYPE=iOS`
  for the iOS compile. No running backend or device was required or changed.

The iOS build intentionally adds five already-Dart-locked native path pods:
`audio_session`, `image_picker_ios`, `just_audio`, `record_ios`, and
`video_player_avfoundation`. Registry pods, their versions/checksums, the
Podfile, and the previously locked native graph are unchanged. The generated
Podfile.lock is checked in so clean CI resolves this same graph.

Logs retained in the workspace product evidence directory:
`s13-private-media-main-tests.log`, `s13-private-media-main-analyze.log`,
`s13-private-media-main-pubget.log`, `s13-private-media-main-android-build.log`,
and `s13-private-media-main-ios-build.log`.

These are compile and automated-code gates, not live media proof, a signed
release, or store readiness. Permission prompts, picker cancellation, native
record/playback lifecycle, cold-process recovery and two-user media display
still require the later same-candidate Android/iOS device acceptance. No new
installation, provider call, payment, public deployment or financial DB write
was performed for this checkpoint.
