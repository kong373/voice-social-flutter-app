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

## Partial product-page refresh (2026-09-10)

This section preserves the earlier 61-PASS checkpoint. The later runtime and
gallery verification is recorded separately below; the old OOM is not erased.

Source: `0b9d1208dd854c9b89a44c16711805f795a83985`. This includes product
`e5bf9c7229786d36b410f61faf4ae7cd838bdac5` and the reviewed post-unmount
35 ms fake-time drain from `46abea669e9454ee80299dea6129bdbbb7538bdb`.
The drain does not change capture timing, assertions, or comparator tolerance.

Only these 24 actual Linux-rendered, visually reviewed page PNGs are refreshed
under `m3_3_all/` (each filename is `<lowercase-id>_390x844.png`):

- AC: 002, 005, 012
- CM: 001, 002, 010, 012
- DS: 001, 003, 005, 006, 007, 008
- MS: 001
- RM: 001, 002, 004, 005, 013, 014
- SC: 001, 002
- US: 001, 002

The review checked current copy, the fixed Mock clock, CM-002 layout,
DS-001 nine-seat card, room dark-theme rendering, expanded checked-in Noto
glyphs, and RM-013 automatic-sync copy against the approved product source
and macOS references. These are not macOS PNG copies. DS-003 and DS-008
also contain small reviewed changes below the existing page tolerance.
All 24 candidate hashes match the committed copies. The nine retired page
archives, 14 runtime PNGs, gallery PNG, macOS PNGs, fonts, test code, and CI
configuration are unchanged by this refresh.

Renderer: Ubuntu 24.04.4 `linux/amd64`, Flutter 3.44.7 / Dart 3.12.2,
Flutter revision `84fc5cbb223bc12f83d65b647ff8a56caf779ffd`; 390 x 844,
DPR 1.0. The existing SDK/public package/build caches were reused offline
with 1 CPU and a 1.25 GiB container memory limit. No database was started.

All-pages generation and strict comparison ran in separate bounded processes
per group. Both phases' exact test-ID unions equal the 60 active
`qaPageCatalog` IDs, without missing, extra, or duplicate IDs:

| Group | Update exit 0 | Strict exit 0 |
| --- | ---: | ---: |
| AC | 12 | 12 |
| CM | 10 | 10 |
| DS | 8 | 8 |
| MS | 6 | 6 |
| RM | 12 | 12 |
| SC | 3 | 3 |
| US | 9 | 9 |

Each group used `flutter test --no-pub --concurrency=1 --reporter expanded`
with an anchored `--name '^(?:<exact group IDs>) '` selector and
`test/m33_all_pages_visual_golden_test.dart`; generation alone added
`--update-goldens`. The all-pages missing-font negative test ran separately
and passed once. Final group phases had no new OOM. The preliminary RM
strict probe is excluded from the final count, as are all update runs.
**The result is 61 unique strict PASS, not the planned 66.**

Runtime four tests and gallery one test remain incomplete at this source.
The runtime RED command selected three widget tests in one process, but OOM
occurred inside the first: `M3.3 video-runtime visual states at 390x844`
(`test/video_runtime_visual_golden_test.dart:41`). Home, room, and expression
comparisons reported real differences of 70, 111288, and 78004 pixels before
OOM. Gift comparison has no completion evidence; the second and third tests
had not started. Thus this is not evidence of three-test accumulation, nor
proof that isolating the first test in a process will avoid OOM. Per-process
peak memory was not measured. The runtime font negative and current-source
gallery strict test were not run; the older gallery PASS above is not counted.

Runtime handle `65521` exited 125 after `oom_kill` increased from 0 to 1;
the compiler then reported an unexpected exit. The owned container was
stopped, and the resource/DB slot returned. SDK, package/build caches, source
snapshot, partial runtime failure images, and resource logs remain available.
No runtime baseline was accepted, no tolerance changed, and no CI run or push
was initiated. The existing full CI test selection remains unchanged.

Evidence is retained under the workspace-root artifact directory
`artifacts/product/filled-decisions-20260909/linux-product-goldens-0b9d120-lcBLwc/`:
`page-set-verification.json` records the exact phase ID sets;
`candidate-hash-audit.json` records all 24 PNG SHA-256 values;
`offline-visual-review.json` records their visual review;
`shard-*-{update,strict}.log`, final `shard-RM-*-complete.log`, and
`all-pages-fontgate.log` retain successful command evidence;
`runtime-red.log`, `runtime-red-failures/`, and `source-resource.log` retain
the incomplete runtime and controlled-resource evidence. Earlier failed
monolithic runs remain separate and are not reported as golden PASS.

## Runtime and gallery verification (2026-09-10)

Render/test source remains `0b9d1208dd854c9b89a44c16711805f795a83985`.
Local parent `72a908f482e9ebb8b7fdc07ef0a9c0190fbee37b` adds only the
24 reviewed page PNGs and README above, not product code, fonts, or tests.
The renderer remains Ubuntu 24.04.4 `linux/amd64`, Flutter 3.44.7 /
Dart 3.12.2. With explicit resource-slot authorization, only the owned Linux
container was changed to 1 CPU / 1879048192 bytes (1.75 GiB), no swap.
Each test process retained the 420-second outer hard timeout and immediate
stop-on-new-OOM check. No other container was operated by this worker.

One update-mode process selected the three runtime widget tests and generated
all 14 actual Linux runtime PNGs: handle `23252`, 3 PASS, test exit 0.
Eight differ from the old Linux baseline: `account`, `decoration`,
`dynamic_detail`, `expression`, `gift`, `home`, `messages`, and `room`
(all named `m3_3_<state>_390x844.png`). The other six are byte-identical.
All 14 were inspected against the approved same-source macOS references:
the nine-seat room, multi-recipient gift controls, deterministic decoration
expiry, comment replies, and retired-entry reflow match the approved product
changes. Linux rasterization is retained; no macOS PNG was copied.
Hubble independently inspected all 14 pairs and approved each at 99/100;
main also approved four critical pairs. Hubble's Mac references at
`b82a30c0f00e6c512232b03c1cb06d905513cf5b` have the same hashes as the
`0b9d120` reference images. All 14 generated files are preserved here; Git
records only the eight changed PNGs. The six byte-identical runtime PNGs,
gallery PNG, page archives, and all non-Linux baselines remain unchanged.

After worker visual review, five separate non-update processes each selected
exactly one existing test using `--plain-name`:

| Log | Test | Result |
| --- | --- | --- |
| `runtime-visual-strict.log` | M3.3 video-runtime visual states at 390x844 | 1 PASS / exit 0 |
| `runtime-tabs-strict.log` | M3.3 root tabs and pure decoration states at 390x844 | 1 PASS / exit 0 |
| `runtime-secondary-strict.log` | M3.3 secondary flows at 390x844 | 1 PASS / exit 0 |
| `runtime-fontgate-strict.log` | M3.3 video-runtime golden font gate fails closed when the baseline font is absent | 1 PASS / exit 0 |
| `gallery-strict.log` | preset artwork has a readable gallery and small silhouettes | 1 PASS / exit 0 |

The first four use `test/video_runtime_visual_golden_test.dart`; gallery uses
`test/preset_avatar_visual_test.dart`. All use the unchanged
`flutter test --no-pub --concurrency=1 --reporter expanded` arguments.
Sequential orchestration handle `68135` exited 0. Log-parsed test names are
five distinct expected names, each with `+1: All tests passed!`, `TEST_EXIT=0`,
and `oom_kill 0`. **This adds five unique strict PASS to the previous 61,
for 66 at the same source: 60 pages + page-font gate 1 + runtime scenes 3 +
runtime-font gate 1 + gallery 1.** Update-mode passes are excluded, and the 61
page/font tests were not rerun. Gallery PNG SHA-256 remains
`dcc912faa577d749b558734ea6510e92115291ca9589c32d7239bb0faebb9279`.

Test exits and container shutdown are separate evidence:

- Update test: exit 0. Each of five strict tests: exit 0. Orchestration: exit 0.
- All six phases: no new OOM. Observed cgroup cumulative peak:
  1645912064 bytes (about 1.533 GiB); this includes tool/compiler/tester/cache,
  not a measured standalone App process peak.
- Only after the tests completed, `docker stop --timeout 5` stopped the owned
  container. Docker recorded its PID 1 (`sleep 1800`) exit as 137 with
  `running=false` and `OOMKilled=false`. **That 137 is the container lifecycle
  result, not a Flutter test exit or an OOM in this successful run.**
- Resource slot returned; source, SDK, package/build caches and old OOM logs
  preserved. No tolerance, assertion, CI selection, or product file changed.

Workspace-root evidence:
`artifacts/product/filled-decisions-20260909/linux-runtime-final-0b9d120-1750m-8kiXeI/`.
`png-manifest.json` lists all 14 Linux/prior-Linux/reference-Mac SHA-256 values;
`linux-runtime-candidate/` holds their original generated bytes;
`worker-visual-review.json` records the worker's per-image assessment;
`independent-visual-review.md` and `independent-visual-verdict-14.json` record
Hubble's 14/14 independent APPROVE and input hashes;
`runtime-update.log`, the five strict logs, and per-phase resource logs retain
the actual runs. `terminal-result.json` records the exact distinct test set;
`container-stop.log` separately records the shutdown status.
