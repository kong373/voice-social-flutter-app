# Core-eight UI refinement — 2026-09-23

## Scope and baseline

This is a follow-up to UI PR #26 at `59c752eaf0cc8c51c4e2de4c0fdea6f10654dfa3`, not a replacement release candidate. The original GPT checkout and the frozen release checkout were left unchanged. The source was first verified against all 1,072 GitHub tree entries (`de2d1dc218816a4147d35acebd9eba7c45830e41`); once Git connectivity recovered, the exact original commit was fetched and this branch was attached to that real parent without changing the working files. The temporary independent source-snapshot root is not a substituted upstream history.

Product Design and Emil guidance was applied to the existing Flutter product: keep its light social/dark room identity and assets, improve hierarchy, target size and visible feedback, and verify actual surfaces rather than infer quality from test counts. This does not redesign navigation or add product features.

## Changes

| Surface | Refinement | Preserved behavior |
| --- | --- | --- |
| Runtime home | Stable category font size, 44 minimum category targets, 48-high create action, readable card metadata | Categories, discovery results, creation and room navigation |
| Discovery | Explicit readable author/body colors, 15/1.5 body typography, larger like/comment targets | Original like/comment callbacks and pending states |
| Messages | Inset light dividers, readable previews, times and status labels | Real conversation/read/unavailable states |
| Private chat | More bubble spacing, readable message body, 48×48 send action and distinct disabled surface | Original send condition, request recovery and delivery states |
| My | Clearer counts and service labels, subtle bottom-navigation separation | Existing role-gated destinations and statistics |
| Room | 44-minimum actual dock targets, 48-high mic action, more readable public text and dock labels | Nine seats, permissions, room/session state, management and command callbacks |
| Gift sheet | One drag indicator, clearer targets/categories/name/price; adaptive 0.82 height for short/large-text views, 0.64 otherwise | Targets, gift quantities, balances, independent outcomes, original request recovery and one-time feedback |
| Decoration | 96 preview instead of 72; compact proportional cards, 48-high adjacent renewal/wear actions, full-image preview | Ownership, expiry, unknown purchase recovery, original purchase/wear callbacks |

The active SocialPill now paints ink above its gradient while preserving the total 44 minimum target. Before/held/released frames confirm visible feedback; this is a widget-level result, not a native frame-rate claim. The room expression and gift sheets explicitly disable the theme handle because each already owns one internal handle.

## Production-theme verification

Default page renders and both golden hosts now use the same room root theme as the actual app. Local social/room scopes are retained. Before and after comparisons use identical host, fonts, dimensions, fixture clock and shadow settings. Export-only `debugDisableShadows` is restored before the Flutter binding's end-of-test invariant check; the pixel comparator and tolerances are unchanged.

This verification also exposed two narrow color-scope issues. Withdrawal history now explicitly uses social foreground colors (no financial behavior changes). The legacy `HomePage` gets a local social theme; it is currently referenced only by the QA catalog, not the real `MainShell` home. No obsolete route was restored and the legacy QA page is not presented as the current home design.

All 74 macOS baseline PNGs are included in this follow-up so the images are no longer local-only. Linux images were independently rendered on Ubuntu 24.04 / Flutter 3.44.7 by run `35768409604` from exact source `ff6c9d67ac39c0bd407c831021abf4a683b301a0`. Before import, all 269 source hashes and 74 managed image hashes were checked, contact sheets and core-page details were reviewed, and the other 10 legacy/avatar images were confirmed unchanged. 71 Linux files changed; three already matched. All 74 Linux renders have platform-specific pixel differences from macOS. They were not copied from the Mac images.

## Executed verification

Flutter 3.44.7 / Dart 3.12.2; checkout-owned package configuration and existing offline dependencies. No shared `.dart_tool` symlink, database, provider call, real payment or device operation.

- Actual room dock: four genuine failing size tests before the fix, four passing after it. Tests exercise edge taps, close/reopen and one-handle configuration.
- Press-feedback plus controls/shared targets: 11 passed. Active-pill inset-region pixel change rose from the independently reviewed 33 to 2,445; different fixture/platform metrics are not generalized as performance data.
- Relevant decoration, messaging, gift, navigation, identity/race and room regressions: 117 passed. Later gift-height changes were additionally validated by the actual modal matrix and gift result/feedback suite.
- Core layouts: 54 passed across 375×667, 390×844 and 402×874 at 1.0/1.3 text scale with simulated safe insets; room/chat keyboard checks: 12 passed.
- Actual gift/expression modal matrix: 12 passed. A newly added full-row visibility assertion first failed both 375×667 gift cases (77.72 / 68.72 viewport height), then passed after adaptive sizing. A no-overflow result alone had missed this usability problem.
- Additional interaction, role-sheet and financial states: 47 passed.
- Final base renders and financial-state renders: 84 passed (66 base/runtime/actual modal cases plus 18 financial states; not 84 distinct pages).
- macOS golden comparisons and Android/iOS source-host contracts: 90 passed. Golden regeneration was followed by normal comparison, not counted as independent visual approval.
- Android debug APK compiled successfully and its manifest label reads `搭子岛`; it is not a signed production build or an installed-device result.
- Analyze: no issues. Changed Dart files: formatting clean. Diff whitespace check: clean.

These groups overlap and must not be summed into a unique business-test total. The full all-page matrices from the previous GPT batch were not claimed as fresh runs here. Final local logs and visual comparisons accompany the task handoff.

## Remaining platform acceptance

This branch is **not a release-ready declaration**. iOS native build/install, two-platform keyboard/back/gesture and accessibility checks, profile frame timing, and the full remote CI result remain separate gates. Linux images have been reviewed and committed; the final head's normal comparison is a separately reported CI result, not inferred from generation. The current Mac reports an unaccepted Xcode license for native tooling; the existing Command Line Tools were sufficient for Flutter widget verification only. No license, signing, provider or security settings were modified.

No API/data/domain implementation, permission rule, wallet/ledger, Backend/Admin/CPS, dependency lock, signing identity or bundle ID was changed. Keep the original release candidate until native and platform evidence for this follow-up has been accepted.

## CI follow-up

The first remote catalog check exposed 11px decoration-card overflow with the standard test/fallback font. The existing `m24_pages_test` reproduced it locally; 16px of layout headroom fixed it without changing or removing assertions. The catalog/renewal group then passed 47 tests. This is a real follow-up fix, not a rerun of an unchanged failing check.

A narrowly scoped `UI Linux golden candidates` workflow runs the two existing golden suites against the committed Linux baselines before any regeneration, then records exact source and image hashes and uploads candidate images for review. A failed comparison remains a failed job even when subsequent candidate generation/upload succeeds; there is no `continue-on-error`. It does not commit files, relax comparisons, approve visual results or deploy. Its successful generation is explicitly not a passing Linux golden comparison. The unchanged full CI also runs the normal comparisons.

The remote M2.4 targeted diagnostics for `ff6c9d67ac39c0bd407c831021abf4a683b301a0` passed all eight jobs (`35768408738`), including the previously failing catalog widgets. The last production change is the 16px card headroom; importing Linux PNGs does not change application source or the independently built Android debug binary.
