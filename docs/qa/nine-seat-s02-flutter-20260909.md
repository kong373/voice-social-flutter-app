# S02 1+8 nine-seat Flutter handoff

Baseline: clean `75f63fc` (contains S05 and withdrawal4d4820). Source decision:
`artifacts/product/filled-decisions-20260909/supplement-answers.json` S02:
1号麦只有管理员或者房主可以上; Q06-01 context confirms 1+8 and distinct style.
All source writes limited to independent Flutter worker tree; no Backend changes.

## Wire and authority

- Canonical seats use `index=seat_number=1..9`. No truncation: all nine occupied
  seats are preserved, including offline ninth, user IDs and backend indices.
- Explicit index0 selects legacy 0..8 compatibility; the displayed positions are
  1..9 while backend indices remain 0..8. Mixed 0+9, duplicates or out-of-range
  indices fail protocol validation rather than silently losing an occupant.
  No real index0 is inferred from an absent canonical1.
- Class `FixedEightSeatAdapter` name retained for source compatibility only;
  implementation always yields nine seats. This baseline has no RoomSeatLayout
  class. No unrelated renaming or feature flag introduced.
- S05 online bool and occupied remain independent; no SDK-based presence merge.
  Existing lease/generation fences and RTC credential checks remain unchanged.
- First seat use permits exactly owner/moderator, never platformModerator/staff.
  Controller rejects ordinary first-seat requests before a write; ordinary queue
  repository submissions allow2..9 only. Owner/moderator direct flow unchanged.
  Historical queue records may still parse seat1; display history is not a grant.
- Assignment/invitation and queue/member validators accept9. Ordinary-member
  assignment picker excludes1; Mock assignment also restricts ordinary2..9.
  Mock invitation1 checks actual target owner/moderator role.
- Existing complete manager roster supplies offline target roles for S05
  governance; no reliance on seat role field being added by Backend.

## UI and scope

Main room stage is one dedicated special seat above eight ordinary seats in a
four-column grid. Seat1 has larger gold-ring avatar and special label, retaining
occupant name and offline label. Stage remains scrollable on short screens and
with keyboard. Empty first seat is absent from ordinary picker;9 stays selectable.
Management special label and ordinary assignment picker aligned. Mock room has9.
Creation/configuration copy now says1+8 rather than fixed8.

Current PK preparation selects opponent ROOM, not mic seats; search found no
eight-seat selector/truncation in PK module. No PK state machine/code edit needed.

No page retired or added; page manifest count unchanged. No new runner. Old golden
impact was reported before implementation; no golden image or gate changes.

## Tests

Pinned binary verified before running:
`/Users/kongzheng/fvm/versions/3.44.7/bin/flutter --version`
Flutter3.44.7, revision84fc5cbb22, Dart3.12.2. No SDK/fvm edits.

TDD: adapter legacy and canonical nine-seat cases genuinely RED (2 failures:
actual8 vs expected9), then GREEN. Existing eight-seat assertions updated to9;
lease-negative request fixtures use ordinary seat2 to preserve original lease
denial checks instead of testing special-seat validation accidentally.

Batch A **150 PASS**:

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/fixed_eight_seat_adapter_test.dart test/backend_room_repository_contract_test.dart test/backend_room_operations_repository_contract_test.dart test/room_controller_test.dart test/room_role_mic_policy_test.dart test/room_mic_queue_controller_test.dart test/room_mic_queue_ui_test.dart test/room_management_review_fixes_test.dart test/room_authority_sync_controller_test.dart
```

Batch B **193 PASS**:

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/backend_room_authority_projection_test.dart test/backend_room_lease_repository_contract_test.dart test/room_lease_controller_test.dart test/room_operations_repository_test.dart test/room_management_seat_layout_test.dart test/room_management_automatic_sync_test.dart test/room_avatar_contract_test.dart test/room_controller_rtc_transition_test.dart test/room_controller_race_test.dart
```

Final stronger empty1/picker and ninth-assignment UI cases: **21 PASS** in
`test/room_mic_queue_ui_test.dart test/room_management_review_fixes_test.dart`.
These overlap batch A; do not add overlapping counts as unique cases.
Full pinned `flutter analyze --no-pub`: no issues. `git diff --check`: clean.

## Explicit remaining integration work

- Backend V54/seat1 server authorization is Ampere-owned; no live/DB verification
  in this task. New seat wire must expose index1..9. No extra field required.
- Outside room-module scope, existing room-card totals still say /8:
  `lib/features/shell/video_runtime_pages.dart:898`,
  `lib/features/discovery/presentation/saved_rooms_page.dart:291`,
  `lib/features/discovery/presentation/search_results_page.dart:431`,
  `lib/features/discovery/home_page.dart:461,525` (also tiny seat indicator clamp),
  `lib/features/discovery/dynamic/data/mock_dynamic_repository.dart:269,277,285`.
  Left untouched for main discovery/shell integration, including related tests.
- Golden suite `video_runtime_visual_golden_test.dart` room/expression/gift and
  management images, and room entries in `m33_all_pages_visual_golden_test.dart`
  need separately reviewed visual baseline changes; neither run nor updated here.
- No full suite, golden, device, vendor, build, DB or live Backend tests executed.

Changed production files are ten room files: room_controller;
backend_room_operations_repository; mock_room_operations_repository;
mock_room_repository; fixed_eight_seat_adapter; room_models; create_room_page;
room_configuration_form; room_management_page; video_runtime_room_page.
Eight existing test files plus this document complete the commit. No temporary
editing scripts, youth/financial/withdrawal/nickname/Backend/PK changes.

## Review follow-up: Mock special-seat target role

Corrected assignUserToMic's overly broad special-seat rejection. It now checks
the target's CURRENT role: owner/moderator may be assigned1, ordinary/staff may
not; range1..9, occupied-seat conflict and already-on-mic checks remain. Assignment
and off-mic preserve management roles, so leaving a seat does not demote its owner.
Default MockRoomRepository seat1 was already owner20001, not an ordinary user.
Owned-room configuration now uses the actual snapshot owner ID instead of20001.
This supersedes the earlier blanket Mock assignment2..9 description above.

Owner/moderator tests: genuine2 RED then GREEN. Current-role demotion, staff and
ordinary denial, occupied-seat uniqueness and owned-room identity also covered.
Pinned3.44.7: **38 PASS**, full analyze no issues, diff-check clean:

```sh
/Users/kongzheng/fvm/versions/3.44.7/bin/flutter test --no-pub test/room_operations_repository_test.dart test/room_role_mic_policy_test.dart test/room_management_review_fixes_test.dart test/room_mic_queue_controller_test.dart test/room_mic_queue_ui_test.dart
```

No S05 presence mapping, Backend, golden or SDK files changed.
# Main integration verification — 2026-09-09

Integrated as `2e5685d401905e1ad81c8e896a6a92d79a7dac6c`, preserving the main-only closed-room card label while changing its open-room total to nine. Pinned Flutter 3.44.7: 13 related files, **254 PASS**, session65967 exit0; full `flutter analyze --no-pub` session31974 exit0, no issues. Parent workspace evidence: `artifacts/product/filled-decisions-20260909/s02-flutter-merged.log` and `s02-flutter-merged-analyze.log`.

Backend merged ac512ed has 24 targeted tests/SpotBugs0, including the canonical owner corrections. No golden update, runtime deployment, native build or ordinary-device acceptance is claimed by these source checks.
