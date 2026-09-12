# 2026-09-10 macOS release golden review

## PK automatic-sync follow-up

Source `e5bf9c7229786d36b410f61faf4ae7cd838bdac5` changes RM-013's
manual-refresh explanation to the implemented foreground HTTP synchronization
with explicit invitation acceptance. Main reviewed both comparator-produced
master/test images and the isolated diff: only this two-line explanation
changes; geometry, contrast and the other controls remain unchanged. The
macOS RM-013 test failed against the previous baseline, then its new actual
render passed a separate non-update comparison (1/1). This follow-up updates
only `test/goldens/m3_3_all/rm-013_390x844.png`; Linux is verified separately.
Main PK/repository/permission/media/font batch also passed 107 tests, not a
replacement for the complete release suite. Evidence is in
`artifacts/product/filled-decisions-20260909/flutter-pk-rm013-golden-{red,generate,strict}-20260910.log`
and `flutter-main-pk-e5bf9c7-20260910.log` under the workspace root.

## Earlier complete macOS review

Render source: `d97cbda7ef2c7a6aa3c835c4547f4283a793fe3e`.
Exact Flutter 3.44.7 / Dart 3.12.2, macOS, 390×844 / DPR 1.0; the
unchanged preset-avatar gallery uses its own 360×460 viewport.
This commit updates **32 reviewed macOS PNGs only**. Linux is separate and
is not approved or refreshed by this record. Neither comparator tolerance,
viewport, font scale, error handling nor test selection was weakened.

## Review scope

The active catalog contains 60 pages. There are 14 independent runtime-state
captures; the retained 69-page directory includes nine retired-page archives
and is not a claim of 69 currently active pages. Existing RM001/RM005 PNGs show
the owned-room selection and room view respectively. Their create-form and
listener approval-picker states have separate behavior tests; these PNGs must
not be described as screenshots of those two additional states.

| Reviewed files / group | Accepted reason |
| --- | --- |
| `m3_3_all/ac-002`, `ac-005` | Pinned Noto font subset now includes current fixed CJK text; camera/consent missing glyphs render correctly. Notification copy references private messages, not retired friend requests. |
| `m3_3_all/ac-012` | Approved PIN-based whole-app youth lock and its accurate recovery explanation. |
| `m3_3_all/ds-001`, `ds-003`, `ds-008`, runtime home | Approved nine-seat counts/layout. DS001 also has the verified small-screen flexible seat summary and correct dark-card text context. |
| `m3_3_all/ds-005`, runtime dynamic_detail | Approved reply action button and resulting comment wrapping. |
| `m3_3_all/ds-006` | Truthful Mock text-only publishing state; not proof or disproof of live image publishing. |
| `m3_3_all/ds-007` | Contribution rank retired; remaining three gift-value ranks show exact currency, pagination and explicit demo state. |
| `m3_3_all/us-001`, `ms-001`, runtime account/messages | Approved removal of friend-request/activity entries with remaining entries reflowed. |
| `m3_3_all/us-002` | Approved Beijing-time daily nickname limit. |
| `m3_3_all/rm-001` | Approved owned-room selection before creation; room title now reads its actual dark subtree theme. |
| `m3_3_all/rm-002`, `rm-004`, `rm-005`, runtime room/expression | Special owner/admin seat plus eight ordinary seats; corrected special-seat glyphs and compact public-screen layout. |
| `m3_3_all/rm-013`, `rm-014` | Ordinary PK/theme-only rules and no surrender. RM013 section titles now read the dark subtree theme. |
| `m3_3_all/cm-001`, `cm-012` | Frozen gift-coin display and approved manual withdrawal rules; historical amounts/dates remain unchanged. |
| `m3_3_all/cm-002` | No recharge bonus; current product amounts and intact two-column responsive cards. |
| `m3_3_all/cm-010`, runtime decoration | Approved preview/duration/renewal UI; fixed mock clock produces Sep 19 / Sep 3 expiry at 20:39 for QA and 18:12 for runtime fixtures, not machine time. |
| `m3_3_all/sc-001`, `sc-002` | Approved guild-chair/anchor roles, corresponding deterministic Mock identity and retired check-in copy. |
| runtime gift | Approved multi-recipient actions, authoritative Mock balance 1680 and refresh control; underlying nine-seat room. |

File names in the table abbreviate the unchanged `_390x844.png` suffix and
`m3_3_` runtime prefix. All 24 page images and eight state images were compared
against their tracked prior image. The earlier failed-run images are retained
separately; unrelated old `test/failures` files were not used as current evidence.

## Defects fixed before accepting the images

- CM002 360×800 / 1.3×: actual 2px bottom overflow, fixed without dropping
  information or shrinking text; related 43-test worker gate passed.
- DS001 same small viewport: actual 12px right overflow, fixed with flexible
  nine-seat indicators. Main combined gate passed both sizes, each traversing
  all 60 active pages. These are two test cases, not 120 distinct tests.
- Decoration's missing mock-clock injection: deterministic expiry regression.
- Both test-font weights: 74 glyphs added, none removed; all 935 current `lib`
  CJK characters covered. Same pinned Noto sources/weights/SIL OFL license.
- RM001, RM013 and DS001 explicit text styles previously used an outer light
  context despite a dark surface. Actual RenderParagraph color regressions
  failed first and passed after the local context fixes.

## Verification

Main targeted gates: font/room-state 12 PASS, dark-context 6 PASS, preset with
the updated font 1 PASS. Mac regeneration's 65 update-mode tests only establish
render completion, not approval. After the final two-page correction, a new
**strict, non-update 66-test** invocation passed:

```sh
flutter test --no-pub --concurrency=1 --reporter=expanded \
  test/m33_all_pages_visual_golden_test.dart \
  test/video_runtime_visual_golden_test.dart \
  test/preset_avatar_visual_test.dart
```

Main visually checked critical room/recharge/decoration screens. Independent
review by Parfit first rejected the real contrast/font defects, then reviewed
all 32 resulting pairs and finally approved the corrected RM013/DS001 images.
This is not device, provider, live-business or whole-suite release acceptance.
The prior whole suite on `8fc6cd5` remains a historical 3280 PASS / 44 FAIL run;
it is not relabeled successful by these targeted results.

Workspace evidence root: `artifacts/product/filled-decisions-20260909/`,
including `pre-repair-goldens-8fc6cd5/`, `flutter-mac-golden-render-20260910.log`,
`flutter-mac-two-page-render-20260910.log`,
`flutter-mac-strict-goldens-20260910.log`,
`flutter-font-room-main-20260910.log` and
`flutter-dark-context-main-20260910.log`.

## 2026-09-13 controlled avatar and profile-capability refresh

The later app source is `4e78573f5fd00fffbe70c9ed274b7c31a7342fa8`, including
`1bc3c8d` canonical dynamic-author projection and `2a7aff0` controlled profile
avatar editing. Main reviewed the four current macOS `testImage` captures
against their matching master/diff diagnostics. This follow-up updates only
these four macOS PNGs; Linux is refreshed separately from its own renderer:

- `test/goldens/m3_3_all/ds-004_390x844.png`
- `test/goldens/m3_3_all/ds-005_390x844.png`
- `test/goldens/m3_3_dynamic_detail_390x844.png`
- `test/goldens/m3_3_all/us-002_390x844.png`

The dynamic Mock fixture retains null canonical avatar descriptors. The
reviewed output is consequently the secure neutral `UserAvatarView` fallback,
not a newly invented PRESET identity and not the retired `RuntimeAvatar` or
URL fallback. The positive canonical-descriptor and missing-descriptor
contracts remain unchanged. In US-002, the Mock environment has no avatar
media transport, so the reviewed unavailable-capability branch shows the
`photo_library` icon and current avatar-editing message.

The source-render check used local Flutter 3.44.7 / Dart 3.12.2 at 390 x 844,
DPR 1.0, with `--concurrency=1`; the only selected test cases were DS-004,
DS-005, US-002 and `M3.3 secondary flows`. The latter's first affected capture
was dynamic detail; after its baseline update, its remaining captures also
completed. All four intentionally failed against the old Mac baselines before
refresh; the diagnostics are retained at
`artifacts/release/ci-golden-isolation-34711980135-20260913/macos-targeted-20260913/`.
No comparator tolerance, test logic, font, or unrelated baseline changed.
