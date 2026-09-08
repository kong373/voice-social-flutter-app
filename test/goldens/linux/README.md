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
