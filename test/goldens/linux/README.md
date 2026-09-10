# M3.3 Linux golden baselines

These baselines are the reviewed Linux counterparts of the 69 page captures
and 14 video-runtime state captures under `test/goldens`.

- Base source run: GitHub Actions `32470068814`
- Base source commit: `66adfdf1eef2499b973a070e2d9691cb694dd2d3`
- Candidate-delta refresh run: GitHub Actions `32699436678`
- Candidate-delta refresh commit: `b87f9980eb0de4ccc568312092e7fd5f87ec05b8`
- Candidate-delta refresh scope: 15 reviewed baselines matching the 15 macOS
  baselines changed by the M4 first-party live-integration candidate
- Runner: Ubuntu 24.04
- Flutter: 3.44.7
- Viewport: 390 x 844 at DPR 1.0
- Source files: the workflow-retained `*_testImage.png` failure diagnostics

The Linux set is intentionally separate because Skia glyph rasterization and
anti-aliasing differ from macOS. The strict comparators and their existing
tolerances remain unchanged; unsupported host platforms fail closed instead
of silently borrowing another platform's images.

## Release user-copy refresh (2026-09-08)

- Source run: GitHub Actions `34195373766`, artifact
  `flutter-quality-34195373766-1` (`10044275551`)
- Source commit: `b4db7fe762ddadc0ed6c304f6e1e010970899cce`
- Scope: `m3_3_all/ac-003_390x844.png`, `ac-004_390x844.png`, and
  `us-002_390x844.png`, copied from the retained `*_testImage.png` captures
- Reason: `b332824` replaced developer-facing copy on these three pages;
  `de20526` refreshed their reviewed macOS baselines but omitted Linux.
- Review: the Linux captures show the same current user copy and layout as
  those macOS baselines, retaining Linux font rasterization. Both source runs
  (`34195373766` and `34195372842`) reported the same three mismatches and
  1847 passing tests. No comparator, tolerance, or test selection changed.

## Preset avatar gallery (2026-09-10)

- Source commit: `39088718e85a57fc0c8b3b7af17609427b332d97`, including the
  expanded checked-in Noto CJK subsets. The avatar test, artwork source, and
  `RegistrationAvatarCjkSupplement.otf` are unchanged from `8fc6cd5`.
- New baseline only: `preset_avatar_gallery_360.png`, 360 x 460 at DPR 1.0.
- Renderer: Ubuntu 24.04.4, `linux/amd64`, Flutter 3.44.7 / Dart 3.12.2;
  Flutter revision `84fc5cbb223bc12f83d65b647ff8a56caf779ffd`.
- The matching Linux SDK and public package cache were reused. Rendering was
  offline in one container limited to 1 CPU / 1 GiB; no database, device,
  external provider, host environment files, or Docker socket were used.
- `flutter pub get --offline --enforce-lockfile`: exit 0, unchanged lockfile.
  New-source missing-baseline RED: one failure, exit 1. Generation and strict
  non-update verification below each ran the same one test and exited 0.

```sh
flutter test --no-pub --concurrency=1 --reporter expanded --update-goldens test/preset_avatar_visual_test.dart
flutter test --no-pub --concurrency=1 --reporter expanded test/preset_avatar_visual_test.dart
```

PNG SHA-256:
`dcc912faa577d749b558734ea6510e92115291ca9589c32d7239bb0faebb9279`.

Visual review against the approved macOS gallery:

```json
{"score":96,"verdict":"pass","category_match":true,"differences":["Linux text edges and apparent weight differ from macOS; layout, colors and artwork agree."],"suggestions":[],"reasoning":"All six avatars, Chinese labels, selected star-fox ring/check and small silhouettes are complete, without missing glyphs, clipping or overflow."}
```

This is a genuine Linux render, not a copy of the macOS PNG. The other 83 Linux
PNGs, all macOS PNGs, test code, comparators and tolerances were not changed.
The initial cold compilation at the old source hit the container's memory
limit; cached subsequent runs completed without another OOM. That failed log
is retained, not counted as a passing test. The matching container and caches
are retained for later explicitly scoped Linux rendering, not a claim that
the remaining pages or runtime states have been refreshed.
