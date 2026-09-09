# S05 Flutter disconnected-seat adaptation

Baseline: clean `4d4820e`; independent worker worktree only. Contract reference:
Backend `78e57d0`, `seatSnapshot` / `seatState`: occupied and user identity survive,
online is boolean, offline speaking is false. No new page or QA runner; page counts unchanged.

## Implementation and inventory

- `BackendRoomRepository` previously preserved occupied/userId but discarded online.
  Now parses explicit online strictly as bool; omission retains legacy compatibility.
- `BackendMicSeat` / `MicSeat` carry presence separately from occupancy. Mapping
  keeps backend index (including legacy seat zero), user and role. Offline cannot
  become available; speaking is suppressed when offline.
- `RoomController` publication and local toggle publication predicates now require
  online. Authority refresh can revoke publication, never grants a fresh RTC token
  or starts publication merely because online becomes true.
- Room seat UI shows `离线 · 占位保留`, including occupants without a display name.
- Management seat cards expose existing off-mic/kick operations for retained
  occupants absent from online member pagination. Only owner / room moderator
  may govern; platform staff and ordinary users cannot. Existing self/owner/peer
  moderator protections remain. Complete manager roster supplies target roles
  because Backend78e seat objects do not include manager role. Manager endpoint
  includes offline managers; client already reads all manager pages.
- No optimistic removal on failed kick. Successful off-mic refreshes authoritative
  seats; backend mic index and target user are passed unchanged.

## No change required

- `RoomController._refreshAuthorityReadOnly`: epoch/generation fences, monotonic
  version, memberActive and exact sessionId checks already reject stale results.
  No SDK presence callback writes seat online status.
- Existing room lease binding and write paths reject invalid/expired/replaced
  generations. Regression suites exercise 40936/40937, old responses after rejoin,
  account switch and disposal. Retained occupancy does not extend a lease.
- `BackendRoomOperationsRepository.takeUserOffMic/kickUser` already send original
  target ID and actor lease and verify response authority; no new route needed.
- Authoritative seat refresh was already independent of online member pagination;
  it did not erase occupants merely absent from that list.

## Validation

Actual installed SDK: Flutter **3.44.8**, Dart 3.12.2. This is not a 3.44.7 claim.
No SDK modification or installation. Initial presence regression failed on the
missing model getter; additional manager-roster behavior regression genuinely
failed because an off-mic action was incorrectly visible, then passed after fix.

First focused batch: **196 PASS**:

```sh
flutter test --no-pub test/backend_room_authority_projection_test.dart test/room_management_review_fixes_test.dart test/room_authority_sync_controller_test.dart test/room_permission_policy_test.dart test/fixed_eight_seat_adapter_test.dart test/room_lease_controller_test.dart test/backend_room_lease_repository_contract_test.dart test/room_management_seat_layout_test.dart
```

After manager-roster fix, affected/additional batch: **130 PASS** (overlaps above;
do not add these counts as distinct cases):

```sh
flutter test --no-pub test/room_management_review_fixes_test.dart test/room_management_seat_layout_test.dart test/backend_room_repository_contract_test.dart test/backend_room_operations_repository_contract_test.dart test/room_role_mic_policy_test.dart test/room_controller_rtc_transition_test.dart test/room_controller_race_test.dart
```

Full `flutter analyze --no-pub`: 0 issues. `git diff --check`: clean.
No golden comparison/update, device, vendor, DB, build, or live endpoint execution.
Offline kick server addition remains Ampere-owned; UI failure/retained-seat behavior
is verified, actual offline kick end-to-end is not claimed. Flutter3.44.7 rerun not done.

## Changed files

- lib/features/room/data/backend_room_repository.dart
- lib/features/room/domain/fixed_eight_seat_adapter.dart
- lib/features/room/domain/room_models.dart
- lib/features/room/domain/room_permission_policy.dart
- lib/features/room/application/room_controller.dart
- lib/features/room/presentation/room_management_page.dart
- lib/features/room/presentation/video_runtime_room_page.dart (seat widget only)
- test/backend_room_authority_projection_test.dart
- test/room_authority_sync_controller_test.dart
- test/room_management_review_fixes_test.dart
- test/room_permission_policy_test.dart
- docs/qa/disconnected-seat-flutter-20260909.md

No PK, youth, nickname, withdrawal, Backend, runner or golden file edits.
