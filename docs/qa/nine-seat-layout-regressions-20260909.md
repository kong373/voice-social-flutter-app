# Nine-seat runtime UI regression follow-up

Base: `dd66c076263f10f860225ac4b794dfcd84f559b1`.
Branch: `codex/flutter-nine-seat-layout-regressions-20260909`.
Only the two reported cases in `test/video_runtime_ui_test.dart` and this document
change. No production UI, mic policy, permissions, media, Backend or golden edits.

## Decision and actual rendering

Q06-01 in the filled `answers.json` says “1+8  1号麦为特殊麦位 样式要不一样”.
Supplement S02 limits seat1 to room owner/manager. The frozen visual contract is
[nine-seat S02 handoff](nine-seat-s02-flutter-20260909.md): a centered special
seat above eight ordinary seats in four columns, larger gold-ring avatar, special
label, and scrolling at constrained heights. Also read
[card totals](nine-seat-card-totals-20260909.md) and
[room rules](../room-rules-checkpoint-20260909.md). This patch does not retest or
change the permission policy.

The existing `m3_3_room_390x844.png` golden depicts the old two-by-four layout;
it is not the approved nine-seat visual reference. The S02 handoff explicitly left
that golden update outstanding. It remains unchanged here.

In `VideoRuntimeRoomPage._roomContentBody`, the ordinary-state seat viewport grew
from 218 at pre-S02 `75f63fc` to 330 for the separate special row plus two ordinary
rows. `_publicScreen` uses a compact, scrolling mood stage below 420 logical
pixels of available public-screen height. `_VideoMicSeat` implements the larger
gold ring and special label. Actual widget-rendered screenshots show all nine
seats, the expected row/column structure, readable public feed and reachable dock.
No production layout correction is warranted for these two viewports.

| Old failure at dd66c07 | Confirmed cause | Replacement checks |
| --- | --- | --- |
| 390×844: missing `video-room-mood-stage-standard` | Nine-seat viewport leaves less than 420px for the public screen, selecting the existing compact branch. | Exactly nine visible avatars; special1 centered above two four-column rows; larger gold ring and special label; compact stage inside the scrolling feed. |
| 360×764 / 1.3× text: expected public screen 340×395, actual 340×283 | Extra seat-row budget is exactly 330−218=112px; 395−112=283. The old constant assumed eight seats. | Ten-pixel horizontal gutters; seat viewport + public screen + existing 4px bottom padding equals the shared layout budget; no seat overlap/clipping or composer overlap; all toolbar actions reachable. No hard-coded 283px expectation. |

## Preserved and strengthened interaction coverage

- First case retains home-to-room routing, composer/expression controls, gift
  sheet, minimization and reopening. Nine-seat geometry is checked before and
  after minimization; overflow exceptions still fail the test.
- Constrained case retains 360px width, 1.3× text scaling, composer/expression,
  gift-to-tools transition, interaction/tools tabs, system back and overflow
  checks. Painted seat avatars are hit-tested: the dense special-seat layout box
  includes transparent spacing, whose center is not an interactive surface.
- New S09 behavior is asserted through actual App dependencies with the Mock
  commerce repository: two current recipients, distinct immutable request keys
  and transfer IDs, two confirmed result rows, then one feedback per recipient.
  The exact wallet delta is 200 tenths for two 10-coin gifts. Results remain until
  explicit dismissal; the completion button is reachable, system back closes the
  sheet, and tools remain usable. No synthetic batch success or legacy automatic
  pop is expected. This is not a live HTTP/financial test; prior strict-receipt
  HTTP tests were not rerun or counted in this follow-up.
- The other nine cases in this test file are unchanged, including keyboard,
  narrow-screen overflow and navigation coverage. No disabled/skipped test or
  golden-threshold relaxation was introduced.

## Rendered evidence

Artifacts are local, ignored by the repository's existing `artifacts/` rule, and
retained for review. They are Flutter widget renders, not device/vendor captures.
The capture helper is opt-in via `ROOM_LAYOUT_EVIDENCE_DIR`; it loads existing
test fonts and precaches image assets. Normal runs do not write screenshots.

- [390×844 before](../../artifacts/qa/nine-seat-layout-20260909/before/room-390x844.png)
  / [after](../../artifacts/qa/nine-seat-layout-20260909/after/room-390x844.png)
- [360×764, 1.3× before](../../artifacts/qa/nine-seat-layout-20260909/before/room-360x764-text130.png)
  / [after](../../artifacts/qa/nine-seat-layout-20260909/after/room-360x764-text130.png)
- [Per-recipient success feedback](../../artifacts/qa/nine-seat-layout-20260909/after/gift-results-360x764-text130.png)
  / [completed results and explicit control](../../artifacts/qa/nine-seat-layout-20260909/after/gift-results-complete-360x764-text130.png)
- [Tools](../../artifacts/qa/nine-seat-layout-20260909/after/tools-360x764-text130.png)
  / [minimized home](../../artifacts/qa/nine-seat-layout-20260909/after/minimized-390x844.png)

Before images were captured with the same font/asset instrumentation while the
original assertions still failed. Before and after room images are byte-identical:

```text
390x844: d027811d0c147562da93f1b62053cfc88d4532a92fb5e4f05089a9125ac669c2
360x764-text130: 06348c9ff5c01ec89835cbed9782f226d24c3340774c1e698a6aa727ef7710b6
```

The checked-in test font subset (`test/fonts/M3GoldenCjk.charset.txt`) lacks
`特` and `殊`; those glyphs appear as boxes in captures. This is a verified test
font limitation, not evidence about native font fallback. No font/golden update
is included. Visual comparison validates frozen geometry and these interactions,
not full typography, old-golden equality or native-device acceptance.

## Actual verification

Pinned Flutter 3.44.7 at `/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7`.

| Run | Terminal result |
| --- | --- |
| Untouched base, reported two cases, handle3877 | exit1: both original failures reproduced |
| Before screenshots with asset precache, handle41439 | exit1: same two original failures |
| Full `video_runtime_ui_test.dart`, handle34582 | exit0: 11 PASS, no failures/skips |
| Final two cases after stronger count/completion/back checks, handle36790 | exit0: 2 PASS; subset of the above 11, not extra unique cases |
| Final full `flutter analyze --no-pub`, handle56632 | exit0: no issues |

During test development, handle72156 had one false failure from hit-testing a
transparent cell center; changing the check to the painted avatar resolved it.
The original two-case GREEN was handle79390 / exit0. No earlier failures are
being reported as passes. Full-file JSON evidence is
`artifacts/qa/nine-seat-layout-20260909/video-runtime-tests.jsonl`.

Reproduction (from this worktree):

```sh
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub --reporter expanded --dart-define=ROOM_LAYOUT_EVIDENCE_DIR=artifacts/qa/nine-seat-layout-20260909/after test/video_runtime_ui_test.dart --name 'home enters room, opens gift sheet and minimizes the session|room gift to tools remains stable at cloud-constrained'
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter test --no-pub test/video_runtime_ui_test.dart
/Users/kongzheng/Documents/ny/.tooling/flutter-3.44.7/bin/flutter analyze --no-pub
```

NOT_RUN: full Flutter suite, golden suite/update, native build/device acceptance,
Backend/DB/Testcontainers, vendor calls, deployment and actual gift transfers.
Main worktree is untouched; this is a local-only append commit.
