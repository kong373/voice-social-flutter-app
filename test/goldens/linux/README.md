# M3.3 Linux golden baselines

These baselines are the reviewed Linux counterparts of the 69 page captures
and 14 video-runtime state captures under `test/goldens`.

- Source run: GitHub Actions `32470068814`
- Source commit: `66adfdf1eef2499b973a070e2d9691cb694dd2d3`
- Runner: Ubuntu 24.04
- Flutter: 3.44.7
- Viewport: 390 x 844 at DPR 1.0
- Source files: the workflow-retained `*_testImage.png` failure diagnostics

The Linux set is intentionally separate because Skia glyph rasterization and
anti-aliasing differ from macOS. The strict comparators and their existing
tolerances remain unchanged; unsupported host platforms fail closed instead
of silently borrowing another platform's images.
